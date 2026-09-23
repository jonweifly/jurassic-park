extends SceneTree
## Real routes/work/deposit for every contract, with encounters disabled to isolate navigation.
const Run = preload("res://scripts/expedition_run.gd")
const Catalog = preload("res://scripts/expedition_catalog.gd")
const Save = preload("res://scripts/save_store.gd")
var world: Node
var checks := 0
var failures := 0
var reports := []

func _initialize() -> void:
	preload("res://scripts/feature_policy.gd").peripheral_enabled = true
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func walk_to(id: String) -> void:
	expect(world.adventure.go_to(id).is_empty(), "Actual travel command accepted: " + id)
	for i in range(2400):
		world._physics_process(0.1)
		if world.hud.expedition_panel.panel.visible: break
	expect(world.hud.expedition_panel.panel.visible and world.session.adventure.sites[id].status == "discovered", "Walk reaches actual visible investigation site: " + id)
	world.hud.expedition_panel.start_choice(0)
	expect(not world.paused and world.order == "expedition", "Inspection choice resumes actual work")
	for i in range(300):
		world._physics_process(0.1)
		if world.session.adventure.sites[id].status in ["completed", "carried"]: break
	expect(world.session.adventure.sites[id].status in ["completed", "carried"], "Work finishes without teleporting or immediate rewards: " + id)

func return_home() -> void:
	expect(world.adventure.return_samples(false).is_empty(), "Contract return has a path to original camp")
	for i in range(2400):
		world._physics_process(0.1)
		if world.hero.route.is_empty():
			for j in range(5): world._physics_process(0.1)
			break
	expect(world.session.adventure.cargo.is_empty(), "Real return settles carried records")

func run() -> void:
	Save.directory = "user://contract_flow_%d" % Time.get_ticks_usec()
	for id in Run.CONTRACTS:
		var content_seed := 0
		for value in range(1, 200):
			if Run.create(value).offers.has(id): content_seed = value; break
		world = load("res://scenes/main.tscn").instantiate()
		root.add_child(world)
		current_scene = world
		world.set_process(false)
		world.set_physics_process(false)
		world.start_session(1500.0, "standard", content_seed)
		world.spawn_clocks.clear()
		world.select_build("tent")
		var center: Vector2i = world.board.cell_at(world.hero.position)
		var placed := false
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var cell := center + Vector2i(dx, dy)
				if placed or not world.placement_error(cell).is_empty(): continue
				world.place_building(cell)
				placed = true
		for i in range(400):
			world._physics_process(0.1)
			if world.session.has_completed("tent"): break
		expect(world.session.has_completed("tent"), "Worker builds free return tent")
		world.build_mode = ""
		expect(world.adventure.contracts.accept(id).is_empty(), "Contract accepted: " + id)
		var expected := Vector2i(0, 10)
		var expected_kits := 0
		# Signal repairs need materials: obtain them through the existing nearby salvage site.
		if id == "signal":
			world.session.adventure.sites.cache.status = "known"
			await walk_to("cache")
			expected.x += 18
		for site in Run.CONTRACTS[id].sites:
			await walk_to(site)
			var reward: Dictionary = Catalog.SITES[site].choices[0]
			expected += Vector2i(reward.reward_wood - reward.wood, reward.reward_gold - reward.gold)
			expected_kits += reward.kits
		if id == "ecology":
			var drawn: Dictionary = world.session.adventure.run.duplicate(true)
			expect(not drawn.claimed and world.session.adventure.cargo.size() == 2, "Two field samples remain unclaimed before return")
			expect(Save.write(world).is_empty(), "Carried contract records persist to disk")
			world.load_game("manual")
			for frame in range(4): await process_frame
			world = current_scene
			world.set_process(false)
			world.set_physics_process(false)
			expect(world.paused and world.session.adventure.run == drawn and world.session.adventure.cargo.size() == 2, "Real scene reload preserves draw, accepted task and carried samples")
			world.paused = false
		await return_home()
		var reward: Dictionary = Run.CONTRACTS[id]
		expected += Vector2i(reward.wood, reward.gold)
		expected_kits += reward.kits
		expect(world.session.adventure.run.claimed, "Actual camp return completes contract: " + id)
		expect(Vector2i(world.session.wood, world.session.gold) == expected and world.session.adventure.kits == expected_kits, "Full route conserves exact site costs and one-time rewards: " + id)
		expect(Save.validate(Save.snapshot(world)).is_empty(), "Full contract route produces valid save")
		reports.append({"contract": id, "seconds": snappedf(world.session.elapsed, 0.1), "wood": world.session.wood, "gold": world.session.gold, "kits": world.session.adventure.kits, "claimed": world.session.adventure.run.claimed})
		world.free()
	DirAccess.make_dir_recursive_absolute("res://captures/variety")
	var file := FileAccess.open("res://captures/variety/contract-routes.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "\t"))
	file.close()
	if DirAccess.dir_exists_absolute(Save.directory):
		for name in DirAccess.open(Save.directory).get_files(): DirAccess.remove_absolute(Save.directory.path_join(name))
		DirAccess.remove_absolute(Save.directory)
	print("CONTRACT FLOW: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
