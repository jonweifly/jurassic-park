extends SceneTree
const Combat = preload("res://scripts/defense_combat.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0
var w: Node
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func build(kind: String, cell: Vector2i) -> Dictionary:
	expect(w.board.can_build(cell), "Fixture is legally buildable")
	var b: Dictionary = w.session.build(kind, cell)
	b.remaining = 0.0
	w.board.block_building(cell, b.id)
	w.create_building_visual(b)
	return b
func run() -> void:
	Save.directory = "user://defense_tactics_fixture"
	w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.sound.set_process(false)
	w.start_session(1500, "hard")
	w.session.wood = 1000
	w.session.gold = 1000
	for x in range(54, 75):
		for y in range(77, 94): w.clear_tree(Vector2i(x,y))
	build("tent", Vector2i(60,81))
	var generator := build("generator", Vector2i(59,79))
	var tower := build("tower", Vector2i(64,81))
	var fence := build("shelter", Vector2i(64,85))
	var origin: Vector3 = w.board.point(tower.cell)
	var small: Node3D = w.spawn_dinosaur(w.board.point(Vector2i(64,83)), "raptor")
	var large: Node3D = w.spawn_dinosaur(w.board.point(Vector2i(68,82)), "alpha_trex")
	var ranged: Node3D = w.spawn_dinosaur(w.board.point(Vector2i(68,81)), "spitter")
	for d in w.dinosaurs: d.visible = true
	expect(w.defense.choose(tower, origin) == small, "Default targets nearest")
	tower.priority = "large"
	expect(w.defense.choose(tower, origin) == large, "Large priority picks boss ahead of small enemy")
	tower.priority = "ranged"
	expect(w.defense.choose(tower, origin) == ranged, "Ranged priority picks spitter")
	ranged.visible = false
	expect(w.defense.choose(tower, origin) == small, "Hidden preferred enemy falls back to visible nearest")
	ranged.visible = true
	w.defense.focus_uid = small.get_meta("save_id")
	expect(w.defense.choose(tower, origin) == small, "Focus overrides role")
	var saved_position: Vector3 = small.position
	small.position += Vector3(80,0,0)
	expect(w.defense.choose(tower, origin) == ranged, "Out-of-range focus does not stop local defense")
	small.position = saved_position
	w.defense.focus_uid = -1
	tower.erase("priority")
	expect(w.session.refit(tower.id, "heavy").is_empty(), "Heavy refit uses real cost and construction")
	expect(Catalog.target_priority(tower) == "large", "Heavy defaults to large targets")
	var boss_hp: float = large.health
	w.update_buildings(0.1)
	expect(large.health == boss_hp, "Under-construction heavy tower cannot attack")
	w.session.tick(18)
	w.update_buildings(0.1)
	expect(is_equal_approx(boss_hp - large.health, 36.0 * 1.35 * 0.94), "Heavy live shot uses large bonus and partial armor penetration")
	expect(is_equal_approx(tower.cooldown, 2.4), "Heavy real shot respects slow firing interval")
	expect(w.visuals[tower.id].has_node("Model/Gun/HeavyBow"), "Heavy refit has distinct weapon geometry")
	expect(Combat.hit_damage({"kind":"tower", "refit":"range"}, "spitter", 1) == 15, "Range tower bonuses remote attackers")
	expect(Combat.hit_damage({"kind":"tower", "refit":"range"}, "raptor", 1) == 10, "Range baseline remains unchanged")
	expect(Combat.hit_damage({"kind":"tower", "refit":"rapid"}, "raptor", 1) / 0.6 > Combat.hit_damage(tower, "raptor", 1) / 2.4, "Rapid retains better sustained light-target output")
	var metrics: Dictionary = preload("res://scripts/hard_difficulty.gd").camp_metrics(w.session)
	expect(is_equal_approx(metrics.dps, 36.0 / 2.4 + 15.0 * 0.35), "Hard budget shares actual heavy base DPS without canceling matchup bonuses")
	small.position = w.board.point(fence.cell) + Vector3(0,0,2)
	fence.cooldown = 0.0
	w.update_buildings(0.1)
	expect(small.get_meta("ai_electric_slow", 0.0) == 1.2, "Real powered fence hit slows")
	Combat.apply_slow(small)
	Combat.apply_slow(small)
	expect(Combat.slow_factor(small) == 0.65, "Multiple slows do not stack")
	Combat.apply_slow(large)
	expect(Combat.slow_factor(large) == 0.92, "Boss has strong slow resistance")
	w.dino_ai.update_one(small, 0.1)
	expect(is_equal_approx(small.speed, small.get_meta("base_speed") * 0.65), "Slow affects actual locomotion speed")
	w.dino_ai.update_one(small, 1.3)
	w.dino_ai.update_one(small, 0.01)
	expect(is_equal_approx(small.speed, small.get_meta("base_speed")), "Movement recovers after slow expires")
	small.set_meta("ai_electric_slow", 0.0)
	generator.hp = 0.0
	fence.cooldown = 0.0
	w.update_buildings(0.1)
	expect(Combat.slow_factor(small) == 1.0, "Unpowered fence cannot slow")
	# Restore the generator visual after the intentional destruction.
	generator.hp = 100.0
	w.board.block_building(generator.cell, generator.id)
	w.create_building_visual(generator)
	Combat.apply_slow(small)
	tower.priority = "ranged"
	w.defense.focus_uid = large.get_meta("save_id")
	var snapshot := Save.snapshot(w)
	expect(Save.validate(snapshot).is_empty(), "New tactical save validates")
	var legacy := snapshot.duplicate(true)
	legacy.erase("defense_focus_uid")
	for b in legacy.session.buildings: b.erase("priority")
	for a in legacy.animals: a.meta.erase("ai_electric_slow")
	expect(Save.validate(legacy).is_empty(), "Optional tactical fields preserve older saves")
	var bad := snapshot.duplicate(true)
	bad.session.buildings[0].refit = "heavy"
	expect(not Save.validate(bad).is_empty(), "Non-tower heavy refit is rejected")
	bad = snapshot.duplicate(true)
	bad.session.buildings[2].priority = "invalid"
	expect(not Save.validate(bad).is_empty(), "Bad priority is rejected")
	bad = snapshot.duplicate(true)
	bad.animals[0].meta.ai_electric_slow = 10.0
	expect(not Save.validate(bad).is_empty(), "Unbounded slow duration is rejected")
	w.free()
	w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	Save.apply(w, snapshot)
	expect(w.session.building(tower.id).priority == "ranged" and w.defense.focused().get_meta("species") == "alpha_trex", "Load restores priority and stable focus identity")
	expect(Combat.slow_factor(w.dinosaurs[0]) == 0.65, "Load preserves remaining slow")
	w.dinosaurs[1].health = 0
	expect(w.defense.focused() == null and w.defense.focus_uid == -1, "Dead focus is cleared")
	w.free()
	print("DEFENSE TACTICS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
