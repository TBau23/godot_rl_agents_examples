extends "res://addons/godot_rl_agents/controller/ai_controller_3d.gd"
## Custom AIController3D for the Sumo agent.
##
## This controller bridges the godot_rl_agents plugin with our sumo_agent.gd
## by implementing the required interface methods.

# Reference to the sumo agent script
var sumo_agent: CharacterBody3D


func _ready() -> void:
	super._ready()
	# Get reference to parent (the SumoAgent node)
	sumo_agent = get_parent() as CharacterBody3D
	if sumo_agent:
		init(sumo_agent)
		# Don't force AI control - let heuristic determine control mode
		# heuristic will be set by Sync node (defaults to "human")


func get_obs() -> Dictionary:
	if sumo_agent == null:
		return {"obs": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]}
	return {"obs": sumo_agent.get_obs()}


func get_reward() -> float:
	if sumo_agent == null:
		return 0.0
	return sumo_agent.get_reward()


func get_action_space() -> Dictionary:
	return {
		"move": {"size": 1, "action_type": "continuous"},
		"turn": {"size": 1, "action_type": "continuous"},
		"charge": {"size": 2, "action_type": "discrete"},      # 0=no, 1=charge
		"swing_left": {"size": 2, "action_type": "discrete"},  # 0=no, 1=swing left
		"swing_right": {"size": 2, "action_type": "discrete"}, # 0=no, 1=swing right
	}


func set_action(action) -> void:
	if sumo_agent == null:
		return
	# action is a Dictionary with keys matching get_action_space()
	sumo_agent.input_move = clamp(action["move"][0], -1.0, 1.0)
	sumo_agent.input_turn = clamp(action["turn"][0], -1.0, 1.0)
	sumo_agent.input_charge = action["charge"] == 1
	# Swing: two binary actions -> -1 (left), 0 (none), 1 (right)
	# If both pressed, left takes priority
	if action["swing_left"] == 1:
		sumo_agent.input_swing = -1
	elif action["swing_right"] == 1:
		sumo_agent.input_swing = 1
	else:
		sumo_agent.input_swing = 0


func get_action() -> Array:
	# Used for recording expert demos - return current human input
	if sumo_agent == null:
		return [0.0, 0.0, 0, 0, 0]
	var swing_left = 1 if sumo_agent.input_swing == -1 else 0
	var swing_right = 1 if sumo_agent.input_swing == 1 else 0
	return [sumo_agent.input_move, sumo_agent.input_turn, 1 if sumo_agent.input_charge else 0, swing_left, swing_right]


func reset() -> void:
	super.reset()
	if sumo_agent:
		sumo_agent.reset()
	done = false


func get_done() -> bool:
	if sumo_agent == null:
		return false
	return sumo_agent.episode_ended


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Check if Sync has requested a reset
	if needs_reset and sumo_agent:
		sumo_agent.reset()
		needs_reset = false
		n_steps = 0
		done = false
