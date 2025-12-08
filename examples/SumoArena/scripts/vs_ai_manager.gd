extends Node3D
## VS AI Arena Manager - Manages human vs AI matches without the training Sync node.
##
## This is a simplified version of arena_manager.gd for play mode.
## Agent1 = Human (keyboard), Agent2 = AI (inference server)

const MAX_EPISODE_STEPS: int = 1500  # Longer timeout for human play

# References to agents
var agent1: CharacterBody3D  # Human
var agent2: CharacterBody3D  # AI

# Episode state
var agent1_alive: bool = true
var agent2_alive: bool = true
var episode_step: int = 0
var episode_active: bool = true
var reset_in_progress: bool = false

# Score tracking
var human_wins: int = 0
var ai_wins: int = 0
var draws: int = 0


func _ready() -> void:
	# Get agent references
	agent1 = $Agent1
	agent2 = $Agent2

	# Connect fall signals
	agent1.fell_off.connect(_on_agent1_fell)
	agent2.fell_off.connect(_on_agent2_fell)

	# Set up enemy references for observations
	agent1.enemy = agent2
	agent2.enemy = agent1

	# Set arena center
	var arena_center = global_position
	agent1.arena_center = arena_center
	agent2.arena_center = arena_center

	# Disable the AI controllers that come with the agent scene
	# (we're using InferenceAI instead for Agent2, and keyboard for Agent1)
	var ai1 = agent1.get_node_or_null("AIController3D")
	var ai2 = agent2.get_node_or_null("AIController3D")
	if ai1:
		ai1.set_physics_process(false)
		ai1.set_process(false)
	if ai2:
		ai2.set_physics_process(false)
		ai2.set_process(false)

	print("=== VS AI MODE ===")
	print("You are BLUE (Agent1)")
	print("Controls: W/S = Forward/Back, A/D = Turn, Space = Charge, Q/E = Swing")
	print("==================")


func _physics_process(_delta: float) -> void:
	if not episode_active:
		return

	episode_step += 1

	if episode_step >= MAX_EPISODE_STEPS:
		_on_timeout()


func _on_agent1_fell() -> void:
	if not episode_active or not agent1_alive:
		return
	agent1_alive = false
	_check_episode_end()


func _on_agent2_fell() -> void:
	if not episode_active or not agent2_alive:
		return
	agent2_alive = false
	_check_episode_end()


func _check_episode_end() -> void:
	if not episode_active:
		return

	if agent1_alive and agent2_alive:
		return

	episode_active = false

	if not agent1_alive and not agent2_alive:
		draws += 1
		print("DRAW! Both fell! (Human: %d, AI: %d, Draws: %d)" % [human_wins, ai_wins, draws])
	elif not agent1_alive:
		ai_wins += 1
		print("AI WINS! (Human: %d, AI: %d, Draws: %d)" % [human_wins, ai_wins, draws])
	else:
		human_wins += 1
		print("YOU WIN! (Human: %d, AI: %d, Draws: %d)" % [human_wins, ai_wins, draws])

	_reset_agents_delayed()


func _on_timeout() -> void:
	if not episode_active:
		return

	episode_active = false
	draws += 1
	print("TIMEOUT - DRAW! (Human: %d, AI: %d, Draws: %d)" % [human_wins, ai_wins, draws])
	_reset_agents_delayed()


func _reset_agents_delayed() -> void:
	if reset_in_progress:
		return
	reset_in_progress = true

	await get_tree().create_timer(1.0).timeout

	agent1.reset()
	agent2.reset()

	agent1_alive = true
	agent2_alive = true
	episode_step = 0
	episode_active = true
	reset_in_progress = false

	print("--- New Round ---")
