extends SceneTree
var failures := 0
var checks := 0
var world: Node

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func step(seconds: float) -> void:
	for i in range(ceili(seconds * 30)): world._physics_process(1.0 / 30)

func free_cell(origin: Vector3, distance: float = 4, require_sight: bool = false) -> Vector2i:
	var center: Vector2i = world.board.cell_at(origin)
	for radius in range(1, 6):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var c := center + Vector2i(x, y)
				var p: Vector3 = world.board.point(c)
				if p.distance_to(origin) < distance: continue
				if require_sight and not world.vision.clear_line(center,c): continue
				if world.board.can_build(c) and p.distance_to(world.hero.position) >= 1.5 and not world.board.route(world.hero.position, p, true).is_empty(): return c
	push_error("No free fixture cell near survivor")
	return center

func place(kind: String) -> Dictionary:
	world.vision.update()
	world.select_build(kind)
	var c := free_cell(world.hero.position)
	world.place_building(c)
	world.build_mode = ""
	return world.building_at(c)

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(3600)
	world.spawn_clocks.clear()
	await physics_frame
	var picked: Vector3 = world.ground_at(world.camera.unproject_position(world.hero.position))
	expect(picked.distance_to(world.hero.position) < 0.15, "Mouse terrain picking must match elevated rendered ground")
	expect(world.board.SIDE == 128 and world.trees.size() > 2500, "Reference map must load at original cell dimensions with tree placements")
	var submerged_trees := 0
	for cell in world.trees:
		for tree_part in world.trees[cell].node.get_children():
			if world.board.layout.submerged_at(tree_part.global_position.x, tree_part.global_position.z): submerged_trees += 1
	expect(submerged_trees == 0, "Reference map does not register harvestable trees inside water")
	expect(world.hero.position.y > 1 and world.hero.position.y < 2.2, "Survivor starts in the low opening meadow")
	var reachable: Dictionary = {}
	var queue: Array[Vector2i] = [world.board.cell_at(world.hero.position)]
	reachable[queue[0]] = true
	var index := 0
	var reached_regions: Dictionary = {}
	while index < queue.size():
		var c := queue[index]
		index += 1
		reached_regions[world.Regions.at(world.board.point(c))] = true
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = c + delta
			if world.board.is_open(next) and not reachable.has(next):
				reachable[next] = true
				queue.append(next)
	for biome in ["mountain", "ice", "swamp", "rainforest"]:
		expect(reached_regions.has(biome), "Original opening must have a traversable route to " + biome)
	var tent := place("tent")
	expect(not tent.is_empty(), "Free initial tent must be placeable in the opening clearing")
	if tent.is_empty(): quit(1); return
	step(2)
	world.order = "idle"
	world.hero.route.clear()
	var remaining: float = tent.remaining
	step(12)
	expect(is_equal_approx(tent.remaining, remaining), "Interrupted construction must remain paused")
	world.command(world.board.point(tent.cell))
	step(12)
	expect(tent.remaining == 0, "Right-click site must resume and complete construction")
	var nearest := Vector2i.ZERO
	var best := INF
	for c in world.trees:
		var p: Vector3 = world.board.point(c)
		if p.distance_to(world.hero.position) < best and not world.board.route(world.hero.position, p, true).is_empty():
			nearest = c
			best = p.distance_to(world.hero.position)
	world.trees[nearest].wood = 1
	world.command(world.board.point(nearest))
	for i in range(600):
		step(1.0 / 30)
		if world.worker.cargo > 0: break
	expect(world.worker.cargo == 1 and world.session.wood == 0, "First chop carries one wood without changing stock")
	expect(not world.trees.has(nearest), "Depleted tree cluster must disappear from resource and navigation state")
	for i in range(600):
		step(1.0 / 30)
		if world.session.wood > 0: break
	expect(world.session.wood == 1, "Only return to tent may credit harvested wood")
	expect(world.order in ["wood", "return"], "Drop-off must automatically resume gathering")
	expect(world.board.cell_at(world.worker.resource_target) != nearest, "After depletion worker must automatically choose another reachable nearby tree")
	world.order = "idle"
	world.hero.route.clear()
	world.worker.cargo = 1
	world.worker.cargo_kind = "wood"
	world.worker.resource_kind = ""
	tent.hp = 0
	var wood_before: int = world.session.wood
	world.worker.begin_return()
	step(2)
	expect(world.order == "waiting_dropoff" and world.worker.cargo == 1 and world.session.wood == wood_before, "Destroyed return point must not credit or delete cargo")
	# Recreate a destination through normal construction, then explicitly return cargo.
	world.update_buildings(0)
	tent = place("tent")
	step(12)
	world.command(world.board.point(tent.cell))
	step(8)
	expect(world.worker.cargo == 0 and world.session.wood == wood_before + 1, "Cargo must survive interrupted orders and return exactly once")
	world.session.wood = 1000
	world.session.gold = 1000
	var fire := place("fire")
	step(7)
	expect(not fire.is_empty() and fire.remaining == 0, "Campfire must complete with worker present")
	var field := place("fossil")
	step(14)
	expect(not field.is_empty() and field.remaining == 0, "Excavation field is a constructed building requiring tent and fire")
	var gold_before: int = world.session.gold
	world.command(world.board.point(field.cell))
	step(15)
	expect(world.session.gold > gold_before, "Constructed fossil field must provide gold through return trips")
	world.order = "idle"
	world.hero.route.clear()
	world.paused = true
	var elapsed: float = world.session.elapsed
	world._physics_process(1)
	expect(world.session.elapsed == elapsed, "Pause must stop all gameplay")
	world.paused = false
	var generator := place("generator")
	step(13)
	expect(not generator.is_empty() and world.session.supply() == 5, "Worker-completed generator supplies power")
	var gate := place("gate")
	step(13)
	expect(not gate.is_empty() and not world.board.is_open(gate.cell), "Completed closed gate blocks navigation")
	world.toggle_gate(gate)
	step(4)
	expect(not world.board.is_open(gate.cell), "Gate must respect five second transition")
	step(1.2)
	expect(world.board.is_open(gate.cell) and gate.open, "Open gate must release its blocked cell")
	world.hero.position = world.board.point(gate.cell)
	world.hero.route.clear()
	world.toggle_gate(gate)
	step(5.2)
	expect(gate.open, "Gate cannot close on an occupant")
	world.hero.position = world.board.point(free_cell(world.hero.position))
	world.toggle_gate(gate)
	step(5.2)
	expect(not gate.open and not world.board.is_open(gate.cell), "Unoccupied gate can close and restore blocking")
	var tower := place("tower")
	step(22)
	expect(not tower.is_empty() and tower.remaining == 0, "Bow tower must be constructed through worker simulation")
	var enemy_cell := free_cell(world.board.point(tower.cell), 3, true)
	var target = world.spawn_dinosaur(world.board.point(enemy_cell))
	expect(is_instance_valid(target), "Tower combat fixture must spawn")
	if is_instance_valid(target):
		target.speed = 0
		target.set_meta("stationary_test", true)
		target.health = 15
		world.vision.update()
		var previous_kills: int = world.session.kills
		step(3)
		expect(world.session.kills == previous_kills + 1, "Powered tower must attack and kill a visible dinosaur")
	generator.hp = 0
	world.update_buildings(0)
	expect(world.board.is_open(generator.cell), "Destroyed generator must release navigation blocking")
	target = world.spawn_dinosaur(world.board.point(enemy_cell))
	if is_instance_valid(target):
		target.speed = 0
		target.set_meta("stationary_test", true)
		var hp: float = target.health
		step(2)
		expect(target.health == hp, "Power loss must immediately stop tower damage")
		target.health = 0
		world.update_dinosaurs(1)
	world.worker.cargo = 0
	world.worker.resource_kind = ""
	tent.hp = 50
	world.command(world.board.point(tent.cell))
	wood_before = world.session.wood
	step(8)
	expect(tent.hp > 50 and world.session.wood < wood_before, "Right-click damaged building must repair it and spend wood")
	world.order = "idle"
	world.hero.route.clear()
	var far_cell := Vector2i(15, 15)
	for c in [Vector2i(15, 15), Vector2i(50, 30), Vector2i(110, 100)]:
		if world.board.is_open(c): far_cell = c; break
	var d = world.spawn_dinosaur(world.board.point(far_cell))
	expect(is_instance_valid(d), "Hidden enemy fixture must spawn on open terrain")
	if is_instance_valid(d):
		world.vision.update()
		expect(not d.visible, "Unexplored enemies must be hidden in world and minimap")
		world.command(d.position)
		expect(world.order != "attack", "Right-clicking an unseen enemy cannot lock its identity")
		world.hero.position = world.board.point(free_cell(d.position, 2))
		world.hero.route.clear()
		world.vision.update()
		expect(d.visible, "Scouting into sight must reveal the enemy")
		world.hero.position = world.board.point(tent.cell + Vector2i(1, 0))
		world.vision.update()
		expect(not d.visible and world.vision.explored.has(far_cell), "Leaving an explored region hides enemies while retaining map memory")
		d.health = 0
		var kills: int = world.session.kills
		world.update_dinosaurs(0.1)
		expect(d.dying and d.animation_state == "death", "Defeated dinosaur must play editable death animation")
		world.update_dinosaurs(0.1)
		expect(world.session.kills == kills + 1, "Death animation must not duplicate kill rewards")
	world.session.phase = "evacuate"
	world.hero.position = world.extraction
	world.hero.route.clear()
	world.order = "idle"
	world._physics_process(0.1)
	expect(world.session.phase == "won", "Reaching extraction after rescue wins")
	world.queue_free()
	await create_timer(0.15).timeout
	print("WORLD: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
