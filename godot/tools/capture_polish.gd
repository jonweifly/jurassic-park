extends SceneTree
## Native OpenGL evidence: day/night, rotated camera, work poses and frame timing.
var world: Node

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	world.hud.refresh(0)
	await process_frame
	await process_frame
	# Force a frame even when macOS occludes the capture window behind another app.
	RenderingServer.force_draw(false)
	var path := "res://captures/polish-%s.png" % name
	var frame := root.get_texture().get_image()
	var result := frame.save_png(path)
	print("SCREENSHOT ",name," ",frame.get_size()," ",result)

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.start_session(3600)
	world.spawn_clocks.clear()
	world.prepare_demo()
	world._physics_process(1.0/30)
	world.update_camera(0)
	world.vision.update()
	world.hud.refresh(0)
	if "--no-shadow" in OS.get_cmdline_user_args():
		world.sun.shadow_enabled = false
		await shot("no-shadow-debug")
		quit()
		return
	await shot("after")
	# Actual rendered frames, after shader warm-up. Frame timing is machine-specific.
	var durations := []
	var previous := Time.get_ticks_usec()
	for i in range(150):
		world._physics_process(1.0/60)
		world.update_camera(1.0/60)
		world.hud.refresh(1.0/60)
		await process_frame
		var now := Time.get_ticks_usec()
		if i > 29: durations.append(float(now-previous)/1000.0)
		previous = now
	durations.sort()
	print("RENDER baseline-camp median_ms=",durations[durations.size()/2]," p95_ms=",durations[int(durations.size()*0.95)]," draw_calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	world.session.elapsed = world.Catalog.DAY_SECONDS * (0.5 + 0.5/TAU)
	world._physics_process(1.0/30)
	world.vision.update()
	await shot("night")
	world.session.elapsed = 0
	world._physics_process(1.0/30)
	world.camera_rig.target_yaw += PI/2
	world.camera_rig.target_pitch = deg_to_rad(42)
	world.camera_size = 24
	world.update_camera(0)
	await physics_frame
	var actual: Vector3 = world.ground_at(world.camera.unproject_position(world.hero.position))
	print("ROTATED_PICK_ERROR ",actual.distance_to(world.hero.position))
	await shot("rotated")
	# A real reachable work target with two phases and a corresponding close-up.
	for cell in world.trees:
		var target: Vector3 = world.board.point(cell)
		var route: PackedVector3Array = world.board.route(world.hero.position,target,true)
		if route.is_empty() or route.size() > 6: continue
		world.hero.position = route[route.size()-1]
		world.hero.route.clear()
		world.worker.assign("wood",target)
		world.hero.route.clear()
		world.camera_rig.center(true)
		var direction: Vector3 = target - world.hero.position
		world.camera_rig.target_yaw = atan2(direction.x,direction.z) + PI * 0.6
		world.camera_rig.target_pitch = deg_to_rad(55)
		world.camera_size = 18
		world.update_camera(0)
		world.vision.update()
		for i in range(25):
			world.hero.advance(1.0/30)
			world.worker.update(1.0/30)
		await shot("chop-windup")
		for i in range(9):
			world.hero.advance(1.0/30)
			world.worker.update(1.0/30)
		await shot("chop-impact")
		break
	# Exercise responsive framing at a wide viewport; no saved project settings change.
	root.size = Vector2i(1600,900)
	await shot("wide")
	world.queue_free()
	await process_frame
	quit()
