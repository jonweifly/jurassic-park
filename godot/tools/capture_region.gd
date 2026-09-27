extends SceneTree
## Render a local terrain inspection without modifying the saved scene or start.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var region := "mountain"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--region="): region = arg.trim_prefix("--region=")
	var positions := {"mountain": Vector3(55, 0, -55), "ice": Vector3(-55, 0, -55), "swamp": Vector3(55, 0, 55), "rainforest": Vector3(-55, 0, 55), "water": Vector3(89, 0, 73)}
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.started = true
	world.paused = false
	var center: Vector2i = world.board.cell_at(positions.get(region, positions.mountain))
	var found := false
	for radius in range(0, 14):
		if found: break
		for x in range(-radius, radius + 1):
			if found: break
			for y in range(-radius, radius + 1):
				var cell := center + Vector2i(x, y)
				if world.board.can_build(cell) and not world.board.route(world.hero.position, world.board.point(cell)).is_empty():
					world.hero.position = world.board.point(cell)
					found = true
					break
	world.camera_focus = world.hero.position
	world.camera_size = 55
	world.camera.size = 55
	world.vision.update()
	if "--unshrouded" in OS.get_cmdline_user_args():
		world.vision.countdown = INF
		world.vision.image.fill(Color.WHITE)
		world.vision.texture.update(world.vision.image)
		world.hud.hide()
	world.update_camera(0)
	world._physics_process(1.0/30)
	if "--unshrouded" not in OS.get_cmdline_user_args(): world.hud.refresh(0)
	world.capture_path = "res://captures/region-%s.png" % region
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	world.capture()
