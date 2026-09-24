extends SceneTree
const Hard = preload("res://scripts/hard_difficulty.gd")
const Session = preload("res://scripts/session.gd")
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func mature_camp(s: RefCounted) -> void:
	for i in range(20):
		s.buildings.append({"id": i + 1, "kind": "tower", "hp": 200.0, "remaining": 0.0, "refit": "rapid"})
	for i in range(5): s.buildings.append({"id": 21 + i, "kind": "generator", "hp": 100.0, "remaining": 0.0})
	for tech in s.Catalog.TECH: s.technologies[tech] = true

func test_curve() -> void:
	var s = Session.new()
	s.mode = "hard"
	mature_camp(s)
	expect(Hard.target_pressure(s) == 0.0, "Even an advanced starting camp retains opening grace")
	var previous := -1.0
	var bounded := true
	var smooth := true
	for time in range(0, 3601):
		s.elapsed = float(time)
		var p := Hard.target_pressure(s)
		var profile := Hard.profile(p)
		bounded = bounded and p >= 0 and p <= 1 and profile.count >= 2 and profile.count <= Hard.MAX_WAVE_SIZE and profile.interval >= Hard.MIN_INTERVAL and profile.interval <= 100 and profile.health <= Hard.MAX_HEALTH_MULTIPLIER and profile.damage <= Hard.MAX_DAMAGE_MULTIPLIER
		smooth = smooth and p >= previous and (previous < 0 or p - previous < 0.002)
		previous = p
	expect(bounded, "All time, count, frequency and strength values stay bounded over an hour")
	expect(smooth, "Time pressure grows monotonically without jumps")
	var ceiling := Hard.target_pressure(s)
	s.elapsed = 1000000.0
	expect(is_equal_approx(Hard.target_pressure(s), ceiling), "Long sessions reach a plateau, not runaway growth")
	s.elapsed = 900.0
	s.buildings.clear()
	s.technologies.clear()
	s.buildings.append({"kind": "generator", "hp": 100.0, "remaining": 0.0})
	var bare := Hard.target_pressure(s)
	var tower := {"kind": "tower", "hp": 200.0, "remaining": 10.0}
	s.buildings.append(tower)
	expect(is_equal_approx(Hard.target_pressure(s), bare), "Unfinished buildings add no pressure")
	tower.remaining = 0.0
	var built := Hard.target_pressure(s)
	expect(built > bare, "A completed defense increases hard-mode pressure")
	tower.refit = "rapid"
	var refitted := Hard.target_pressure(s)
	expect(refitted > built, "Defense refits contribute to camp strength")
	s.technologies.defense = true
	expect(Hard.target_pressure(s) > refitted, "Completed technology adds pressure")
	s.technologies.clear()
	tower.hp = 0.0
	expect(is_equal_approx(Hard.target_pressure(s), bare), "Destroyed defenses no longer count")
	s.buildings.clear()
	mature_camp(s)
	var late := Hard.profile(Hard.target_pressure(s))
	var weak := Hard.profile(bare)
	expect(late.count > weak.count and late.interval < weak.interval and late.health > weak.health and late.damage > weak.damage, "An advanced camp gets more, faster, stronger attackers")
	for time in [100.0, 359.0, 360.0, 719.0, 720.0, 1200.0, 1500.0]:
		s.elapsed = time
		var group := Hard.group(time, Hard.target_pressure(s))
		expect(group.size() <= Hard.MAX_WAVE_SIZE and (group.has("raptor") or group.has("small_raptor")), "Wave retains ordinary dinosaurs at " + str(time))
		expect((time >= 360) == group.has("young_trex") or time >= 720, "Juvenile gate at " + str(time))
		expect((time >= 720) == group.has("trex"), "Adult gate at " + str(time))
	expect(Hard.group(100, 0) == ["small_raptor", "small_raptor"], "First wave contains just two small raptors")
	expect(Hard.group(1500, 1).count("trex") == 2, "Peak mixed wave has at most two adults")

func make_world() -> Node:
	var w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.sound.set_process(false)
	return w

func clear_animals(w: Node) -> void:
	for d in w.dinosaurs: d.free()
	w.dinosaurs.clear()

func test_runtime() -> void:
	var w := make_world()
	expect(w.spawn_clocks.size() == 2 and w.spawn_clocks[1].period == 160, "Classic clocks remain unchanged")
	w.start_session(1500.0, "standard")
	expect(w.spawn_clocks[0].next == 100 and w.spawn_clocks[0].period == 95, "Standard opening and interval unchanged")
	w.session.elapsed = 900.0
	expect(w.director.group() == ["trex", "raptor", "young_trex"], "Standard late group unchanged")
	w.director.update()
	expect(w.dinosaurs.size() == 3 and w.dinosaurs[0].max_health == 1000 and w.dinosaurs[0].attack_damage == 20, "Standard enemies retain original stats and wave size")
	clear_animals(w)
	w.session.elapsed = 0.0
	w.hud.hard_start_button.pressed.emit()
	expect(w.session.mode == "hard" and w.started and w.session.duration == 1500 and w.spawn_clocks[0].next == 100, "New-game button starts hard mode with preparation window")
	w.session.elapsed = 99.0
	w.director.update()
	expect(w.dinosaurs.is_empty(), "No timed dinosaurs before first wave")
	w.session.elapsed = 100.0
	w.director.update()
	expect(w.dinosaurs.size() == 2 and w.spawn_clocks[0].next == 200, "Opening spawns two dinosaurs and schedules one next wave")
	var all_patrol := true
	for d in w.dinosaurs: all_patrol = all_patrol and w.dino_ai.state(d) == "patrol" and not d.route.is_empty()
	expect(all_patrol, "Every hard-wave member approaches the camp along a real route")
	w.director.update()
	expect(w.dinosaurs.size() == 2, "Repeated director update cannot duplicate a wave")
	# Verify actual encounter rather than only number changes.
	w.hero.health = 10000.0
	for i in range(1800):
		w.update_dinosaurs(1.0 / 30.0)
		if w.hero.health < 10000: break
	expect(w.hero.health < 10000, "Opening patrol reaches and attacks a stationary survivor within 60 seconds")
	w.hero.health = w.hero.max_health
	clear_animals(w)
	w.session.elapsed = 1500.0
	w.spawn_clocks[0].next = 1500.0
	w.director.update()
	expect(w.spawn_clocks[0].pressure <= Hard.MAX_PRESSURE_STEP, "Sudden progress is smoothed per wave")
	for wave in range(8):
		clear_animals(w)
		w.session.elapsed = w.spawn_clocks[0].next
		w.director.update()
	var mixed := []
	for d in w.dinosaurs: mixed.append(d.get_meta("species"))
	expect(mixed.has("trex") and mixed.has("young_trex") and mixed.has("raptor") and mixed.has("small_raptor"), "Runtime late waves mix adult, juvenile and ordinary dinosaurs")
	expect(w.dinosaurs[0].max_health > 1000 and w.dinosaurs[0].max_health <= 1000 * Hard.MAX_HEALTH_MULTIPLIER and w.dinosaurs[0].attack_damage > 20 and w.dinosaurs[0].attack_damage <= 20 * Hard.MAX_DAMAGE_MULTIPLIER, "Live adult has capped increased health and damage")
	expect(w.dino_ai.tactics.heavy(w.dinosaurs[0]), "Hard adult retains telegraphed heavy attacks")
	var snapshot := Save.snapshot(w)
	expect(Save.validate(snapshot).is_empty(), "Hard live save passes validation: " + Save.validate(snapshot))
	expect(Save.write(w).is_empty(), "Hard save writes to a test-only directory")
	var saved := Save.read_slot("manual")
	expect(saved.has("data"), "Hard disk save can be read")
	var hp: float = w.dinosaurs[0].max_health
	var damage: float = w.dinosaurs[0].attack_damage
	var expected_next: float = w.spawn_clocks[0].next
	w.free()
	w = make_world()
	if saved.has("data"):
		Save.apply(w, saved.data)
		expect(w.session.mode == "hard" and w.spawn_clocks[0].next == expected_next, "Reload preserves hard mode, pressure and exact next-wave schedule")
		expect(w.dinosaurs[0].max_health == hp and is_equal_approx(w.dinosaurs[0].attack_damage, damage), "Reload restores spawn-time stats without recalculation or double scaling")
		w.hud.refresh_save_info()
		expect(w.hud.continue_button.text.contains("困难生存"), "Continue labels the hard save correctly")
	var bad := snapshot.duplicate(true)
	bad.spawn_clocks[0].pressure = 9.0
	expect(not Save.validate(bad).is_empty(), "Reject out-of-range saved pressure")
	bad = snapshot.duplicate(true)
	bad.animals[0].meta.ai_hard_damage_multiplier = 100.0
	expect(not Save.validate(bad).is_empty(), "Reject invalid saved damage multiplier")
	# Fill the cap cheaply; test spawn_group admits only available places.
	clear_animals(w)
	for i in range(Hard.LIVING_LIMIT - 1): w.spawn_dinosaur(w.hero.position, "small_raptor")
	w.director.spawn_group(Hard.group(1500, 1), false, 1)
	expect(w.director.living_count() == Hard.LIVING_LIMIT, "Ordinary hard waves obey the live cap")
	w.director.spawn_group(Hard.group(1500, 1), false, 1)
	expect(w.director.living_count() == Hard.LIVING_LIMIT, "Full island never overflows or removes existing enemies")
	var returning: Node3D = w.dinosaurs[0]
	# Choose a physically reachable idle animal; isolated woodland pockets must
	# not bypass the same collision rules merely because the population is full.
	var reachable := false
	for x in range(-8, 9):
		if reachable: break
		for y in range(-8, 9):
			var point: Vector3 = w.board.point(w.board.cell_at(w.hero.position) + Vector2i(x, y))
			if point.distance_to(w.hero.position) < 8 or not w.board.body_open(point, returning.body_radius): continue
			if w.dino_ai.patrol_route(point, w.hero.position, returning.body_radius).is_empty(): continue
			returning.position = point
			reachable = true
			break
	expect(reachable, "Cap fixture has an idle dinosaur with a real route to camp")
	returning.set_meta("ai_state", "idle")
	returning.health -= 5.0
	var remaining_health: float = returning.health
	w.dinosaurs.erase(returning)
	w.dinosaurs.push_front(returning)
	w.director.spawn_group(Hard.group(1500, 1), false, 1)
	expect(w.dino_ai.state(returning) == "patrol" and returning.health == remaining_health and w.director.living_count() == Hard.LIVING_LIMIT, "At the cap, idle patrols approach again without new spawns or free healing")
	w.session.phase = "evacuate"
	w.session.evacuation_elapsed = 181.0
	w.spawn_clocks[0].next = w.session.game_time()
	w.director.update()
	expect(w.director.living_count() == Hard.LIVING_LIMIT + Hard.EVACUATION_RESERVE, "Evacuation keeps late pressure with a bounded six-enemy reserve")
	w.hud.refresh(0)
	expect(w.hud.boarding_bar.visible, "Hard evacuation displays boarding progress")
	clear_animals(w)
	w.session.evacuation_elapsed = 240.0
	w.spawn_clocks[0].next = w.session.game_time()
	w.director.update()
	expect(w.dinosaurs.size() > 0 and w.dinosaurs[0].get_meta("ai_patrol_destination") == w.extraction, "Hard pressure continues beyond the three standard finale waves toward extraction")
	clear_animals(w)
	w.spawn_clocks.clear()
	w.hero.position = w.extraction
	w.paused = false
	w._physics_process(6.0)
	expect(w.session.phase == "evacuate" and w.session.boarding_progress == 6.0, "Hard mode requires holding extraction, not instant victory")
	w._physics_process(6.0)
	expect(w.session.phase == "won", "Hard mode remains winnable by holding extraction for twelve seconds")
	w.free()

func test_defended_camp() -> void:
	var w := make_world()
	w.start_session(1500, "hard")
	w.prepare_demo()
	clear_animals(w)
	w.session.technologies = {"tools": true, "defense": true, "pack_1": true}
	for b in w.session.buildings:
		if b.kind == "tower": b.refit = "rapid"
	w.session.elapsed = 900.0
	w.spawn_clocks[0].pressure = Hard.target_pressure(w.session)
	w.spawn_clocks[0].next = 900.0
	w.vision.update()
	w.director.update()
	var first_wave_last_id: int = w.session.next_dinosaur_id - 1
	var first_hits := false
	var later_hits := false
	var defender_hits := false
	var attackers := {}
	for tick in range(2100):
		w.session.tick(0.1)
		if tick % 10 == 0: w.vision.update()
		w.update_buildings(0.1)
		w.update_dinosaurs(0.1)
		w.update_effects(0.1)
		w.director.update()
		for d in w.dinosaurs:
			if d.health < d.max_health: defender_hits = true
			var strike: Dictionary = d.get_meta("ai_strike", {})
			if strike.get("kind", "") == "building":
				var id: int = d.get_meta("save_id")
				attackers[id] = true
				if id <= first_wave_last_id: first_hits = true
				else: later_hits = true
		# Auto-repair is a test fixture to keep the same powered defense available
		# for successive waves; attacks, damage and tower targeting stay real.
		for b in w.session.buildings: b.hp = w.Catalog.max_health(b)
		w.hero.health = w.hero.max_health
	expect(w.session.supply() >= w.session.demand() and defender_hits, "Established powered defenses actually fire on hard attackers")
	expect(first_hits and later_hits and attackers.size() >= 3, "Successive mixed waves repeatedly attack an upgraded camp, not just roam the island")
	print("HARD CAMP: attackers=", attackers.size(), " kills=", w.session.kills, " period=", w.spawn_clocks[0].period)
	w.free()

func run() -> void:
	Save.directory = "user://test_hard_%d" % Time.get_ticks_usec()
	test_curve()
	test_runtime()
	test_defended_camp()
	var folder := DirAccess.open(Save.directory)
	if folder:
		for file in folder.get_files(): folder.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.directory))
	print("HARD DIFFICULTY: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
