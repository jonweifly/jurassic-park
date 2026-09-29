extends SceneTree
## Read-only replay of a copied save. Performance output only; never saves the game.
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
var world: Node
var slot := "auto0"
var output := "res://captures/performance/saved-crowd.json"
var frames := 180
var instrument := false
var reference_board := false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--instrument": instrument = true
		if arg == "--reference-board": reference_board = true
		if arg.begins_with("--save-dir="): Save.directory = arg.trim_prefix("--save-dir=")
		if arg.begins_with("--slot="): slot = arg.trim_prefix("--slot=")
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
	if frames < 1 or (instrument and reference_board):
		push_error("Use a positive frame count and only one of --instrument / --reference-board")
		quit(1)
		return
	if reference_board and not ResourceLoader.exists("res://captures/performance/reference_board.gd"):
		push_error("Copy the baseline board to res://captures/performance/reference_board.gd before using --reference-board")
		quit(1)
		return
	var saved := Save.read_slot(slot)
	if saved.has("error"): push_error(saved.error); quit(1); return
	Preferences.file_path = "user://crowd_profile_fixture/preferences.cfg"
	world = load("res://scenes/main.tscn").instantiate()
	if instrument: world.set_script(load("res://tools/profile_world.gd"))
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	if instrument or reference_board:
		var measured = load("res://captures/performance/reference_board.gd" if reference_board else "res://tools/profile_board.gd").new()
		for key in ["grid", "layout", "terrain", "structures", "revision", "clearance_grids"]: measured.set(key, world.board.get(key))
		world.board = measured
		world.hero.navigation = measured
	Save.apply(world, saved.data)
	world.paused = false
	world.preferences.values.fullscreen = false
	world.preferences.apply(world, false)
	var native := DisplayServer.get_name() != "headless"
	if native:
		DisplayServer.window_set_size(Vector2i(1280,800))
		for warmup in range(30): await RenderingServer.frame_post_draw
	if instrument:
		world.profile.clear()
		world.board.profile = {"route_us":0,"route_calls":0,"grid_us":0,"grid_calls":0,"slowest":[]}
	var samples := {"simulation":[], "hud_camera":[], "frame":[]}
	for frame in range(frames):
		var start := Time.get_ticks_usec()
		world._physics_process(1.0/30)
		var sim_us := Time.get_ticks_usec() - start
		var t := Time.get_ticks_usec()
		world._process(1.0/30)
		var hud_us := Time.get_ticks_usec() - t
		if native:
			await RenderingServer.frame_post_draw
		samples.simulation.append(sim_us/1000.0)
		samples.hud_camera.append(hud_us/1000.0)
		samples.frame.append((Time.get_ticks_usec()-start)/1000.0)
	var report := {"slot":slot,"native":native,"reference_board":reference_board,"frames":frames,"dinosaurs":saved.data.animals.size(),"buildings":saved.data.session.buildings.size()}
	for key in samples:
		var values: Array = samples[key]
		values.sort()
		var sum := 0.0
		for v in values: sum += v
		report[key] = {"mean_ms":sum/values.size(),"p95_ms":values[int(values.size()*.95)],"max_ms":values.back()}
	if instrument:
		report["profile"] = world.profile
		report["navigation"] = world.board.profile
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if not file:
		push_error("Cannot write performance report: " + output)
		world.free()
		quit(1)
		return
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("SAVED CROWD ",JSON.stringify(report))
	var failed: bool = report.simulation.p95_ms > 33.3
	world.free()
	print("SAVED BUDGET: ",1 if failed else 0," failures")
	quit(1 if failed else 0)
