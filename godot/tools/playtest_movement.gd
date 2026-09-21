extends SceneTree
## Isolated native UI fixture: normal input/rendering, no player saves or enemy spawns.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	load("res://scripts/save_store.gd").directory = "user://movement_ui_fixture"
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.start_session(1500.0, "standard")
	world.spawn_clocks.clear()
	world.camera_size = 24
	world.camera_rig.target_pitch = deg_to_rad(38)
	world.update_camera(0)
