extends Node3D
## Multi-Arena Spawner - Creates multiple training arenas for parallel training.
##
## This script procedurally spawns N copies of the training arena,
## each offset along the X axis. All arenas share a single Sync node
## at the root level for coordinated RL training.

@export var num_arenas: int = 16
@export var arena_spacing: float = 20.0

var arena_scene: PackedScene = preload("res://scenes/training_arena.tscn")


func _ready() -> void:
	_spawn_arenas()
	_setup_camera()


func _spawn_arenas() -> void:
	for i in num_arenas:
		var arena = arena_scene.instantiate()
		arena.position.x = i * arena_spacing
		arena.name = "Arena%d" % (i + 1)

		# Remove the Sync node from instanced arena BEFORE adding to tree
		# (we have one at root level - can't have multiple Sync nodes)
		var sync_node = arena.get_node_or_null("Sync")
		if sync_node:
			arena.remove_child(sync_node)
			sync_node.free()

		# Remove camera and lighting (we'll have shared ones)
		var camera = arena.get_node_or_null("Camera3D")
		if camera:
			arena.remove_child(camera)
			camera.free()
		var light = arena.get_node_or_null("DirectionalLight3D")
		if light:
			arena.remove_child(light)
			light.free()
		var env = arena.get_node_or_null("WorldEnvironment")
		if env:
			arena.remove_child(env)
			env.free()

		add_child(arena)

	print("Spawned %d arenas with %d total agents" % [num_arenas, num_arenas * 2])


func _setup_camera() -> void:
	# Create overhead camera that can see all arenas
	var camera = Camera3D.new()
	camera.name = "OverheadCamera"

	# Calculate center position based on number of arenas
	var total_span = (num_arenas - 1) * arena_spacing
	var center_x = total_span / 2.0

	# Position camera high enough to see all arenas
	# Using orthographic for cleaner multi-arena view
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = max(total_span + 20, 30)  # Ensure all arenas visible
	camera.transform = Transform3D.IDENTITY
	camera.position = Vector3(center_x, 50, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)  # Look straight down

	add_child(camera)
