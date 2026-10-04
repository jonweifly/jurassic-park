extends SceneTree
const Save = preload("res://scripts/save_store.gd")
const Session = preload("res://scripts/session.gd")
var checks := 0
var failures := 0
var world: Node
var temporary_directory := ""

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make_world() -> Node:
	var w = load("res://scenes/main.tscn").instantiate()
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.start_session(1500.0, "standard")
	w.spawn_clocks.clear()
	return w

func build_fixture(s: RefCounted, kind: String, cell: Vector2i) -> Dictionary:
	var b: Dictionary = s.build(kind, cell)
	if not b.is_empty(): b.remaining = 0.0
	return b

func test_research() -> void:
	var s = Session.new()
	expect(not s.begin_research("pack_1").is_empty(), "Research requires an actual laboratory")
	s.wood = 500
	s.gold = 500
	build_fixture(s, "tent", Vector2i(1, 1))
	var generator := build_fixture(s, "generator", Vector2i(2, 1))
	var lab := build_fixture(s, "lab", Vector2i(3, 1))
	expect(s.research(lab.id).is_empty(), "Existing lab upgrade remains usable")
	s.tick(10)
	expect(s.has_completed("laboratory"), "Upgrade finishes into a functioning laboratory")
	var stock := Vector2i(s.wood, s.gold)
	expect(not s.begin_research("pack_2").is_empty() and stock == Vector2i(s.wood, s.gold), "Missing prerequisite never charges resources")
	expect(s.begin_research("pack_1").is_empty(), "First carrying research can start")
	expect(s.wood == stock.x - 8 and s.gold == stock.y - 5, "Research charges listed price once")
	expect(not s.begin_research("tools").is_empty(), "Only one research job at a time")
	s.tick(10)
	generator.hp = 0.0
	s.tick(10)
	expect(s.research_job.remaining == 10, "Power loss suspends paid research without discarding progress")
	generator.hp = 100.0
	lab.hp = 0.0
	s.tick(10)
	expect(s.research_job.remaining == 10, "Destroyed laboratory suspends research")
	lab.hp = 100.0
	s.tick(10)
	expect(s.harvest_level == 1 and s.technologies.has("pack_1"), "Research resumes and unlocks capacity two")
	expect(not s.begin_research("pack_1").is_empty(), "Completed research cannot be bought twice")
	for tech in ["pack_2", "pack_3", "tools", "defense", "medicine"]:
		expect(s.begin_research(tech).is_empty(), "Technology is reachable: " + tech)
		s.tick(60)
	expect(s.harvest_level == 3 and is_equal_approx(s.work_multiplier(), 1.35) and is_equal_approx(s.defense_multiplier(), 1.3), "Completed progression applies real gameplay multipliers")
	s.duration = 1500
	s.elapsed = 1350
	expect(s.begin_research("radio").is_empty(), "Radio research available after investment")
	s.tick(60)
	expect(s.duration == 1500, "Late radio cannot postpone an already earlier rescue")
	s.phase = "evacuate"
	expect(not s.begin_research("radio").is_empty(), "Evacuation cannot start research")

func test_save_roundtrip() -> void:
	world = make_world()
	world.prepare_demo()
	world.session.mode = "standard"
	world.session.wood = 90
	world.session.gold = 70
	world.session.elapsed = 410.0
	world.session.technologies = {"pack_1": true, "defense": true}
	world.session.harvest_level = 1
	world.session.research_job = {"tech": "tools", "remaining": 12.5}
	var tent: Dictionary
	var gate: Dictionary
	for b in world.session.buildings:
		if b.kind == "tent": tent = b
		if b.kind == "gate": gate = b
		if b.kind == "tower": b.remaining = 3.5
	gate.open = true
	gate.gate_timer = 2.5
	world.board.remove_building(gate.cell)
	world.worker.cargo_kind = "wood"
	world.worker.cargo = 2
	world.worker.resource_kind = "wood"
	world.worker.resource_target = world.board.point(world.trees.keys()[10])
	world.worker.begin_return()
	world.hero.position = world.board.point(tent.cell) + Vector3(0, 0, 2)
	world.hero.route.clear()
	world.hero.health = 82.0
	var removed: Vector2i = world.trees.keys()[0]
	world.clear_tree(removed)
	var reduced: Vector2i = world.trees.keys()[1]
	world.trees[reduced].wood = 7
	world.dino_ai.emit_noise(world.hero.position, 7.0, "hero")
	var d: Node3D = world.spawn_dinosaur(world.hero.position, "raptor")
	world.hero.target_id = d.get_instance_id()
	d.set_meta("ai_strike", {"remaining": 0.12, "kind": "building", "id": tent.id})
	var corpse: Node3D = world.spawn_dinosaur(world.hero.position, "small_raptor")
	corpse.health = 0
	corpse.dying = true
	corpse.death_clock = 0.4
	world.session.kills = 1
	world.hero.visual.model.rotation.y = 1.25
	world.vision.explored[Vector2i(80, 80)] = true
	world.camera_rig.target_yaw = 2.1
	var snap := Save.snapshot(world)
	expect(Save.validate(snap).is_empty(), "Complex live snapshot is structurally valid: " + Save.validate(snap))
	expect(Save.write(world).is_empty(), "Manual snapshot writes successfully")
	var read := Save.read_slot("manual")
	expect(read.has("data"), "Written save passes checksum and schema")
	if not read.has("data"):
		world.free()
		return
	var expected_random: int = world.rng.randi()
	world.free()
	world = make_world()
	Save.apply(world, read.data)
	expect(world.hero.visual.model.rotation.y == 1.25, "Character facing persists across save/load")
	var site: Dictionary = {}
	for b in world.session.buildings:
		if b.kind == "tower": site = b
	expect(site.remaining == 3.5 and world.board.structures.has(site.cell), "Unfinished construction keeps time, power reservation and collision")
	var loaded_corpse: Node3D = null
	var loaded_attacker: Node3D = null
	for animal in world.dinosaurs:
		if animal.dying: loaded_corpse = animal
		if animal.has_meta("ai_strike"): loaded_attacker = animal
	expect(loaded_corpse != null and loaded_attacker != null, "Saved attack and corpse both restore")
	if loaded_corpse: world.dino_ai.update_death(loaded_corpse, 0.1)
	expect(world.session.kills == 1 and world.session.gold == 70, "Saved corpse cannot grant a second kill or gold reward")
	expect(world.paused and world.started, "Continue loads paused with a live session")
	expect(world.session.wood == 90 and world.session.gold == 70 and world.session.elapsed == 410, "Stock and game clock are restored")
	expect(world.worker.cargo == 2 and world.order == "return", "Mid-delivery command and cargo persist")
	expect(world.session.research_job.remaining == 12.5 and world.session.harvest_level == 1, "Technology and research timer persist")
	expect(not world.trees.has(removed) and world.trees[reduced].wood == 7, "Depleted and partially harvested trees persist")
	expect(world.board.is_open(gate.cell) and world.session.building(gate.id).gate_timer == 2.5, "Open gate and in-flight gate transition persist")
	expect(world.dinosaurs.size() == snap.animals.size() and loaded_attacker != null and loaded_attacker.get_meta("ai_strike").remaining == 0.12, "Dinosaurs and wind-up attacks persist")
	expect(loaded_attacker != null and world.hero.target_id == loaded_attacker.get_instance_id(), "Attack target remaps stable save ID to new scene instance")
	expect(world.rng.randi() == expected_random, "Loading does not advance the saved gameplay RNG")
	expect(world.vision.explored.has(Vector2i(80, 80)) and world.camera_rig.target_yaw == 2.1, "Exploration and camera survive loading")
	expect(world.dino_ai.noises == snap.noises, "Unexpired AI hearing events persist independently of audio")
	var before: float = world.session.elapsed
	world._physics_process(1)
	expect(world.session.elapsed == before, "Loaded pause prevents hidden damage/timer advancement")
	world.worker.resource_kind = ""
	world.worker.update(0.033)
	expect(world.session.wood == 92 and world.worker.cargo == 0, "Saved delivery credits stock exactly once")
	world.worker.update(1)
	expect(world.session.wood == 92, "Completed delivery cannot be credited twice")
	world.session.phase = "evacuate"
	world.session.evacuation_elapsed = 142.0
	world.session.finale_wave = 3
	world.session.boarding_progress = 4.5
	expect(Save.write(world, true).is_empty(), "Evacuation can be saved")
	var evacuation := Save.read_slot("auto0")
	expect(evacuation.has("data") and evacuation.data.session.evacuation_elapsed == 142 and evacuation.data.session.finale_wave == 3 and evacuation.data.session.boarding_progress == 4.5, "Evacuation timer and finale waves persist")
	world.session.phase = "playing"
	world.paused = false
	world.hero.health = 80
	world.session.gold = 10
	world.stop_order()
	world.heal()
	world.hero.route.clear()
	world.worker.update(1.0)
	expect(world.hero.health == 90 and world.session.gold == 9, "Basic healing charges one gold for ten health at tent")
	world.session.technologies.medicine = true
	world.worker.update(1.0)
	expect(world.hero.health == 115 and world.session.gold == 8, "Medical research improves healing rather than granting free regeneration")
	world.stop_order()
	world.worker.update(2.0)
	expect(world.hero.health == 115 and world.session.gold == 8, "Cancelled healing stops charges and recovery")
	world.session.gold = 0
	world.heal()
	expect(world.order == "idle", "Unaffordable healing does not start travel")
	world.session.gold = 8
	expect(Save.write(world, true).is_empty() and Save.write(world, true).is_empty(), "Three automatic save slots are independently writable")
	expect(FileAccess.file_exists(Save.directory.path_join("auto1.jps")) and FileAccess.file_exists(Save.directory.path_join("auto2.jps")), "Automatic rotation retains three snapshots")
	expect(Save.write(world).is_empty() and FileAccess.file_exists(Save.directory.path_join("manual_backup.jps")), "Manual overwrite retains a prior valid backup")
	var corrupt := FileAccess.open(Save.directory.path_join("manual.jps"), FileAccess.WRITE)
	corrupt.store_string("broken save")
	corrupt.close()
	expect(Save.read_slot("manual").has("error"), "Truncated file rejected safely")
	var fallback := Save.latest()
	expect(fallback.has("data") and fallback.recovered, "Continue falls back to a valid snapshot when the manual file is damaged")
	var bad := snap.duplicate(true)
	bad.version = 999
	expect(not Save.validate(bad).is_empty(), "Unsupported schema rejected")
	bad = snap.duplicate(true)
	bad.session.buildings[0].erase("cell")
	expect(not Save.validate(bad).is_empty(), "Malformed nested building rejected before world mutation")
	world.free()

func test_bite() -> void:
	world = make_world()
	var p: Vector3 = world.hero.position
	var d: Node3D = world.spawn_dinosaur(p, "raptor")
	world.dino_ai.provoke(d, "hero", -1, p)
	world.dino_ai.attack_if_close(d)
	expect(world.hero.health == 150, "Bite wind-up does not deal immediate damage")
	world.dino_ai.resolve_strike(d, 0.1)
	expect(world.hero.health == 150, "Bite damage waits until contact")
	world.hero.position += Vector3(8, 0, 0)
	world.dino_ai.resolve_strike(d, 0.1)
	expect(world.hero.health == 150, "Leaving reach during wind-up avoids damage")
	world.hero.position = p
	d.attack_cooldown = 0
	world.dino_ai.attack_if_close(d)
	world.dino_ai.resolve_strike(d, 0.2)
	expect(world.hero.health == 138, "A connected bite deals its original damage once")
	world.dino_ai.resolve_strike(d, 0.2)
	expect(world.hero.health == 138, "A committed strike cannot hit twice")
	world.free()

func test_pacing() -> void:
	world = make_world()
	world.director.configure()
	expect(world.spawn_clocks[0].next == 100, "Standard opening has an authored preparation window")
	world.session.elapsed = 500
	expect(world.director.group()[0] == "young_trex", "Middle phase changes camp threat to juvenile tyrannosaur")
	world.session.elapsed = 900
	expect(world.director.group()[0] == "trex", "Late phase uses an adult threat, without sensing across map")
	world.session.elapsed = 1390
	world.spawn_clocks.clear()
	world.director.update()
	expect(world.session.rescue_warned, "Rescue approach is announced before evacuation")
	for seed_value in range(65065, 65075):
		world.rng.seed = seed_value
		world.session.phase = "evacuate"
		world.session.evacuation_elapsed = 0
		world.session.finale_wave = 0
		var before: int = world.dinosaurs.size()
		world.director.update()
		expect(world.session.finale_wave == 1 and world.dinosaurs.size() > before, "Evacuation creates a real local encounter for seed " + str(seed_value))
		world.director.update()
		expect(world.session.finale_wave == 1, "No duplicate finale wave in same time window")
		for d in world.dinosaurs: d.free()
		world.dinosaurs.clear()
	world.session.evacuation_elapsed = 120
	world.session.finale_wave = 3
	world.director.update()
	expect(world.dinosaurs.is_empty(), "Completed finale waves do not replay")
	world.hero.position = world.extraction
	world.paused = false
	world._physics_process(6.0)
	expect(world.session.phase == "evacuate" and is_equal_approx(world.session.boarding_progress, 6.0), "Standard mode requires holding the landing zone before victory")
	world.hero.position += Vector3(8, 0, 0)
	world._physics_process(2.0)
	expect(is_equal_approx(world.session.boarding_progress, 5.0), "Leaving the landing zone slowly loses boarding progress")
	world.hero.health = 0
	world.hero.position = world.extraction
	world.paused = false
	world._physics_process(0.033)
	expect(world.session.phase == "lost", "A dead survivor cannot win by standing on extraction")
	world.free()

func run() -> void:
	temporary_directory = "user://test_core_%d" % Time.get_ticks_usec()
	Save.directory = temporary_directory
	test_research()
	test_save_roundtrip()
	test_bite()
	test_pacing()
	var folder := DirAccess.open(temporary_directory)
	if folder:
		for file in folder.get_files(): folder.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_directory))
	print("CORE EXPERIENCE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
