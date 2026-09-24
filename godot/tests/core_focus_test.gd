extends SceneTree
const Features = preload("res://scripts/feature_policy.gd")
const Save = preload("res://scripts/save_store.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Session = preload("res://scripts/session.gd")
const Board = preload("res://scripts/board.gd")
const Terrain = preload("res://scripts/terrain_data.gd")
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func new_world() -> Node:
	var w = load("res://scenes/main.tscn").instantiate()
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.start_session(1500.0, "standard")
	w.spawn_clocks.clear()
	return w

func test_freeze_and_load() -> void:
	expect(not Features.peripheral_enabled, "Peripheral systems default to dormant in the production profile")
	world = new_world()
	world.session.hunger = 1.0
	world.session.fatigue = 99.0
	world.session.raw_meat = 3
	world.session.survival_damage = 12.0
	var hp: float = world.hero.health
	world._physics_process(30.0)
	expect(world.hero.health == hp and world.session.hunger == 1.0 and world.session.fatigue == 99.0, "Actual world tick neither starves, tires nor applies dormant pending damage")
	expect(world.session.survival_clock == 0 and not world.session.eat_food() and not world.session.cook_food(), "Food actions and survival clock are suspended")
	world.session.add_berries(2)
	world.session.add_hunted_food(2)
	expect(world.session.berries == 0 and world.session.raw_meat == 3, "Harvest and kill callbacks cannot accumulate hidden food")
	for role in Session.PROFESSIONS:
		world.session.profession = role
		expect(is_equal_approx(world.session.survivor_speed(), 5.6) and world.session.survivor_max_health() == 150 and world.session.survivor_damage() == 13 and world.session.carry_capacity_bonus() == 0, "Archived profession has no active modifiers: " + role)
	world.hud.refresh(0)
	expect(not world.hud.eat_button.visible and not world.hud.journal_button.visible and not world.hud.profession_select.is_visible_in_tree(), "Focused UI hides archived systems")
	world.free()
	# Produce a valid pre-focus snapshot through the archived module, then load
	# it under the real default profile and verify the data remains recoverable.
	Features.peripheral_enabled = true
	world = new_world()
	world.session.profession = "doctor"
	world.session.hunger = 1.0
	world.session.fatigue = 99.0
	world.hero.max_health = 170.0
	world.hero.health = 85.0
	world.session.adventure.run = preload("res://scripts/expedition_run.gd").create(1826)
	world.session.adventure.power_until = 1000.0
	world.session.adventure.scan_until = 1000.0
	world.session.adventure.sites.cache.status = "discovered"
	world.session.adventure.job = {"id": "cache", "inspect": true}
	world.order = "expedition"
	var saved := Save.snapshot(world)
	expect(Save.validate(saved).is_empty(), "Archived snapshot is valid before migration")
	var earlier := saved.duplicate(true)
	earlier.session.erase("profession")
	var migrated := Save.migrate(earlier)
	expect(Save.validate(migrated).is_empty() and migrated.session.adventure == earlier.session.adventure, "Earlier version-three saves gain profession without losing run history")
	world.free()
	Features.peripheral_enabled = false
	world = new_world()
	Save.apply(world, saved)
	expect(world.session.adventure == saved.session.adventure and world.session.hunger == 1 and world.session.fatigue == 99, "Old peripheral data survives loading exactly")
	expect(world.order == "idle" and world.hero.route.is_empty() and world.adventure.visuals.is_empty(), "Old investigation order stops without spawning inaccessible sites")
	expect(world.hero.max_health == 150 and world.hero.health == 75 and is_equal_approx(world.hero.speed, 5.6), "Old profession normalizes health ratio without free healing")
	expect(world.session.supply() == 0, "Old radio battery cannot supply hidden power")
	world.adventure.update(500)
	world.adventure.cancel_job()
	world.hud.expedition_panel.open()
	expect(not world.hud.expedition_panel.panel.visible and world.session.adventure == saved.session.adventure, "Dormant actions do not mutate retained data or open modals")
	var roundtrip := Save.snapshot(world)
	expect(Save.validate(roundtrip).is_empty() and roundtrip.session.adventure == saved.session.adventure, "Focused save preserves archived data through a second save")
	world.free()

func test_refits() -> void:
	world = new_world()
	world.prepare_demo()
	world.session.wood = 200
	world.session.gold = 200
	var tower: Dictionary
	var gate: Dictionary
	for b in world.session.buildings:
		if b.kind == "tower": tower = b
		if b.kind == "gate": gate = b
	gate.hp -= 60
	expect(world.session.refit(gate.id, "brace").is_empty(), "Damaged gate can be reinforced")
	expect(gate.hp == 420 and Catalog.max_health(gate) == 480, "Reinforcement retains sixty damage")
	var stock := Vector2i(world.session.wood, world.session.gold)
	expect(not world.session.refit(gate.id, "brace").is_empty() and stock == Vector2i(world.session.wood, world.session.gold), "Repeat upgrade cannot charge twice")
	expect(world.session.refit(tower.id, "range").is_empty() and Catalog.attack_range(tower) == 20 and Catalog.attack_interval(tower) == 1.35, "Long-range tower trades rate for coverage")
	expect(not world.session.refit(tower.id, "rapid").is_empty(), "Tower roles are mutually exclusive")
	var snapshot := Save.snapshot(world)
	expect(Save.validate(snapshot).is_empty(), "In-progress upgrades and invested costs validate")
	for d in world.dinosaurs: d.free()
	world.dinosaurs.clear()
	var enemy: Node3D
	for x in range(-10, 11):
		for y in range(-10, 11):
			var cell: Vector2i = tower.cell + Vector2i(x, y)
			var distance: float = world.board.point(cell).distance_to(world.board.point(tower.cell))
			if enemy or distance < 17 or distance > 19 or not world.board.is_open(cell): continue
			enemy = world.spawn_dinosaur(world.board.point(cell), "raptor")
	expect(enemy != null, "Real combat fixture has an open target cell")
	if enemy:
		enemy.visible = true
		world.update_buildings(1)
		expect(enemy.health == 100, "Refitting tower cannot fire during construction")
		world.session.tick(12)
		world.update_buildings(1)
		expect(enemy.health == 90 and is_equal_approx(tower.cooldown, 1.35), "Finished range tower hits at eighteen metres with its real cooldown")
		tower.refit = "rapid"
		tower.cooldown = 0.0
		world.update_buildings(1)
		expect(enemy.health == 90, "Rapid tower cannot fire outside eleven metres")
		enemy.position = world.board.point(tower.cell) + Vector3(8, 0, 0)
		world.update_buildings(0.1)
		expect(enemy.health == 80 and is_equal_approx(tower.cooldown, 0.6), "Rapid tower uses its actual faster firing interval inside coverage")
		world.session.buildings[2].hp = 0.0
		world.update_buildings(2)
		expect(enemy.health == 80, "Refits do not bypass camp power requirements")
	var bad := snapshot.duplicate(true)
	bad.session.buildings[0].refit = "rapid"
	expect(not Save.validate(bad).is_empty(), "Refit cannot be attached to an incompatible building in a save")
	bad = snapshot.duplicate(true)
	bad.survival.hunger = "bad"
	expect(not Save.validate(bad).is_empty(), "Malformed dormant survival fields are rejected before loading")
	world.free()
	world = new_world()
	Save.apply(world, snapshot)
	gate = world.session.building(gate.id)
	tower = world.session.building(tower.id)
	world.session.tick(12)
	expect(gate.remaining == 0 and tower.remaining == 0 and gate.hp == 420, "Loaded upgrade completes without charging or healing again")
	world.hero.position = world.board.point(gate.cell) + Vector3(0, 0, 2)
	world.paused = false
	world.selected_id = gate.id
	world.repair_selected()
	for i in range(150):
		world.hero.advance(0.1)
		world.worker.update(0.1)
	expect(gate.hp == 480 and world.order == "idle", "Gate repair command reaches reinforced health cap")
	var quote: Dictionary = world.session.demolition_quote(gate.id)
	expect(quote.wood == 13 and quote.gold == 10, "Refund includes construction plus reinforcement investment")
	world.demolish_building(gate.id)
	expect(not world.board.structures.has(gate.cell) and world.session.demolition_quote(gate.id).is_empty(), "Demolishing a refitted gate reopens passage exactly once")
	world.free()

func arena_build(kind: String, cell: Vector2i) -> Dictionary:
	var b: Dictionary = world.session.build(kind, cell)
	b.remaining = 0.0
	world.board.block_building(cell, b.id)
	return b

func test_tactics_and_pacing() -> void:
	world = new_world()
	world.board = Board.new()
	world.board.layout = Terrain.new()
	world.board.layout.heights.fill(0.0)
	world.board.layout.walk.fill(1)
	world.board.layout.build.fill(1)
	world.trees.clear()
	world.session.wood = 1000
	world.session.gold = 1000
	arena_build("tent", Vector2i(52, 60))
	arena_build("generator", Vector2i(53, 60))
	var wall := arena_build("gate", Vector2i(64, 64))
	for y in range(58, 71):
		if y != 64: world.board.block_building(Vector2i(64, y), wall.id)
	world.hero.position = world.board.point(Vector2i(66, 64))
	var d: Node3D = world.spawn_dinosaur(world.board.point(Vector2i(62, 64)), "raptor")
	expect(world.dino_ai.visible_target(d).get("kind") == "building", "Closed defense prevents opportunistic pursuit")
	world.board.remove_building(wall.cell)
	wall.open = true
	expect(world.dino_ai.visible_target(d).get("kind") == "hero", "Raptor prefers a visible survivor through the open gate")
	world.dino_ai.provoke(d, "building", wall.id, world.board.point(wall.cell))
	expect(world.dino_ai.visible_target(d).get("id") == wall.id, "Actual attacker still takes retaliation priority")
	world.dinosaurs.erase(d)
	d.free()
	d = world.spawn_dinosaur(world.board.point(Vector2i(61, 64)), "trex")
	world.dino_ai.engage(d, {"kind": "building", "id": wall.id, "position": world.board.point(wall.cell)})
	world.hero.position = d.position + Vector3(0, 0, 2)
	expect(world.dino_ai.visible_target(d).get("id") == wall.id, "Rex remains committed when a nearer non-attacking survivor appears")
	world.dino_ai.provoke(d, "hero", -1, world.hero.position)
	expect(world.dino_ai.visible_target(d).get("kind") == "hero", "Rex commitment does not suppress retaliation")
	d.set_meta("ai_retaliation", 0.0)
	wall.hp = 0
	expect(world.dino_ai.visible_target(d).get("kind") == "hero", "Destroyed commitment target releases the rex")
	world.director.configure()
	world.session.elapsed = 95
	d.set_meta("ai_state", "alert")
	world.director.update()
	d.set_meta("ai_state", "return")
	world.director.update()
	expect(world.spawn_clocks[0].next == 120, "Combat ending near a wave grants twenty-five seconds to rebuild")
	world.session.elapsed = 110
	d.set_meta("ai_state", "alert")
	world.director.update()
	d.set_meta("ai_state", "return")
	world.director.update()
	expect(world.spawn_clocks[0].next == 120, "Repeated disengagement cannot postpone the next wave forever")
	world.free()

func run() -> void:
	Save.directory = "user://core_focus_fixture"
	test_freeze_and_load()
	test_refits()
	test_tactics_and_pacing()
	print("CORE FOCUS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
