extends SceneTree
## Real travel/work/return loop on the island. Encounters disabled to isolate navigation;
## full_session_test separately exercises the unchanged combat/economy win/loss gates.
const Save = preload("res://scripts/save_store.gd")
const Catalog = preload("res://scripts/expedition_catalog.gd")
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	preload("res://scripts/feature_policy.gd").peripheral_enabled = true
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func step() -> void:
	world._physics_process(0.1)

func key(code: Key) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	world._unhandled_input(input)

func run() -> void:
	Save.directory = "user://expedition_flow_%d" % Time.get_ticks_usec()
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500.0, "standard")
	world.spawn_clocks.clear()
	# The free first tent is constructed through the normal placement/worker path.
	world.select_build("tent")
	var center: Vector2i = world.board.cell_at(world.hero.position)
	var placed := false
	for x in range(-2, 3):
		for y in range(-2, 3):
			var cell := center + Vector2i(x, y)
			if placed or not world.placement_error(cell).is_empty(): continue
			world.place_building(cell)
			placed = true
	for i in range(400):
		step()
		if world.session.has_completed("tent"): break
	expect(world.session.has_completed("tent"), "Real worker builds the free return tent")
	world.build_mode = ""
	# This route fixture starts with coordinates; discovery still requires physical sight.
	for id in Catalog.SITE_ORDER: world.session.adventure.sites[id].status = "known"
	for id in Catalog.SITE_ORDER:
		expect(world.adventure.go_to(id).is_empty(), "Travel order accepted: " + id)
		for i in range(1800):
			step()
			if world.hud.expedition_panel.panel.visible: break
		expect(world.hud.expedition_panel.panel.visible and world.paused, "Walking opens inspection only at the site: " + id)
		expect(world.session.adventure.sites[id].status == "discovered", "Line of sight discovers " + id)
		var clock: float = world.session.elapsed
		step()
		expect(world.session.elapsed == clock, "Inspection pauses the simulation: " + id)
		world.hud.expedition_panel.start_choice(0)
		expect(not world.paused and world.order == "expedition", "Choosing action resumes work: " + id)
		if id == "cache":
			for i in range(30): step()
			var progress: float = world.session.adventure.sites.cache.progress
			expect(progress > 0 and Save.write(world).is_empty(), "In-progress job writes a real version-two disk save")
			world.load_game("manual")
			for i in range(4): await process_frame
			world = current_scene
			world.set_process(false)
			world.set_physics_process(false)
			expect(world.paused and world.order == "expedition" and world.session.adventure.sites.cache.progress == progress, "Actual scene reload restores paid choice, route and progress")
			world.toggle_pause()
		for i in range(500):
			step()
			if world.session.adventure.sites[id].status in ["carried", "completed"]: break
		expect(world.session.adventure.sites[id].status in ["carried", "completed"], "Actual simulation completes work: " + id)
		if not world.session.adventure.cargo.is_empty():
			expect(world.adventure.return_samples().is_empty(), "Cargo has a return path: " + id)
			# Force a replan to cover board edits during a return trip.
			world.board.revision += 1
			for i in range(1800):
				step()
				if world.session.adventure.cargo.is_empty(): break
			expect(world.session.adventure.cargo.is_empty(), "Walk back and deposit without teleport: " + id)
	expect(world.session.adventure.records.size() == 6 and world.session.adventure.story_rewarded, "All six sites and the narrative reward complete in the real simulation")
	expect(world.session.wood == 16 and world.session.gold == 55, "Whole exploration route uses earned stock and exact one-time repair costs")
	# Disk-level v1 migration with real header and checksum, then normal load lifecycle.
	var legacy := Save.snapshot(world)
	legacy.version = 1
	legacy.session.erase("adventure")
	var bytes := var_to_bytes(legacy)
	var file := FileAccess.open(Save.directory.path_join("legacy.jps"), FileAccess.WRITE)
	file.store_buffer("JP05".to_ascii_buffer())
	file.store_buffer(Save.digest(bytes).to_ascii_buffer())
	file.store_buffer(bytes)
	file.close()
	expect(Save.read_slot("legacy").has("data"), "Real v1 disk file passes migration and validation")
	world.load_game("legacy")
	for i in range(4): await process_frame
	world = current_scene
	world.set_process(false)
	world.set_physics_process(false)
	expect(world.paused and world.session.gold == 55 and world.session.adventure.sites.size() == 6, "V1 scene load preserves economy and initializes optional exploration")
	key(KEY_L)
	expect(world.hud.expedition_panel.panel.visible, "Journal accessible from pause")
	key(KEY_ESCAPE)
	expect(world.paused and not world.hud.expedition_panel.panel.visible, "Closing journal preserves previous pause")
	world.session.phase = "won"
	key(KEY_L)
	expect(world.hud.expedition_panel.panel.visible, "Records accessible after a finished run")
	key(KEY_L)
	world.session.phase = "evacuate"
	world.session.finale_wave = 3
	world.session.adventure.power_until = world.session.game_time() + 0.3
	world.paused = false
	expect(world.session.supply() == 2, "Temporary battery still active at evacuation start")
	for i in range(4): step()
	expect(world.session.supply() == 0, "Temporary battery expires during evacuation")
	for file_name in DirAccess.open(Save.directory).get_files(): DirAccess.remove_absolute(Save.directory.path_join(file_name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.directory))
	print("EXPEDITION FLOW: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
