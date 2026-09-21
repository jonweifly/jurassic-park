extends SceneTree
## Local native stress sample, not a cross-platform FPS guarantee or a balance test.
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
func _initialize() -> void: call_deferred("run")
func percentile(values: Array, fraction: float) -> float:
	values.sort()
	return values[mini(values.size()-1,int(values.size()*fraction))]
func run() -> void:
	Save.directory = "user://environment_profile_fixture"
	Preferences.file_path = "user://environment_profile_fixture/preferences.cfg"
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	world.weather.preview_kind = 3
	if "--low-quality" in OS.get_cmdline_user_args():
		world.preferences.values.quality = 0
		world.preferences.apply(world,false)
	world.hero.health = 100000 # Fixture remains alive; no economy/win-rate claims.
	world.camera_size = 36
	world.update_camera(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 190926
	for i in range(42):
		var species := "trex" if i < 4 else ("young_trex" if i < 12 else "raptor")
		for attempt in range(100):
			var cell: Vector2i = world.board.cell_at(world.hero.position) + Vector2i(rng.randi_range(-12,12),rng.randi_range(-12,12))
			var p: Vector3 = world.board.point(cell)
			if p.distance_to(world.hero.position) < 5 or not world.board.body_open(p,world.Board.species_radius(species)): continue
			var d: Node3D = world.spawn_dinosaur(p,species)
			if d:
				world.dino_ai.provoke(d,"hero",-1,world.hero.position)
				break
	var samples := []
	var ticks := []
	for frame in range(240):
		var start := Time.get_ticks_usec()
		world.paused = false
		world._physics_process(1.0/60)
		var tick := float(Time.get_ticks_usec()-start)/1000
		world.update_camera(1.0/60)
		world.hud.refresh(0)
		RenderingServer.force_draw(false)
		await process_frame
		if frame >= 60:
			samples.append(float(Time.get_ticks_usec()-start)/1000)
			ticks.append(tick)
	var result := {"renderer":"GL Compatibility", "viewport":str(root.size), "dinosaurs":world.dinosaurs.size(), "samples":samples.size(), "rain_particles":world.weather.drops.amount, "tree_parts":world.scenery.forest.source_parts, "tree_batches":world.scenery.forest.batches.size(), "tick_median_ms":percentile(ticks,0.5), "tick_p95_ms":percentile(ticks,0.95), "tick_max_ms":ticks[-1], "iteration_median_ms":percentile(samples,0.5), "iteration_p95_ms":percentile(samples,0.95), "draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	var folder := "res://captures/weather-refinement" if "--weather-refinement" in OS.get_cmdline_user_args() else "res://captures/environment"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var suffix := "-low" if "--low-quality" in OS.get_cmdline_user_args() else "-storm"
	FileAccess.open(folder.path_join("performance"+suffix+".json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	root.get_texture().get_image().save_png(folder.path_join("stress-42-dinosaurs"+suffix+".png"))
	print("ENVIRONMENT PERFORMANCE ",JSON.stringify(result))
	world.free()
	quit()
