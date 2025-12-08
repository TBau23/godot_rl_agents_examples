extends Node3D
## Arena Manager - Coordinates episodes, win/loss detection, and agent reset.
##
## This script manages:
## - Tracking which agents are still alive
## - Dispatching win/loss rewards when an agent falls
## - Episode timeout handling
## - Coordinating resets through the Sync node

const MAX_EPISODE_STEPS: int = 1000
const SPAWN_RADIUS: float = 3.0  # Distance from center to spawn

# References to agents (set in _ready)
var agent1: CharacterBody3D
var agent2: CharacterBody3D

# Episode state
var agent1_alive: bool = true
var agent2_alive: bool = true
var episode_step: int = 0
var episode_active: bool = true  # Prevents double-processing and timer during reset
var reset_in_progress: bool = false  # Prevents multiple reset calls

# Random number generator for spawn randomization
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	# Initialize RNG with random seed
	rng.randomize()

	# Get agent references
	agent1 = $Agent1
	agent2 = $Agent2

	# Connect fall signals
	agent1.fell_off.connect(_on_agent1_fell)
	agent2.fell_off.connect(_on_agent2_fell)

	# Set up enemy references for observations
	agent1.enemy = agent2
	agent2.enemy = agent1

	# Set arena center for multi-arena support (uses parent position if nested)
	var arena_center = global_position
	agent1.arena_center = arena_center
	agent2.arena_center = arena_center

	# Randomize initial spawn positions
	_randomize_spawn_positions()


func _physics_process(_delta: float) -> void:
	# Don't count steps if episode is over (waiting for reset)
	if not episode_active:
		return

	# Count steps for timeout
	episode_step += 1

	# Check for timeout (draw)
	if episode_step >= MAX_EPISODE_STEPS:
		_on_timeout()

	# Debug: Press Space to print observations and rewards
	if Input.is_action_just_pressed("ui_accept"):
		print("--- Debug Info (Step %d) ---" % episode_step)
		print("Agent 1 obs: ", agent1.get_obs())
		print("Agent 1 accumulated_reward: ", agent1.accumulated_reward)
		print("Agent 2 obs: ", agent2.get_obs())
		print("Agent 2 accumulated_reward: ", agent2.accumulated_reward)


func _on_agent1_fell() -> void:
	if not episode_active or not agent1_alive:
		return  # Already processed or episode ended
	agent1_alive = false
	_check_episode_end()


func _on_agent2_fell() -> void:
	if not episode_active or not agent2_alive:
		return  # Already processed or episode ended
	agent2_alive = false
	_check_episode_end()


func _check_episode_end() -> void:
	if not episode_active:
		return

	# Wait one frame to handle simultaneous falls
	if agent1_alive and agent2_alive:
		return  # Neither fell yet

	# Mark episode as ended immediately to prevent timer from triggering
	episode_active = false

	if not agent1_alive and not agent2_alive:
		# Both fell - draw (rare edge case)
		agent1.on_draw()
		agent2.on_draw()
		print("Draw! Both agents fell. A1 reward: %.3f, A2 reward: %.3f" % [agent1.accumulated_reward, agent2.accumulated_reward])
	elif not agent1_alive:
		# Agent 1 fell - Agent 2 wins
		agent1.on_lost()
		agent2.on_won()
		print("Agent 2 wins! A1 reward: %.3f, A2 reward: %.3f" % [agent1.accumulated_reward, agent2.accumulated_reward])
	else:
		# Agent 2 fell - Agent 1 wins
		agent2.on_lost()
		agent1.on_won()
		print("Agent 1 wins! A1 reward: %.3f, A2 reward: %.3f" % [agent1.accumulated_reward, agent2.accumulated_reward])

	# Reset after delay
	_reset_agents_delayed()


func _on_timeout() -> void:
	if not episode_active:
		return

	episode_active = false
	agent1.on_draw()
	agent2.on_draw()
	print("Timeout - Draw! A1 reward: %.3f, A2 reward: %.3f" % [agent1.accumulated_reward, agent2.accumulated_reward])
	_reset_agents_delayed()


func _reset_agents_delayed() -> void:
	# Prevent multiple resets from stacking
	if reset_in_progress:
		return
	reset_in_progress = true

	# Small delay so you can see the fall, then reset
	await get_tree().create_timer(0.5).timeout

	# Randomize spawn positions before reset
	_randomize_spawn_positions()

	# Reset agents (they'll use newly assigned spawn_position/spawn_rotation)
	agent1.reset()
	agent2.reset()

	# Also reset the AI controllers
	var ai1 = agent1.get_node_or_null("AIController3D")
	var ai2 = agent2.get_node_or_null("AIController3D")
	if ai1:
		ai1.done = false
		ai1.needs_reset = false
	if ai2:
		ai2.done = false
		ai2.needs_reset = false

	# Reset arena state
	agent1_alive = true
	agent2_alive = true
	episode_step = 0
	episode_active = true
	reset_in_progress = false

	print("Episode reset - new round!")


func _randomize_spawn_positions() -> void:
	## Randomize spawn positions to prevent self-play bias.
	## Agents spawn on opposite sides of arena, facing each other.
	## Random angle ensures both agents experience all orientations equally.

	var arena_center = global_position

	# Random angle for spawn axis (0 to 2*PI)
	var spawn_angle = rng.randf() * TAU

	# Agent 1 spawns at spawn_angle, Agent 2 at opposite side
	var pos1 = arena_center + Vector3(
		cos(spawn_angle) * SPAWN_RADIUS,
		0.5,
		sin(spawn_angle) * SPAWN_RADIUS
	)
	var pos2 = arena_center + Vector3(
		cos(spawn_angle + PI) * SPAWN_RADIUS,
		0.5,
		sin(spawn_angle + PI) * SPAWN_RADIUS
	)

	# Rotation to face opponent (toward center from each spawn point)
	# Agent 1 faces toward Agent 2 (opposite direction of spawn_angle)
	var rot1 = spawn_angle + PI  # Face inward
	var rot2 = spawn_angle       # Face inward (opposite direction)

	# Update spawn positions (agent.reset() will use these)
	agent1.spawn_position = pos1
	agent1.spawn_rotation = rot1
	agent2.spawn_position = pos2
	agent2.spawn_rotation = rot2
