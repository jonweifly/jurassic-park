extends SceneTree
var world: Node
var folder := "res://captures/art-direction"
var tag := "after"

func _initialize() -> void: call_deferred("run")

func shot(name: String) -> void:
	world.update_lighting()
	world.update_buildings(0)
	world.update_camera(0)
	world.vision.update()
	world.hud.refresh(0)
	for i in range(8): await process_frame
	RenderingServer.force_draw(false)
	print("ART CAPTURE ", tag, " ", name, " ", root.get_texture().get_image().save_png(folder.path_join(tag + "-" + name + ".png")))

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	load("res://scripts/save_store.gd").directory = "user://art_direction_fixture"
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500, "standard")
	world.spawn_clocks.clear()
	world.prepare_demo()
	world.camera_size = 25
	world.camera_rig.target_pitch = deg_to_rad(46)
	world.weather.preview_kind = 0
	world.update_buildings(0)
	await shot("camp")
	var timings := []
	for i in range(90):
		var start := Time.get_ticks_usec()
		world.update_camera(1.0 / 60)
		RenderingServer.force_draw(false)
		await process_frame
		if i > 29: timings.append((Time.get_ticks_usec() - start) / 1000.0)
	timings.sort()
	var perf := {"viewport": str(root.size), "median_ms": timings[timings.size()/2], "p95_ms": timings[int(timings.size() * .95)], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	FileAccess.open(folder.path_join(tag + "-performance.json"), FileAccess.WRITE).store_string(JSON.stringify(perf, "\t"))
	print("ART PERFORMANCE ", JSON.stringify(perf))
	world.hud.hide()
	world.camera_size = 12
	world.camera_rig.target_pitch = deg_to_rad(38)
	await shot("close")
	world.session.elapsed = world.Catalog.DAY_SECONDS * (0.5 + 0.5/TAU)
	await shot("night")
	world.session.elapsed = 300
	world.weather.preview_kind = 2
	await shot("rain")
	world.preferences.values.quality = 0
	world.preferences.apply(world, false)
	await shot("low")
	world.free()
	quit()
