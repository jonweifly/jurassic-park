extends SceneTree
const Session = preload("res://scripts/session.gd")
const Save = preload("res://scripts/save_store.gd")
const Catalog = preload("res://scripts/catalog.gd")
var checks := 0
var failures := 0
var world: Node

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func add(kind: String, cell: Vector2i) -> Dictionary:
	world.clear_tree(cell)
	var b: Dictionary = world.session.build(kind, cell)
	b.remaining = 0.0
	world.board.block_building(cell, b.id)
	world.create_building_visual(b)
	return b

func economy() -> void:
	var s = Session.new()
	s.wood = 1000
	s.gold = 1000
	for kind in ["tent", "fire", "generator", "shelter", "tower", "lab", "fossil", "gate"]:
		var b: Dictionary = s.build(kind, Vector2i(s.next_id, 2))
		expect(not b.is_empty(), "Can buy fixture " + kind)
		b.remaining = 0.0
	# Foundation + upgrade costs must be recovered, but research must not be refunded.
	var lab: Dictionary = s.buildings[5]
	expect(s.research(lab.id).is_empty(), "Upgrade can begin")
	expect(s.demolition_quote(lab.id) == {"wood": 5, "gold": 5}, "Lab quote includes foundation and paid upgrade")
	var legacy: Dictionary = lab.duplicate()
	lab.erase("invested_wood")
	lab.erase("invested_gold")
	expect(s.demolition_quote(lab.id) == {"wood": 5, "gold": 5}, "Old upgraded lab has conservative compatible refund")
	lab.merge(legacy, true)
	for b in s.buildings:
		var price := Vector2i(b.invested_wood, b.invested_gold)
		b.hp *= 0.5
		b.remaining = 5.0
		var before := Vector2i(s.wood, s.gold)
		var quote: Dictionary = s.demolish(b.id)
		expect(Vector2i(s.wood, s.gold) - before == Vector2i(floori(price.x * 0.25), floori(price.y * 0.25)), "Damaged unfinished refund is bounded: " + b.kind)
		expect(not quote.is_empty() and s.building(b.id).is_empty(), "Demolished record is unavailable: " + b.kind)
		before = Vector2i(s.wood, s.gold)
		expect(s.demolish(b.id).is_empty() and Vector2i(s.wood, s.gold) == before, "Repeat demolition cannot mint resources: " + b.kind)
	var tent: Dictionary = s.build("tent", Vector2i(10,10))
	s.phase = "won"
	expect(s.demolish(tent.id).is_empty() and tent.hp > 0, "Results screen cannot demolish")
	s.phase = "evacuate"
	expect(s.demolish(tent.id) == {"wood": 0, "gold": 0}, "Free tent can unblock a road during evacuation without reward")

func run() -> void:
	Save.directory = "user://demolition_test_fixture"
	economy()
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500, "standard")
	world.spawn_clocks.clear()
	world.session.wood = 200
	world.session.gold = 200
	var start: Vector2i = world.board.cell_at(world.hero.position)
	var exit_cell := start + Vector2i.RIGHT
	var tent := add("tent", exit_cell)
	# Enclose the survivor except for the paid/free structure blocking the only exit.
	var changed := []
	for x in range(-1,2):
		for y in range(-1,2):
			var cell := start + Vector2i(x,y)
			if cell in [start, exit_cell] or world.board.terrain.has(cell): continue
			changed.append(cell)
			world.board.block_terrain(cell)
	var target: Vector3 = world.board.point(start + Vector2i(2,0))
	expect(world.board.route(world.hero.position,target).is_empty(), "Fixture is genuinely trapped by the building")
	world.worker.assign("build", world.board.point(tent.cell), tent.id)
	world.selected_id = tent.id
	var revision: int = world.board.revision
	world.demolish_building(tent.id)
	expect(world.board.revision > revision and world.board.is_open(exit_cell), "Demolition immediately invalidates blocked navigation")
	expect(not world.board.route(world.hero.position,target).is_empty(), "Survivor now has a route out of the enclosure")
	expect(world.board.body_segment_open(world.hero.position,world.board.point(exit_cell),world.hero.body_radius), "Body collision clears with the route")
	expect(not world.visuals.has(tent.id) and world.order == "idle" and world.selected_id == -1, "Visual, selection and construction order are cleared")
	for cell in changed: world.board.block_terrain(cell, false)
	tent = add("tent", exit_cell)
	world.worker.cargo = 1
	world.worker.cargo_kind = "wood"
	world.worker.resource_kind = ""
	world.worker.begin_return()
	world.demolish_building(tent.id)
	expect(world.order == "waiting_dropoff" and world.worker.cargo == 1, "Removing last tent preserves cargo and waits for replacement")
	tent = add("tent", exit_cell)
	world.worker.update(1.1)
	expect(world.order == "return", "Replacement tent resumes cargo delivery")
	world.stop_order()
	world.worker.cargo = 0
	var generator := add("generator", start + Vector2i(0,-2))
	var gate := add("gate", start + Vector2i(2,0))
	gate.open = true
	world.board.remove_building(gate.cell)
	world.build_mode = "tent"
	expect(world.placement_error(gate.cell) == "此处已有建筑或设施", "An open gate is passable but still occupies its building plot")
	world.paused = true
	world.demolish_building(gate.id)
	expect(gate.hp > 0, "Paused gameplay cannot silently demolish")
	world.paused = false
	world.demolish_building(gate.id)
	expect(world.board.is_open(gate.cell) and world.session.building(gate.id).is_empty(), "Open gate demolition leaves the passage open")
	gate = add("gate", start + Vector2i(2,0))
	world.board.block_terrain(gate.cell)
	world.demolish_building(gate.id)
	expect(not world.board.is_open(gate.cell), "Demolition does not erase underlying terrain obstruction")
	world.board.block_terrain(gate.cell,false)
	var lab := add("lab", start + Vector2i(-2,0))
	world.session.research(lab.id)
	world.session.work(lab.id, 10)
	world.session.begin_research("tools")
	var remaining: float = world.session.research_job.remaining
	world.demolish_building(generator.id)
	world.session.tick(1)
	expect(world.session.research_job.remaining == remaining and not world.session.research_powered(), "Generator removal suspends paid research")
	world.demolish_building(lab.id)
	expect(not world.session.research_job.is_empty(), "Lab removal preserves paid research")
	var snap := Save.snapshot(world)
	expect(Save.validate(snap).is_empty(), "Post-demolition save is valid: " + Save.validate(snap))
	world.free()
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	Save.apply(world,snap)
	expect(world.session.demolition_quote(lab.id).is_empty() and not world.visuals.has(lab.id), "Load cannot resurrect or claim demolished building")
	expect(not world.board.structures.has(generator.cell), "Cleared building cell remains clear after load")
	expect(world.session.research_job.remaining == remaining, "Suspended research survives load")
	world.free()
	print("DEMOLITION: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
