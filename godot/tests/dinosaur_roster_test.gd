extends SceneTree
const Catalog = preload("res://scripts/dinosaur_catalog.gd")
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

func camp(towers: int, refit: String = "", tech: bool = false) -> RefCounted:
	var s = Session.new()
	s.mode = "hard"
	s.elapsed = 1350.0
	for i in range(towers): s.buildings.append({"kind": "tower", "hp": 200.0, "remaining": 0.0, "refit": refit, "cell": Vector2i(64,64)})
	for i in range(ceili(towers / 5.0)): s.buildings.append({"kind": "generator", "hp": 100.0, "remaining": 0.0})
	if tech: s.technologies.defense = true
	return s

func test_budget() -> void:
	var basic := camp(8)
	var rapid := camp(8, "rapid", true)
	expect(is_equal_approx(Hard.camp_metrics(basic).dps, 80.0), "Budget uses the real eight-tower DPS")
	expect(is_equal_approx(Hard.camp_metrics(rapid).dps, 8 * 10.0 / 0.6 * 1.3), "Budget includes rapid fire and damage research multiplicatively")
	expect(is_equal_approx(Hard.camp_metrics(rapid).durability, 8 * 200.0 / 0.8), "Defense research contributes effective durability")
	var previous := 0.0
	var increasing := true
	for count in [1, 4, 8, 12, 20]:
		var strength := Hard.camp_strength(camp(count, "rapid", true))
		increasing = increasing and strength > previous
		previous = strength
	expect(increasing, "Pressure remains responsive from one to twenty towers")
	var p := Hard.target_pressure(rapid)
	var wave := Hard.group(1350, p, 1)
	var target := Hard.health_target(rapid, wave, p)
	var hp := 0.0
	for kind in wave: hp += Catalog.spec(kind).hp * target
	expect(hp / float(Hard.camp_metrics(rapid).dps) >= 22, "Eight upgraded towers cannot erase the whole budget in only a few seconds")
	var weak_p := Hard.target_pressure(basic)
	expect(p > weak_p and Hard.profile(p).interval < Hard.profile(weak_p).interval, "Same tower count with stronger output receives more pressure and shorter intervals")
	var huge := camp(200, "rapid", true)
	expect(Hard.target_pressure(huge) <= 1.0 and Hard.health_target(huge, wave, 1) <= Hard.MAX_HEALTH_MULTIPLIER, "Huge bases cannot create unbounded stats")
	var before: float = Hard.camp_metrics(rapid).dps
	for b in rapid.buildings:
		if b.kind == "generator": b.hp = 0.0
	expect(Hard.camp_metrics(rapid).dps == 0 and Hard.camp_strength(rapid) < Hard.camp_strength(camp(8, "rapid", true)), "Power loss removes tower output without erasing surviving fortifications")
	expect(before > 0, "Power fixture had functioning defenses")
	var elites := Hard.group(1000, 0.7, 1)
	expect(elites.has("elite_raptor") and elites.has("spitter") and elites.has("raptor"), "Support waves mix elite, ranged and ordinary dinosaurs")
	expect(not Hard.group(1079, 1, 0).has("alpha_trex"), "No boss before eighteen minutes even for advanced camps")
	expect(Hard.group(1200, 0.8, 4).count("alpha_trex") == 1 and not Hard.group(1200, 0.8, 5).has("alpha_trex"), "Boss cadence leaves support waves between bosses")

func world_fixture(offset: Vector2i = Vector2i.ZERO) -> Node:
	var w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.sound.set_process(false)
	w.start_session(1500, "hard")
	w.session.wood = 10000
	w.session.gold = 10000
	for x in range(49, 81):
		for y in range(49, 81): w.clear_tree(Vector2i(x, y) + offset)
	for entry in [["tent", Vector2i(60,63)], ["generator", Vector2i(60,61)], ["tower", Vector2i(64,63)], ["tower", Vector2i(65,63)]]:
		if offset != Vector2i.ZERO: expect(w.board.can_build(entry[1] + offset), "Fortified fixture uses legal building terrain")
		var b: Dictionary = w.session.build(entry[0], entry[1] + offset)
		b.remaining = 0.0
		w.board.block_building(b.cell, b.id)
		w.create_building_visual(b)
	return w

func test_attacks_and_save() -> void:
	var w := world_fixture()
	var tower: Dictionary = w.session.buildings[2]
	var target: Vector3 = w.board.point(tower.cell)
	var marker: MeshInstance3D = w.dino_ai.specials.impact_marker(target, 4.2, Color.WHITE)
	var vertices: PackedVector3Array = marker.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var grounded := true
	for vertex in vertices:
		var p := vertex + marker.position
		grounded = grounded and absf(p.y - w.board.layout.height_at(p.x, p.z) - 0.06) < 0.001
	expect(grounded and marker.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Attack warning follows terrain without a floating shadow")
	expect(w.dino_ai.specials.within_impact(target + Vector3(4, 2, 0), target, 4.2) and not w.dino_ai.specials.within_impact(target + Vector3(4.3, 0, 0), target, 4.2), "Area damage matches the warning footprint on slopes")
	marker.free()
	var spitter: Node3D = w.spawn_dinosaur(target + Vector3(0, 0, 10), "spitter")
	w.dino_ai.provoke(spitter, "building", tower.id, target)
	w.dino_ai.attack_if_close(spitter)
	var strike: Dictionary = spitter.get_meta("ai_strike", {})
	expect(strike.get("special") == "acid" and tower.hp == 200, "Spitter initiates a visible ranged wind-up without instant damage")
	w.dino_ai.resolve_strike(spitter, 0.5)
	expect(tower.hp == 200, "Acid damage waits for impact")
	w.dino_ai.resolve_strike(spitter, 0.6)
	expect(tower.hp == 178, "Acid reaches a defense at ten meters")
	w.dino_ai.resolve_strike(spitter, 1)
	expect(tower.hp == 178, "Special strike resolves exactly once")
	w.hero.position = target + Vector3(0, 0, 7)
	spitter.attack_cooldown = 0
	w.dino_ai.provoke(spitter, "hero", -1, w.hero.position)
	w.dino_ai.attack_if_close(spitter)
	w.hero.position += Vector3(5, 0, 0)
	w.dino_ai.resolve_strike(spitter, 1.1)
	expect(w.hero.health == w.hero.max_health, "Survivor can leave the committed acid impact circle")
	var elite: Node3D = w.spawn_dinosaur(target + Vector3(0, 0, 6), "elite_raptor")
	w.dino_ai.provoke(elite, "building", tower.id, target)
	w.dino_ai.attack_if_close(elite)
	expect(elite.get_meta("ai_strike", {}).get("special") == "pounce", "Elite initiates a distinct six-meter pounce")
	var before := elite.position
	for i in range(40): w.dino_ai.resolve_strike(elite, 0.02)
	expect(elite.position.distance_to(before) > 1 and tower.hp < 178, "Pounce advances the real body and hits after wind-up")
	var boss: Node3D = w.spawn_dinosaur(target + Vector3(0, 0, 3), "alpha_trex")
	Hard.strengthen(boss, 0.75)
	w.dino_ai.provoke(boss, "building", tower.id, target)
	w.dino_ai.attack_if_close(boss)
	expect(boss.get_meta("ai_strike", {}).get("special") == "stomp", "Boss starts a telegraphed area stomp")
	w.hero.position = w.board.point(Vector2i(65, 62))
	var snapshot := Save.snapshot(w)
	expect(Save.validate(snapshot).is_empty(), "All new species and pending special attacks validate: " + Save.validate(snapshot))
	var boss_hp: float = boss.max_health
	var boss_damage: float = boss.attack_damage
	w.free()
	w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.sound.set_process(false)
	Save.apply(w, snapshot)
	boss = w.dinosaurs[-1]
	expect(boss.max_health == boss_hp and boss.attack_damage == boss_damage and boss.get_meta("ai_strike").special == "stomp", "Reload restores boss strength and pending attack without reapplying scaling")
	tower = w.session.buildings[2]
	var second: Dictionary = w.session.buildings[3]
	var first_hp: float = tower.hp
	w.dino_ai.resolve_strike(boss, 1.2)
	expect(tower.hp < first_hp and second.hp < 200, "Boss area strike damages multiple clustered defenses")
	tower.hp = 200.0
	second.hp = 200.0
	var centered_strike: Dictionary = {"special": "stomp", "impact": target}
	w.dino_ai.specials.resolve(boss, centered_strike)
	var core_damage: float = 200.0 - tower.hp
	var peripheral_damage: float = 200.0 - second.hp
	expect(core_damage > peripheral_damage and peripheral_damage > 0.0, "Boss stomp remains lethal at its center but loses damage across nearby towers")
	var tower_spacing := Vector2(w.board.point(second.cell).x - target.x, w.board.point(second.cell).z - target.z).length()
	expect(absf(peripheral_damage / core_damage - lerpf(1.0, 0.35, tower_spacing / 4.2)) < 0.02, "Stomp damage follows distance within its warning circle")
	expect(Catalog.received_damage("alpha_trex", 100, "tower") == 76 and Catalog.received_damage("alpha_trex", 100, "shelter") == 100, "Armor has a clear electric-defense counter")
	# Legacy hard saves predate wave and health-budget fields.
	var legacy := snapshot.duplicate(true)
	legacy.spawn_clocks[0].erase("wave")
	legacy.spawn_clocks[0].erase("health_multiplier")
	expect(Save.validate(legacy).is_empty(), "Earlier hard saves remain loadable")
	w.session.elapsed = 1300
	w.spawn_clocks[0].pressure = 0.8
	w.spawn_clocks[0].wave = 4
	w.spawn_clocks[0].next = 1300.0
	w.director.update()
	expect(w.dinosaurs.filter(func(d): return d.health > 0 and d.get_meta("species") == "alpha_trex").size() == 1, "Support waves cannot stack a second living boss")
	var corrupt := snapshot.duplicate(true)
	corrupt.animals[-1].meta.ai_strike.impact = "bad"
	expect(not Save.validate(corrupt).is_empty(), "Malformed special attack positions reject before loading")
	w.free()

func test_fortified_pressure() -> void:
	for mode in ["standard", "hard"]:
		var offset := Vector2i(0, 18)
		var w := world_fixture(offset)
		w.session.mode = mode
		w.session.technologies.defense = true
		for i in range(3):
			var cell := Vector2i(57 + i, 59) + offset
			expect(w.board.can_build(cell), "Extra generator uses legal terrain")
			var b: Dictionary = w.session.build("generator", cell)
			b.remaining = 0.0
			w.board.block_building(b.cell, b.id)
			w.create_building_visual(b)
		for cell in [Vector2i(62,61), Vector2i(64,61), Vector2i(66,61), Vector2i(62,65), Vector2i(64,65), Vector2i(66,65)]:
			expect(w.board.can_build(cell + offset), "Extra tower uses legal terrain")
			var b: Dictionary = w.session.build("tower", cell + offset)
			b.remaining = 0.0
			w.board.block_building(b.cell, b.id)
			w.create_building_visual(b)
		for b in w.session.buildings:
			if b.kind == "tower": b.refit = "rapid"
		w.session.elapsed = 1190
		w.hero.position = w.board.point(Vector2i(61,63) + offset)
		w.director.configure_hard() if mode == "hard" else w.director.configure()
		if mode == "hard":
			var p := Hard.target_pressure(w.session)
			w.spawn_clocks[0].pressure = p
			w.spawn_clocks[0].health_multiplier = Hard.health_target(w.session, Hard.group(1190,p,3), p)
			w.spawn_clocks[0].wave = 3
		w.spawn_clocks[0].next = 1190.0
		var total_damage := 0.0
		var peak_alive := 0
		var waves_with_hits := {}
		var boss_seen := false
		var tower_damage := 0.0
		for tick in range(2400):
			w.session.tick(0.1)
			if tick % 5 == 0: w.vision.update()
			var enemy_hp := 0.0
			for d in w.dinosaurs: enemy_hp += maxf(d.health, 0)
			w.update_buildings(0.1)
			for d in w.dinosaurs: enemy_hp -= maxf(d.health, 0)
			tower_damage += enemy_hp
			w.update_dinosaurs(0.1)
			w.update_effects(0.1)
			w.director.update()
			peak_alive = maxi(peak_alive, w.director.living_count())
			for d in w.dinosaurs:
				boss_seen = boss_seen or d.get_meta("species") == "alpha_trex"
			# Fixed-base damage measurement: repair between ticks only after measuring
			# damage. Real fire, visibility, routes and enemy deaths remain enabled.
			for b in w.session.buildings:
				var lost: float = w.Catalog.max_health(b) - b.hp
				if lost > 0:
					total_damage += lost
					waves_with_hits[int(w.spawn_clocks[0].get("wave", 0))] = true
				b.hp = w.Catalog.max_health(b)
			w.hero.health = w.hero.max_health
		print("FORTIFIED ", mode, " damage=", total_damage, " peak=", peak_alive, " kills=", w.session.kills, " hit_waves=", waves_with_hits.size(), " boss=", boss_seen, " tower_damage=", tower_damage, " power=", w.session.supply(), "/", w.session.demand())
		if mode == "hard":
			expect(total_damage > 500 and waves_with_hits.size() >= 2 and boss_seen and tower_damage > 1000, "Eight rapid towers with defense research still take repeated substantial wave damage and encounter a boss")
		else:
			expect(not boss_seen and peak_alive <= 12, "Standard mode keeps its small original waves without elites or bosses")
		w.free()

func test_models() -> void:
	for kind in Catalog.SPECIES:
		var d: Node3D = load("res://scenes/models/%s.tscn" % Catalog.spec(kind).model).instantiate()
		d.is_dinosaur = true
		root.add_child(d)
		var skeleton: Skeleton3D = d.get_node("Model/Rig/Skeleton3D")
		var meshes := skeleton.find_children("*", "MeshInstance3D", true, false).filter(func(mesh): return mesh.skin != null)
		expect(skeleton.get_bone_count() >= 20 and meshes.size() == 1 and meshes[0].skin != null, kind + " has a skinned anatomical mesh and articulated skeleton")
		var player: AnimationPlayer = d.visual.player
		expect(player.has_animation("attack") and player.has_animation("walk") and player.has_animation("death"), kind + " supplies production animations")
		player.play("attack", 0)
		player.seek(0.3, true)
		var jaw := skeleton.get_bone_pose_rotation(skeleton.find_bone("jaw"))
		player.seek(0, true)
		expect(jaw.angle_to(skeleton.get_bone_pose_rotation(skeleton.find_bone("jaw"))) > 0.2, kind + " attack animates the jaw")
		d.free()

func test_perimeter_replan() -> void:
	var w := world_fixture(Vector2i(0, 18))
	var destination: Vector3 = w.board.point(Vector2i(70, 81))
	for x in range(67, 74):
		for y in range(78, 85): w.board.block_terrain(Vector2i(x, y))
	var d: Node3D = w.spawn_dinosaur(w.board.point(Vector2i(62, 86)), "alpha_trex")
	expect(d != null, "Perimeter fixture has space for a boss body")
	if d:
		expect(w.board.route(d.position, destination, true, d.body_radius).is_empty(), "Sealed destination has no direct route")
		expect(w.dino_ai.redirect_patrol(d, destination), "Boss finds an accessible camp perimeter")
		d.path_cooldown = 0
		w.dino_ai.update_patrol(d, 0.1)
		expect(not d.route.is_empty(), "Patrol replanning preserves its reachable perimeter route")
	w.free()

func run() -> void:
	Save.directory = "user://roster_test_%d" % Time.get_ticks_usec()
	test_budget()
	test_attacks_and_save()
	test_models()
	test_perimeter_replan()
	test_fortified_pressure()
	print("DINOSAUR ROSTER: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
