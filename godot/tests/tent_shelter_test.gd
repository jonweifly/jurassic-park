extends SceneTree
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
	expect(w.board.can_build(cell), "Fixture is legally buildable: " + kind)
	var b: Dictionary = w.session.build(kind, cell)
	b.remaining = 0.0
	w.board.block_building(cell, b.id)
	w.create_building_visual(b)
	return b

func fresh() -> void:
	w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.sound.set_process(false)

func run() -> void:
	Save.directory = "user://tent_shelter_fixture"
	fresh()
	w.start_session(1500, "standard")
	w.session.wood = 1000
	w.session.gold = 1000
	for x in range(54, 75):
		for y in range(77, 94): w.clear_tree(Vector2i(x, y))
	var tent := build("tent", Vector2i(60, 81))
	w.hero.position = w.board.point(tent.cell)
	w.hero.health = 40.0

	expect(not w.hero.is_sheltered(), "Standing on a tent is not shelter by itself")
	w.enter_shelter(w.hero, tent)
	expect(w.hero.is_sheltered() and w.hero.sheltered_id == tent.id, "Entering records the specific tent")
	expect(not w.hero.visual.model.visible, "Sheltered survivor is hidden")
	expect(w.visuals[tent.id].get_meta("occupied"), "Tent shows someone is inside")

	var raptor: Node3D = w.spawn_dinosaur(w.board.point(Vector2i(62, 81)), "raptor")
	var rex: Node3D = w.spawn_dinosaur(w.board.point(Vector2i(63, 81)), "trex")
	for d in w.dinosaurs: d.visible = true
	var target: Dictionary = w.dino_ai.visible_target(rex)
	expect(target.get("kind", "") != "hero", "Normal targeting skips a sheltered survivor")
	expect(w.dino_ai.tactics.preferred_target(raptor).get("kind", "") != "hero", "Raptor tactics skip a sheltered survivor")

	# Retaliation must not merely fail: it has to release so the tent becomes the target.
	w.dino_ai.provoke(rex, "hero", w.survivor_id(w.hero), w.hero.position)
	var retaliation: Dictionary = w.dino_ai.visible_target(rex)
	expect(retaliation.get("kind", "") != "hero", "Retaliation does not bite through the tent")
	expect(float(rex.get_meta("ai_retaliation")) == 0.0, "Retaliation is released against a sheltered survivor")
	expect(not retaliation.is_empty(), "Released retaliation finds the camp instead of freezing")

	var before: float = w.hero.health
	rex.set_meta("ai_strike", {"kind": "hero", "id": w.survivor_id(w.hero), "remaining": -1.0, "animated": true})
	w.dino_ai.resolve_strike(rex, 0.1)
	expect(w.hero.health == before, "A strike already in flight cannot land on a sheltered survivor")
	var spitter: Node3D = w.spawn_dinosaur(w.board.point(Vector2i(61, 81)), "spitter")
	w.dino_ai.specials.resolve(spitter, {"special": "acid", "impact": w.hero.position})
	expect(w.hero.health == before, "Area damage cannot reach a sheltered survivor")

	# The 40% warning must survive the global defence-notice throttle.
	w.defense_notice_after = w.session.game_time() + 100.0
	var full: float = Catalog.max_health(tent)
	tent.hp = full
	w.damage_building(tent, full * 0.75)
	expect(w.shelter_warned.has(tent.id), "Shelter warning ignores the defence notice throttle")

	tent.hp = 0.0
	w.refresh_shelters()
	expect(not w.hero.is_sheltered(), "A destroyed tent evicts the survivor")
	expect(w.hero.visual.model.visible, "An evicted survivor becomes visible again")
	expect(w.dino_ai.visible_target(rex).get("kind", "") == "hero", "An evicted survivor is attackable again")

	tent.hp = full
	w.enter_shelter(w.hero, tent)
	w.stop_order()
	expect(not w.hero.is_sheltered(), "Any new order leaves the tent")

	# The heal order is how a player actually gets inside, so drive that whole path.
	w.leave_shelter(w.hero)
	w.hero.health = 40.0
	w.session.gold = 5
	w.heal()
	expect(w.order == "heal", "Healing takes the tent order")
	expect(not w.hero.is_sheltered(), "Ordering a heal does not teleport into the tent")
	w.hero.route.clear()
	w.hero.position = w.board.point(tent.cell)
	w.worker.update(1.1)
	expect(w.hero.is_sheltered(), "Arriving at the tent enters the shelter")
	expect(w.hero.health > 40.0, "Healing restores health inside the tent")
	expect(w.session.gold == 4, "Healing bills one gold per second")

	w.session.gold = 0
	var broke: float = w.hero.health
	w.worker.update(1.1)
	expect(w.hero.is_sheltered(), "Running out of gold does not evict the survivor")
	expect(w.hero.health == broke, "Running out of gold pauses regeneration")

	w.hero.health = w.hero.max_health
	w.session.gold = 5
	w.worker.update(1.1)
	expect(not w.hero.is_sheltered(), "Finishing a heal leaves the tent")

	w.enter_shelter(w.hero, tent)
	var snapshot: Dictionary = Save.snapshot(w)
	expect(Save.validate(snapshot).is_empty(), "Shelter state saves cleanly")
	var stale: Dictionary = snapshot.duplicate(true)
	stale.hero.erase("sheltered_id")
	expect(not Save.validate(stale).is_empty(), "A save without the shelter field is rejected, not crashed")
	w.free()

	fresh()
	Save.apply(w, snapshot)
	expect(w.hero.sheltered_id == tent.id, "Load restores the shelter")
	expect(not w.hero.visual.model.visible, "Loaded shelter still hides the survivor")
	w.free()
	print("TENT SHELTER: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
