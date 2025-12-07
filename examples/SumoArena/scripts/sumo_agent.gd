extends CharacterBody3D
## Sumo Agent - Controls movement and physics for sumo-style combat.
##
## This script handles:
## - Movement (forward/backward, turning)
## - Physics (velocity, friction, gravity)
## - Collision response (pushing other agents)
## - Fall detection
## - Input from keyboard (testing) or AI controller (training)

# Signals
signal fell_off

# Physics constants
const MASS: float = 10.0
const MOVE_FORCE: float = 50.0
const MAX_SPEED: float = 8.0
const TURN_SPEED: float = 3.0
const FRICTION: float = 0.03
const GRAVITY: float = 9.8
const FALL_THRESHOLD: float = -1.0
const ARENA_RADIUS: float = 6.0

# Charge ability constants
const CHARGE_DURATION: float = 0.3
const CHARGE_COOLDOWN: float = 1.5
const CHARGE_SPEED_MULT: float = 2.5
const CHARGE_TURN_MULT: float = 0.2  # Reduced turning while charging

# Collision constants
const PUSH_FORCE_MULT: float = 2.0  # Base push multiplier
const CHARGE_PUSH_MULT: float = 1.5  # Extra push when charging

# Swing attack constants
const SWING_DURATION: float = 0.2        # Wind-up + active frames
const SWING_COOLDOWN: float = 2.0        # Longer than charge
const SWING_PUSH_MULT: float = 5.0       # Much stronger than charge
const SWING_ARC: float = 120.0           # Degrees - hits in front-left or front-right
const SWING_RANGE: float = 1.5           # Slightly beyond body collision range

# Agent configuration
@export var player_id: int = 1
@export var agent_color: Color = Color(0.3, 0.5, 0.8, 1.0)
@export var debug_logging: bool = false

# Input state (from keyboard or AI)
var input_move: float = 0.0
var input_turn: float = 0.0
var input_charge: bool = false

# Charge ability state
var is_charging: bool = false
var charge_timer: float = 0.0
var charge_cooldown: float = 0.0

# Swing attack state
var is_swinging: bool = false
var swing_timer: float = 0.0
var swing_cooldown: float = 0.0
var swing_direction: int = 0  # -1 = left, 0 = none, 1 = right
var input_swing: int = 0  # Input from keyboard or AI

# Debug log file
var log_file: FileAccess = null

# Reference to enemy (set by arena manager)
var enemy: CharacterBody3D = null

# Reference to arena center (for multi-arena support)
var arena_center: Vector3 = Vector3.ZERO

# Spawn state (for reset)
var spawn_position: Vector3
var spawn_rotation: float

# RL state
var is_controlled_by_ai: bool = false
var accumulated_reward: float = 0.0
var episode_ended: bool = false

# Reference to AI controller (set automatically if present)
var ai_controller: Node = null

# Arm mesh references
@onready var left_arm: MeshInstance3D = $LeftArm
@onready var right_arm: MeshInstance3D = $RightArm
@onready var impact_particles: GPUParticles3D = $ImpactParticles


func _ready() -> void:
	# Check for AI controller child
	ai_controller = get_node_or_null("AIController3D")
	if ai_controller:
		# Will be set to AI control when heuristic changes from "human"
		pass
	# Save initial spawn state
	spawn_position = global_position
	spawn_rotation = rotation.y

	# Open debug log file
	if debug_logging:
		var log_path = "user://sumo_debug_agent%d.log" % player_id
		log_file = FileAccess.open(log_path, FileAccess.WRITE)
		if log_file:
			log_file.store_line("=== Sumo Agent %d Debug Log ===" % player_id)
			log_file.store_line("Log path: %s" % ProjectSettings.globalize_path(log_path))
			print("Agent %d logging to: %s" % [player_id, ProjectSettings.globalize_path(log_path)])

	# Apply agent color to mesh with emissive glow
	var mesh = $MeshInstance3D
	if mesh:
		var material = mesh.get_surface_override_material(0)
		if material:
			material = material.duplicate()
			material.albedo_color = agent_color
			# Add emissive glow
			material.emission_enabled = true
			material.emission = agent_color
			material.emission_energy_multiplier = 0.3
			mesh.set_surface_override_material(0, material)

	# Apply darker color to arm meshes
	if left_arm and right_arm:
		var arm_material = StandardMaterial3D.new()
		arm_material.albedo_color = agent_color.darkened(0.2)
		arm_material.emission_enabled = true
		arm_material.emission = agent_color.darkened(0.2)
		arm_material.emission_energy_multiplier = 0.2
		left_arm.set_surface_override_material(0, arm_material)
		right_arm.set_surface_override_material(0, arm_material.duplicate())


func debug_log(msg: String) -> void:
	if debug_logging and log_file:
		log_file.store_line("[%.2f] %s" % [Time.get_ticks_msec() / 1000.0, msg])
		log_file.flush()


func _physics_process(delta: float) -> void:
	# Determine control mode: use keyboard if heuristic is "human" or no AI controller
	var use_keyboard = true
	if ai_controller and ai_controller.heuristic != "human":
		use_keyboard = false

	# Get input
	if use_keyboard:
		get_keyboard_input()
	# else: AI input is set externally via set_action()

	# Apply movement
	apply_movement(delta)

	# Process swing attack
	process_swing(delta)

	# Update arm visuals
	update_arm_visuals()

	# Check for fall
	check_fall()

	# Calculate shaping rewards
	calculate_shaping_rewards()

	# Step penalty for RL - increases with distance to discourage passive play
	if not episode_ended and enemy:
		var distance_to_enemy = (enemy.global_position - global_position).length()
		var proximity_factor = clamp(distance_to_enemy / (ARENA_RADIUS * 2), 0.0, 1.0)
		accumulated_reward -= 0.001 * (1.0 + proximity_factor)  # -0.001 close, -0.002 far


func get_keyboard_input() -> void:
	if player_id == 1:
		input_move = Input.get_axis("p1_backward", "p1_forward")
		input_turn = Input.get_axis("p1_turn_right", "p1_turn_left")
		input_charge = Input.is_action_just_pressed("p1_charge")
		# Swing input (Q = left, E = right)
		if Input.is_action_just_pressed("p1_swing_left"):
			input_swing = -1
		elif Input.is_action_just_pressed("p1_swing_right"):
			input_swing = 1
		else:
			input_swing = 0
	else:
		input_move = Input.get_axis("p2_backward", "p2_forward")
		input_turn = Input.get_axis("p2_turn_right", "p2_turn_left")
		input_charge = Input.is_action_just_pressed("p2_charge")
		# Swing input (U = left, O = right)
		if Input.is_action_just_pressed("p2_swing_left"):
			input_swing = -1
		elif Input.is_action_just_pressed("p2_swing_right"):
			input_swing = 1
		else:
			input_swing = 0


func apply_movement(delta: float) -> void:
	# Update charge cooldown
	if charge_cooldown > 0:
		charge_cooldown -= delta

	# Update charge timer
	if is_charging:
		charge_timer -= delta
		if charge_timer <= 0:
			is_charging = false

	# Check for new charge activation
	if input_charge and not is_charging and charge_cooldown <= 0:
		is_charging = true
		charge_timer = CHARGE_DURATION
		charge_cooldown = CHARGE_COOLDOWN

	# Clear charge input (it's a one-shot trigger)
	input_charge = false

	# Apply rotation (reduced while charging)
	var turn_mult = CHARGE_TURN_MULT if is_charging else 1.0
	rotate_y(input_turn * TURN_SPEED * turn_mult * delta)

	# Calculate forward force (F = ma -> a = F/m)
	# Boosted while charging
	var speed_mult = CHARGE_SPEED_MULT if is_charging else 1.0
	var acceleration = (input_move * MOVE_FORCE * speed_mult) / MASS
	var move_direction = -transform.basis.z  # Forward is -Z in Godot
	velocity += move_direction * acceleration * delta

	# Apply friction (velocity decay)
	velocity.x *= (1.0 - FRICTION)
	velocity.z *= (1.0 - FRICTION)

	# Clamp horizontal speed (higher limit while charging)
	var max_speed = MAX_SPEED * speed_mult
	var horiz_vel = Vector3(velocity.x, 0, velocity.z)
	if horiz_vel.length() > max_speed:
		horiz_vel = horiz_vel.normalized() * max_speed
		velocity.x = horiz_vel.x
		velocity.z = horiz_vel.z

	# Apply gravity
	velocity.y -= GRAVITY * delta

	# Move and handle collisions
	var pre_velocity = velocity
	move_and_slide()

	var collision_count = get_slide_collision_count()
	if collision_count > 0:
		debug_log("Collisions: %d, vel_before: %.2f, vel_after: %.2f" % [collision_count, pre_velocity.length(), velocity.length()])

	# Handle pushing other agents
	for i in collision_count:
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		var collider_name = collider.name if collider else "null"

		debug_log("  [%d] Collider: %s, is_char: %s, normal: %s" % [i, collider_name, collider is CharacterBody3D, collision.get_normal()])

		if collider is CharacterBody3D and collider != self:
			# Calculate push based on our velocity
			var push_direction = -collision.get_normal()
			var push_strength = pre_velocity.length() * PUSH_FORCE_MULT
			# Charging hits harder
			if is_charging:
				push_strength *= CHARGE_PUSH_MULT
			debug_log("  -> PUSH! dir: %s, strength: %.2f" % [push_direction, push_strength])
			collider.apply_push(push_direction * push_strength)

			# Momentum reward for hard hits
			if push_strength > MAX_SPEED * 1.5:
				accumulated_reward += 0.05 * (push_strength / MAX_SPEED)
				# Spawn impact particles
				spawn_impact_effect(collision.get_position(), push_strength / MAX_SPEED)


func apply_push(push_vector: Vector3) -> void:
	velocity += push_vector


func process_swing(delta: float) -> void:
	# Update swing cooldown
	if swing_cooldown > 0:
		swing_cooldown -= delta

	# Update swing timer
	if is_swinging:
		swing_timer -= delta
		if swing_timer <= 0:
			is_swinging = false
			execute_swing_hit()

	# Check for new swing activation
	if input_swing != 0 and not is_swinging and swing_cooldown <= 0:
		is_swinging = true
		swing_direction = input_swing
		swing_timer = SWING_DURATION
		swing_cooldown = SWING_COOLDOWN

	# Clear swing input (it's a one-shot trigger)
	input_swing = 0


func execute_swing_hit() -> void:
	# Check if enemy is in swing arc
	if enemy == null:
		return

	var to_enemy = enemy.global_position - global_position
	var distance = to_enemy.length()

	if distance > SWING_RANGE:
		return  # Out of range

	# Calculate angle to enemy in local space
	var local_to_enemy = to_enemy * global_transform.basis
	var angle_to_enemy = atan2(local_to_enemy.x, -local_to_enemy.z)
	var angle_deg = rad_to_deg(angle_to_enemy)

	# Check if enemy is in swing arc
	# Left swing (-1) hits left side (negative angles), right swing (1) hits right side
	var arc_center = swing_direction * 45.0
	var arc_half = SWING_ARC / 2.0

	if abs(angle_deg - arc_center) <= arc_half:
		# HIT! Apply powerful push
		var push_dir = to_enemy.normalized()
		var push_strength = SWING_PUSH_MULT * MAX_SPEED
		enemy.apply_push(push_dir * push_strength)

		# Momentum reward for landing swing hit
		accumulated_reward += 0.15

		# Spawn impact particles at enemy position
		spawn_impact_effect(enemy.global_position, 2.0)

		print("Agent %d SWING HIT! Strength: %.1f" % [player_id, push_strength])


func update_arm_visuals() -> void:
	if left_arm == null or right_arm == null:
		return

	# Reset both arms to resting position
	left_arm.rotation_degrees = Vector3(0, 0, 0)
	right_arm.rotation_degrees = Vector3(0, 0, 0)

	if is_swinging:
		# Swing animation - rotate arm forward
		var swing_progress = 1.0 - (swing_timer / SWING_DURATION)
		var swing_angle = swing_progress * 90.0  # 0 to 90 degrees forward

		if swing_direction == -1:  # Left swing
			left_arm.rotation_degrees.x = -swing_angle
		elif swing_direction == 1:  # Right swing
			right_arm.rotation_degrees.x = -swing_angle


func spawn_impact_effect(pos: Vector3, intensity: float) -> void:
	if impact_particles == null:
		return
	impact_particles.global_position = pos
	impact_particles.amount = int(8 + intensity * 12)
	impact_particles.restart()
	impact_particles.emitting = true


func calculate_shaping_rewards() -> void:
	if enemy == null or episode_ended:
		return

	# Edge pressure: reward when enemy is closer to edge than us
	var my_pos_relative = global_position - arena_center
	var my_edge_dist = ARENA_RADIUS - Vector2(my_pos_relative.x, my_pos_relative.z).length()
	var enemy_pos_relative = enemy.global_position - arena_center
	var enemy_edge_dist = ARENA_RADIUS - Vector2(enemy_pos_relative.x, enemy_pos_relative.z).length()

	# Small reward when we have positional advantage (enemy closer to edge)
	if enemy_edge_dist < my_edge_dist:
		accumulated_reward += 0.002 * (my_edge_dist - enemy_edge_dist)


func check_fall() -> void:
	if global_position.y < FALL_THRESHOLD and not episode_ended:
		print("Agent %d fell off!" % player_id)
		episode_ended = true  # Prevent repeated signals
		fell_off.emit()


# RL Interface methods
func get_obs() -> Array:
	if enemy == null:
		return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

	var obs = []

	# Angle to enemy (sin/cos to avoid discontinuity)
	var to_enemy = enemy.global_position - global_position
	var local_to_enemy = to_enemy * global_transform.basis
	var angle = atan2(local_to_enemy.x, -local_to_enemy.z)
	obs.append(sin(angle))  # 0
	obs.append(cos(angle))  # 1

	# Distance to enemy (normalized)
	var max_distance = ARENA_RADIUS * 2.0
	obs.append(clamp(to_enemy.length() / max_distance, 0.0, 1.0))  # 2

	# Distance to edge (0 = edge, 1 = center) - relative to arena center for multi-arena support
	var my_pos_relative = global_position - arena_center
	var my_dist = Vector2(my_pos_relative.x, my_pos_relative.z).length()
	obs.append(clamp((ARENA_RADIUS - my_dist) / ARENA_RADIUS, 0.0, 1.0))  # 3

	# Enemy distance to edge
	var enemy_pos_relative = enemy.global_position - arena_center
	var enemy_dist = Vector2(enemy_pos_relative.x, enemy_pos_relative.z).length()
	obs.append(clamp((ARENA_RADIUS - enemy_dist) / ARENA_RADIUS, 0.0, 1.0))  # 4

	# Own velocity (local, normalized)
	var local_vel = velocity * global_transform.basis
	obs.append(clamp(local_vel.x / MAX_SPEED, -1.0, 1.0))  # 5
	obs.append(clamp(local_vel.z / MAX_SPEED, -1.0, 1.0))  # 6

	# Enemy velocity (in my local space)
	var enemy_local_vel = enemy.velocity * global_transform.basis
	obs.append(clamp(enemy_local_vel.x / MAX_SPEED, -1.0, 1.0))  # 7
	obs.append(clamp(enemy_local_vel.z / MAX_SPEED, -1.0, 1.0))  # 8

	# Charge state observations
	obs.append(1.0 if is_charging else 0.0)  # 9: Am I charging?
	obs.append(clamp(charge_cooldown / CHARGE_COOLDOWN, 0.0, 1.0))  # 10: My cooldown remaining
	obs.append(1.0 if enemy.is_charging else 0.0)  # 11: Is enemy charging?

	# Swing state observations (NEW)
	obs.append(1.0 if is_swinging else 0.0)  # 12: Am I swinging?
	obs.append(clamp(swing_cooldown / SWING_COOLDOWN, 0.0, 1.0))  # 13: My swing cooldown
	obs.append(1.0 if enemy.is_swinging else 0.0)  # 14: Is enemy swinging?

	return obs


func get_reward() -> float:
	var reward = accumulated_reward
	accumulated_reward = 0.0
	return reward


func on_won() -> void:
	accumulated_reward += 1.0
	episode_ended = true


func on_lost() -> void:
	accumulated_reward -= 1.0
	episode_ended = true


func on_draw() -> void:
	accumulated_reward -= 1.5  # Draws are worse than losing - fight or die trying
	episode_ended = true


func reset() -> void:
	global_position = spawn_position
	rotation = Vector3(0, spawn_rotation, 0)
	velocity = Vector3.ZERO
	accumulated_reward = 0.0
	episode_ended = false
	input_move = 0.0
	input_turn = 0.0
	input_charge = false
	is_charging = false
	charge_timer = 0.0
	charge_cooldown = 0.0
	# Reset swing state
	input_swing = 0
	is_swinging = false
	swing_timer = 0.0
	swing_cooldown = 0.0
	swing_direction = 0
