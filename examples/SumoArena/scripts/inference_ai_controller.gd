extends Node3D
## AI Controller that connects to Python inference server for ONNX model inference.
##
## This is an alternative to the C#-based ONNX inference in godot_rl_agents.
## It connects to a Python server running inference_server.py.

signal connected
signal disconnected

@export var server_host: String = "127.0.0.1"
@export var server_port: int = 11100
@export var auto_reconnect: bool = true
@export var reconnect_delay: float = 2.0

var stream: StreamPeerTCP = null
var is_connected: bool = false
var sumo_agent: CharacterBody3D = null
var pending_response: bool = false
var response_buffer: String = ""

# Fallback action when not connected (do nothing)
var fallback_action = {
	"move": [0.0],
	"turn": [0.0],
	"charge": 0,
	"swing_left": 0,
	"swing_right": 0
}

var last_action = fallback_action.duplicate()


func _ready() -> void:
	# Get reference to parent (the SumoAgent node)
	sumo_agent = get_parent() as CharacterBody3D

	if sumo_agent:
		# Mark this agent as AI controlled (disables keyboard input)
		sumo_agent.is_controlled_by_ai = true
		print("[InferenceAI] Controlling agent: ", sumo_agent.name)

	# Start connection attempt
	_connect_to_server()


func _connect_to_server() -> void:
	if stream != null:
		stream.disconnect_from_host()

	stream = StreamPeerTCP.new()
	stream.set_no_delay(true)

	print("[InferenceAI] Connecting to %s:%d..." % [server_host, server_port])
	var err = stream.connect_to_host(server_host, server_port)
	if err != OK:
		print("[InferenceAI] Failed to start connection: ", err)
		_schedule_reconnect()
		return


func _schedule_reconnect() -> void:
	if auto_reconnect:
		await get_tree().create_timer(reconnect_delay).timeout
		if not is_connected:
			_connect_to_server()


func _process(_delta: float) -> void:
	if stream == null:
		return

	stream.poll()
	var status = stream.get_status()

	match status:
		StreamPeerTCP.STATUS_NONE:
			if is_connected:
				is_connected = false
				print("[InferenceAI] Disconnected")
				disconnected.emit()
				_schedule_reconnect()

		StreamPeerTCP.STATUS_CONNECTING:
			pass  # Still connecting

		StreamPeerTCP.STATUS_CONNECTED:
			if not is_connected:
				is_connected = true
				print("[InferenceAI] Connected to inference server!")
				connected.emit()

			# Read any available data
			_read_responses()

		StreamPeerTCP.STATUS_ERROR:
			if is_connected:
				is_connected = false
				print("[InferenceAI] Connection error")
				disconnected.emit()
			_schedule_reconnect()


func _read_responses() -> void:
	while stream.get_available_bytes() > 0:
		var data = stream.get_utf8_string(stream.get_available_bytes())
		response_buffer += data

		# Process complete messages (newline-delimited JSON)
		while "\n" in response_buffer:
			var newline_pos = response_buffer.find("\n")
			var line = response_buffer.substr(0, newline_pos)
			response_buffer = response_buffer.substr(newline_pos + 1)

			if line.strip_edges().is_empty():
				continue

			var json = JSON.new()
			var parse_result = json.parse(line)
			if parse_result == OK:
				var response = json.data
				_handle_response(response)
			else:
				print("[InferenceAI] JSON parse error: ", json.get_error_message())


func _handle_response(response: Dictionary) -> void:
	if response.get("type") == "actions":
		last_action = response.get("actions", fallback_action)
		pending_response = false
		# Debug: print first few actions received
		if Engine.get_physics_frames() < 10:
			print("[InferenceAI] Got action: move=%.2f turn=%.2f" % [
				last_action.get("move", [0])[0] if last_action.get("move") is Array else last_action.get("move", 0),
				last_action.get("turn", [0])[0] if last_action.get("turn") is Array else last_action.get("turn", 0)
			])
	elif response.get("type") == "pong":
		pass  # Heartbeat response
	elif response.get("type") == "error":
		print("[InferenceAI] Server error: ", response.get("message", "unknown"))


func _physics_process(_delta: float) -> void:
	if sumo_agent == null:
		return

	# Request inference if connected
	if is_connected and not pending_response:
		_request_inference()

	# Apply last known action
	_apply_action(last_action)


func _request_inference() -> void:
	if stream == null or not is_connected:
		return

	var obs = sumo_agent.get_obs()
	var request = {
		"type": "inference",
		"obs": obs
	}

	var json_str = JSON.stringify(request) + "\n"
	stream.put_data(json_str.to_utf8_buffer())
	pending_response = true


func _apply_action(action: Dictionary) -> void:
	# Apply continuous actions
	if action.has("move"):
		var move_val = action["move"]
		if move_val is Array:
			sumo_agent.input_move = clamp(move_val[0], -1.0, 1.0)
		else:
			sumo_agent.input_move = clamp(move_val, -1.0, 1.0)

	if action.has("turn"):
		var turn_val = action["turn"]
		if turn_val is Array:
			sumo_agent.input_turn = clamp(turn_val[0], -1.0, 1.0)
		else:
			sumo_agent.input_turn = clamp(turn_val, -1.0, 1.0)

	# Apply discrete actions
	sumo_agent.input_charge = action.get("charge", 0) == 1

	var swing_left = action.get("swing_left", 0) == 1
	var swing_right = action.get("swing_right", 0) == 1
	if swing_left:
		sumo_agent.input_swing = -1
	elif swing_right:
		sumo_agent.input_swing = 1
	else:
		sumo_agent.input_swing = 0
