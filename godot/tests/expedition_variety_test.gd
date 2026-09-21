extends SceneTree
const Catalog = preload("res://scripts/expedition_catalog.gd")
const Run = preload("res://scripts/expedition_run.gd")
const Save = preload("res://scripts/save_store.gd")
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func make_world(seed_value: int = 0) -> Node:
	var w = load("res://scenes/main.tscn").instantiate()
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.start_session(1500.0, "standard", seed_value)
	w.spawn_clocks.clear()
	return w

func seed_for(contract: String) -> int:
	for value in range(1, 200):
		if Run.create(value).offers.has(contract): return value
	return 0

func arrive(id: String) -> void:
	var p: Vector3 = world.board.point(world.session.adventure.sites[id].cell)
	var route: PackedVector3Array = world.board.route(world.hero.position, p, true)
	if not route.is_empty(): world.hero.position = route[-1]
	world.hero.route.clear()
	world.vision.update()
	world.adventure.refresh_visibility()

func tent_at_hero() -> Dictionary:
	var center: Vector2i = world.board.cell_at(world.hero.position)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell := center + Vector2i(dx, dy)
			if not world.board.can_build(cell) or cell == center: continue
			var b: Dictionary = world.session.build("tent", cell)
			b.remaining = 0.0
			world.board.block_building(cell, b.id)
			world.create_building_visual(b)
			return b
	return {}

func finish_fixture(id: String) -> void:
	var site: Dictionary = world.session.adventure.sites[id]
	site.status = "completed"
	site.progress = Catalog.SITES[id].seconds
	site.paid = true
	site.choice = 0
	world.session.adventure.records.append(id)

func test_generation() -> void:
	var events := {}
	var contracts := {}
	var signatures := {}
	var valid := true
	var timing := true
	for seed_value in range(1, 129):
		var run := Run.create(seed_value)
		valid = valid and Run.validate(run, []) and run == Run.create(seed_value)
		signatures[JSON.stringify(run.plan)] = true
		for id in run.offers: contracts[id] = true
		var previous := -100.0
		for item in run.plan:
			events[item.id] = true
			timing = timing and item.at - previous >= 90 and not Catalog.event(item.id).is_empty()
			previous = item.at
	expect(valid, "128 content seeds produce valid reproducible plans")
	expect(events.size() == 12 and contracts.size() == 4, "Seed sweep reaches all twelve events and four contracts")
	expect(signatures.size() > 100 and timing, "Plans vary with nonoverlapping ninety-second offer windows")
	world = make_world()
	var rng_before: int = world.rng.state
	var structures: Dictionary = world.board.structures.duplicate()
	world.session.adventure.run = Run.create(1826)
	var stored: Dictionary = world.session.adventure.run.duplicate(true)
	world.adventure.restore()
	expect(world.rng.state == rng_before and world.board.structures == structures, "Content draw and reconstruction preserve combat RNG and island navigation")
	expect(world.session.adventure.run == stored, "Reconstruction never redraws saved offers or times")
	world.free()

func test_random_events() -> void:
	world = make_world(1)
	var state: Dictionary = world.session.adventure
	var covered := {}
	for seed_value in range(1, 15):
		state.run = Run.create(seed_value)
		state.events_done.clear()
		state.offer = ""
		world.session.wood = 100
		world.session.gold = 100
		world.session.phase = "playing"
		for item in state.run.plan:
			world.session.elapsed = item.at - 0.1
			world.adventure.update_events()
			expect(state.offer.is_empty(), "Event waits for persisted time seed %d/%s" % [seed_value, item.id])
			world.session.elapsed = item.at
			world.adventure.update_events()
			expect(state.offer == item.id and state.offer_until == item.at + 90, "Only drawn event activates with full response window")
			if not covered.has(item.id):
				covered[item.id] = true
				var gold: int = world.session.gold
				var wood: int = world.session.wood
				expect(world.adventure.choose_event(0).is_empty(), "Drawn effect can execute: " + item.id)
				if item.id in ["barter", "materials"]:
					expect(world.session.gold == gold - (8 if item.id == "barter" else 12) and world.session.wood == wood + (16 if item.id == "barter" else 22), "New material trades apply exact cost and yield")
				if item.id in ["survey", "clinic_lead"]:
					var site := "nest" if item.id == "survey" else "clinic"
					expect(state.sites[site].status == "known" and world.session.wood == wood and world.session.gold == gold, "Coordinate clue grants knowledge without resources")
				var stock := Vector2i(world.session.wood, world.session.gold)
				expect(not world.adventure.choose_event(0).is_empty() and stock == Vector2i(world.session.wood, world.session.gold), "Resolved event cannot be claimed twice")
			else:
				world.session.elapsed = state.offer_until
				var stock := Vector2i(world.session.wood, world.session.gold)
				world.adventure.update_events()
				expect(state.events_done.has(item.id) and stock == Vector2i(world.session.wood, world.session.gold), "Ignoring drawn message is free and final")
		expect(state.events_done.size() == 8 and state.offer.is_empty(), "Completed random timeline is exhausted without fallback events")
		if covered.size() == 12: break
	expect(covered.size() == 12, "Every new and retained radio effect exercised")
	state.run = Run.create(42)
	state.events_done.clear()
	state.offer = ""
	world.session.elapsed = 190
	world.paused = true
	world._physics_process(100)
	expect(state.offer.is_empty() and world.session.elapsed == 190, "Pause does not trigger or age random radio")
	world.session.phase = "evacuate"
	world.adventure.update_events()
	expect(state.offer.is_empty(), "No new random offers during evacuation")
	world.free()

func test_contracts() -> void:
	world = make_world(seed_for("evidence"))
	var state: Dictionary = world.session.adventure
	var stock := Vector2i(world.session.wood, world.session.gold)
	var explored: Dictionary = world.vision.explored.duplicate()
	expect(not world.adventure.contracts.accept("missing").is_empty(), "Invalid contract cannot be accepted")
	expect(world.adventure.contracts.accept("evidence").is_empty(), "Offered contract accepts through gameplay API")
	expect(stock == Vector2i(world.session.wood, world.session.gold) and world.vision.explored == explored, "Accept grants no stock or fog reveal")
	expect(state.sites.cache.status == "known" and state.sites.archive.status == "known", "Contract reveals only its investigation coordinates")
	expect(not world.adventure.contracts.accept(state.run.offers[1]).is_empty(), "One contract per run prevents shopping all rewards")
	var tent := tent_at_hero()
	expect(not tent.is_empty(), "Settlement fixture has a real completed tent")
	finish_fixture("cache")
	world.adventure.contracts.settle()
	expect(not state.run.claimed and stock == Vector2i(world.session.wood, world.session.gold), "One of two records cannot claim reward")
	finish_fixture("archive")
	var position: Vector3 = world.hero.position
	world.hero.position += Vector3(10, 0, 0)
	world.adventure.contracts.settle()
	expect(not state.run.claimed, "Completing fieldwork away from tent does not credit reward")
	world.hero.position = position
	tent.remaining = 1.0
	world.adventure.contracts.settle()
	expect(not state.run.claimed, "Unfinished tent cannot settle contract")
	tent.remaining = 0.0
	tent.hp = 0
	world.adventure.contracts.settle()
	expect(not state.run.claimed, "Destroyed tent cannot settle contract")
	tent.hp = 100
	world.hero.health = 0
	world.adventure.contracts.settle()
	expect(not state.run.claimed, "Dead survivor cannot settle contract")
	world.hero.health = 150
	world.session.phase = "lost"
	world.adventure.contracts.settle()
	expect(not state.run.claimed, "Failed session cannot settle contract")
	world.session.phase = "evacuate"
	world.adventure.contracts.settle()
	expect(state.run.claimed and world.session.wood == stock.x + 8 and world.session.gold == stock.y + 8, "Return before boarding grants exact contract bonus once")
	world.adventure.contracts.settle()
	expect(world.session.wood == stock.x + 8 and world.session.gold == stock.y + 8, "Repeated settlement cannot duplicate bonus")
	var snap := Save.snapshot(world)
	expect(Save.validate(snap).is_empty(), "Completed contract state is save-valid")
	world.free()
	world = make_world()
	Save.apply(world, snap)
	world.adventure.contracts.settle()
	expect(world.session.adventure.run.claimed and world.session.gold == stock.y + 8, "Reloaded paid contract remains paid without duplicate bonus")
	world.free()

func test_noise_and_brief() -> void:
	for choice in [0, 1]:
		world = make_world(812)
		arrive("nest")
		var target: Vector3 = world.hero.position
		expect(world.adventure.begin("nest", choice).is_empty(), "Sample choice accepted: " + str(choice))
		world.hero.route.clear()
		world.dino_ai.noises.clear()
		world.adventure.noise_clock = 0
		world.adventure.update(0.1)
		expect(world.dino_ai.noises.size() == 1 and world.dino_ai.noises[0].radius == (8.0 if choice == 0 else 16.0), "Selected sampling effort emits actual gameplay noise")
		var d: Node3D = world.spawn_dinosaur(world.hero.position, "raptor")
		d.position = target + Vector3(12, 0, 0)
		expect(world.dino_ai.audible_noise(d).is_empty() == (choice == 0), "Raptor twelve meters away hears only intensive sampling")
		world.vision.visible_cells.erase(world.board.cell_at(d.position))
		var brief: String = world.adventure.route_brief("nest")
		expect(brief.contains("已见恐龙 0") and brief.contains("不保证安全"), "Travel briefing cannot reveal hidden dinosaur")
		world.vision.visible_cells[world.board.cell_at(d.position)] = true
		expect(world.adventure.route_brief("nest").contains("已见恐龙 1"), "Travel briefing reports truly visible local threat")
		world.dinosaurs.erase(d)
		d.free()
		world.stop_order()
		var progress: float = world.session.adventure.sites.nest.progress
		world.adventure.update(1)
		expect(world.session.adventure.sites.nest.progress == progress, "Cancelled noisy sampling stops progress")
		expect(not world.adventure.begin("nest", 1 - choice).is_empty(), "Committed sample reward cannot be swapped after interruption")
		world.adventure.begin("nest", choice)
		world.hero.route.clear()
		for i in range(130): world.adventure.update(0.1)
		expect(world.session.adventure.sites.nest.status == "carried" and world.session.gold == 10, "Sampling reward remains carried until returning home")
		var tent := tent_at_hero()
		expect(not tent.is_empty(), "Sampling fixture can return to a valid tent")
		world.adventure.deposit_samples()
		expect(world.session.gold == 10 + (24 if choice == 0 else 36), "Sampling pays the selected risk/reward amount on deposit")
		world.free()

func write_legacy(snapshot: Dictionary, slot: String) -> void:
	var bytes := var_to_bytes(snapshot)
	var file := FileAccess.open(Save.directory.path_join(slot + ".jps"), FileAccess.WRITE)
	file.store_buffer("JP05".to_ascii_buffer())
	file.store_buffer(Save.digest(bytes).to_ascii_buffer())
	file.store_buffer(bytes)
	file.close()

func test_save_validation() -> void:
	world = make_world(91826)
	world.session.elapsed = 180
	world.adventure.update_events()
	world.adventure.contracts.accept(world.session.adventure.run.offers[0])
	var snap := Save.snapshot(world)
	expect(snap.version == 3 and Save.validate(snap).is_empty(), "Active random plan and accepted contract use save version three")
	expect(Save.write(world).is_empty(), "Version-three disk save succeeds")
	var disk := Save.read_slot("manual")
	expect(disk.has("data") and disk.data.session.adventure.run == snap.session.adventure.run, "Disk roundtrip preserves exact content draw")
	for key in ["seed", "plan", "offers", "active", "claimed"]:
		var bad := snap.duplicate(true)
		bad.session.adventure.run.erase(key)
		expect(not Save.validate(bad).is_empty(), "Missing contract state field rejected: " + key)
	var bad := snap.duplicate(true)
	bad.session.adventure.run.plan[1].at = NAN
	expect(not Save.validate(bad).is_empty(), "Nonfinite event time rejected")
	bad = snap.duplicate(true)
	bad.session.adventure.run.plan[1].id = "map"
	expect(not Save.validate(bad).is_empty(), "Duplicate or wrong-pool radio event rejected")
	bad = snap.duplicate(true)
	bad.session.adventure.run.claimed = true
	expect(not Save.validate(bad).is_empty(), "Claimed contract without completed records rejected")
	bad = snap.duplicate(true)
	bad.session.adventure.sites.nest.choice = 2
	expect(not Save.validate(bad).is_empty(), "Invalid sampling choice rejected")
	var legacy := snap.duplicate(true)
	legacy.version = 2
	legacy.session.adventure.erase("run")
	legacy.session.adventure.offer = "battery"
	legacy.session.adventure.offer_until = 391.0
	legacy.session.elapsed = 310.0
	legacy.session.adventure.events_done = ["map"]
	write_legacy(legacy, "legacy2")
	var loaded := Save.read_slot("legacy2")
	expect(loaded.has("data") and loaded.data.version == 3 and loaded.data.session.adventure.run.is_empty(), "Real version-two file migrates to legacy timeline")
	expect(loaded.data.session.adventure.offer == "battery" and loaded.data.session.adventure.offer_until == 391 and loaded.data.rng_state == legacy.rng_state, "Migration preserves active choice, deadline, and combat RNG")
	expect(not legacy.session.adventure.has("run") and legacy.version == 2, "Migration leaves original source untouched")
	world.free()
	world = make_world()
	Save.apply(world, loaded.data)
	expect(world.session.adventure.run.is_empty() and world.adventure.choose_event(0).is_empty(), "Legacy pending radio executes after restore")
	world.session.elapsed = 451
	world.adventure.update_events()
	expect(world.session.adventure.offer == "medicine", "Legacy next event follows original schedule")
	world.free()

func run() -> void:
	Save.directory = "user://variety_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Save.directory))
	test_generation()
	test_random_events()
	test_contracts()
	test_noise_and_brief()
	test_save_validation()
	for file in DirAccess.open(Save.directory).get_files(): DirAccess.remove_absolute(Save.directory.path_join(file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.directory))
	print("EXPEDITION VARIETY: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
