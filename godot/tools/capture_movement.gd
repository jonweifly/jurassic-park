extends SceneTree
var world: Node
var folder := "res://captures/movement"

func _initialize() -> void:
	call_deferred("run")

func shot(title: String, at: Vector3) -> void:
	# Let CanvasItem redraw after any window-creation focus notifications.
	for frame in range(3):
		world.paused = false
		world.hud.refresh(0)
		world.pointer_feedback.update_hover(world.camera.unproject_position(at), at)
		world.pointer_feedback.active = not world.hud.covers(world.pointer_feedback.pointer)
		world.pointer_feedback.queue_redraw()
		await process_frame
	RenderingServer.force_draw(false)
	var result := root.get_texture().get_image().save_png(folder.path_join(title + ".png"))
	print("MOVEMENT SCREENSHOT ", title, " result=", result)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500.0, "standard")
	world.spawn_clocks.clear()
	world.camera_size = 24
	world.camera_rig.target_pitch = deg_to_rad(38)
	world.update_camera(0)
	world.vision.update()
	var target := Vector3.ZERO
	for x in range(5, 12):
		var cell: Vector2i = world.board.cell_at(world.hero.position) + Vector2i(x, 0)
		if world.board.is_open(cell) and not world.board.route(world.hero.position, world.board.point(cell)).is_empty():
			target = world.board.point(cell)
			break
	world.command(target)
	world.pointer_feedback.pulse_left = 0.6
	await shot("move-start", target)
	await shot("move-separated", world.hero.position)
	for i in range(24):
		world.paused = false
		world._physics_process(0.1)
		world.update_camera(0.1)
	world.pointer_feedback.pulse_left = 0
	await shot("move-follow", target)
	world.stop_order()
	var tree := Vector3.ZERO
	for cell in world.trees:
		var p: Vector3 = world.board.point(cell)
		var screen: Vector2 = world.camera.unproject_position(p)
		if p.distance_to(world.hero.position) < 10 and screen.x > 360 and screen.x < 1000 and screen.y > 220 and screen.y < 630 and not world.board.route(world.hero.position, p, true).is_empty():
			tree = p
			world.vision.explored[cell] = true
			break
	world.command(tree)
	world.pointer_feedback.pulse_left = 0.55
	await shot("axe-target", tree)
	world.stop_order()
	# A safe close target fixture for the combat cursor, without running combat.
	var d: Node3D = world.spawn_dinosaur(world.hero.position + Vector3(0, 0, 2), "raptor")
	if not d: d = world.spawn_dinosaur(world.hero.position, "raptor")
	d.visible = true
	world.command(d.position)
	await shot("attack-target", d.position)
	world.stop_order()
	# Isolate a nearby cell to verify that a silent move cursor still reports errors.
	var blocked_cell: Vector2i = world.board.cell_at(world.hero.position) + Vector2i(3, 0)
	for x in range(-1, 2):
		for y in range(-1, 2):
			if x != 0 or y != 0: world.board.block_terrain(blocked_cell + Vector2i(x, y))
	var blocked_point: Vector3 = world.board.point(blocked_cell)
	world.pointer_feedback.confirm({"kind": "blocked", "position": blocked_point}, false)
	await shot("blocked-target", blocked_point)
	world.free()
	quit()
