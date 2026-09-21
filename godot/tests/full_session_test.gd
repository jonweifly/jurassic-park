extends SceneTree
## Deterministic bot using actual orders, prices, health and gathering; no granted stock.
## This is a functional/balance smoke test, not a substitute for human playtesting.
var content_variation := false
var world: Node
var camp := Vector3.ZERO
var strategy := "logistics"
var use_radio := true
var failures := 0
var report: Array[Dictionary] = []
var victories := {"logistics": 0, "defense": 0}
var invariant_failure := false

func _initialize() -> void:
	call_deferred("run")

func count(kind: String) -> int:
	var total := 0
	for b in world.session.buildings:
		if b.kind == kind and b.hp > 0: total += 1
	return total

func gather(resource: String) -> void:
	if world.order in ["wood", "gold", "return"] and world.worker.resource_kind == resource: return
	if resource == "gold":
		for b in world.session.buildings:
			if b.kind == "fossil" and b.hp > 0 and b.remaining <= 0:
				world.command(world.board.point(b.cell))
				return
	else:
		var best := INF
		var target := Vector3.ZERO
		for c in world.trees:
			var p: Vector3 = world.board.point(c)
			if not world.vision.explored.has(c): continue
			var distance := p.distance_to(camp) + p.distance_to(world.hero.position) * 0.5
			if distance >= best: continue
			if world.board.route(world.hero.position, p, true).is_empty(): continue
			best = distance
			target = p
		if best < INF: world.command(target)

func afford(wood: int, gold: int) -> bool:
	if world.session.wood < wood:
		gather("wood")
		return false
	if world.session.gold < gold:
		gather("gold")
		return false
	return true

func ensure_building(kind: String, number: int = 1) -> bool:
	if count(kind) >= number: return true
	var spec: Dictionary = world.Catalog.BUILDINGS[kind]
	if not afford(spec.wood, spec.gold): return false
	if not world.session.can_afford(kind).is_empty(): return false
	world.select_build(kind)
	var center: Vector2i = world.board.cell_at(camp)
	var selected := Vector2i(-1, -1)
	var best := INF
	for radius in range(1, 5):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var cell := center + Vector2i(x, y)
				if not world.placement_error(cell).is_empty() or not world.placement_warning(cell).is_empty(): continue
				var p: Vector3 = world.board.point(cell)
				var score := p.distance_to(camp)
				if score < best:
					best = score
					selected = cell
	if selected.x >= 0: world.place_building(selected)
	else: world.command(camp)
	world.build_mode = ""
	return false

func technology(tech: String) -> bool:
	if world.session.technologies.has(tech): return true
	if not world.session.research_job.is_empty(): return false
	var spec: Dictionary = world.Catalog.TECH[tech]
	if not afford(spec.wood, spec.gold): return false
	world.session.begin_research(tech)
	return false

func think() -> void:
	if content_variation:
		# Exercise affordable drawn effects through normal event APIs, keeping a reserve.
		var adventure: Dictionary = world.session.adventure
		if not adventure.offer.is_empty() and world.session.phase == "playing":
			var event: Dictionary = world.adventure.Catalog.event(adventure.offer)
			var choice: Dictionary = event.choices[0]
			var take: bool = (choice.wood == 0 and choice.gold == 0) or (world.session.wood - choice.wood >= 30 and world.session.gold - choice.gold >= 20)
			world.adventure.choose_event(0 if take else 1)
		if world.hero.health <= 100: world.adventure.use_kit()
	if world.session.phase == "evacuate":
		if world.hero.position.distance_to(world.extraction) >= 2.8:
			if world.order != "move": world.command(world.extraction)
		else:
			for d in world.dinosaurs:
				if d.health > 0 and d.visible and d.position.distance_to(world.hero.position) <= 8:
					if world.order != "attack" or world.hero.target_id != d.get_instance_id(): world.command(d.position)
					break
		return
	# The bot reacts only to revealed nearby animals, like a player watching the camp.
	var target: Node3D = null
	var best := 10.0
	for d in world.dinosaurs:
		if d.health <= 0 or not d.visible: continue
		var distance: float = d.position.distance_to(world.hero.position)
		if distance < best:
			best = distance
			target = d
	if target:
		if best < 5.5 and target.get_meta("ai_target_kind", "") == "hero":
			var center: Vector2i = world.board.cell_at(world.hero.position)
			var escape: Vector3 = world.hero.position
			var score := -INF
			for x in range(-3, 4):
				for y in range(-3, 4):
					var cell := center + Vector2i(x, y)
					if not world.board.is_open(cell): continue
					var p: Vector3 = world.board.point(cell)
					var route: PackedVector3Array = world.board.route(world.hero.position, p)
					if route.is_empty() or route.size() > 6: continue
					var value: float = p.distance_to(target.position) - p.distance_to(camp) * 0.2
					if value > score:
						score = value
						escape = p
			if escape != world.hero.position:
				world.command(escape)
				return
		if world.order != "attack" or world.hero.target_id != target.get_instance_id(): world.command(target.position)
		return
	if world.hero.health < 90 and world.session.gold > 0 and world.session.has_completed("tent"):
		if world.order != "heal": world.heal()
		return
	if world.order == "heal" and world.hero.health < world.hero.max_health: return
	# Finish interrupted construction before buying another site.
	for b in world.session.buildings:
		if b.hp > 0 and b.remaining > 0 and not b.get("upgrading", false):
			if world.order != "build" or world.worker.target_id != b.id: world.command(world.board.point(b.cell))
			return
	for kind in ["tent", "fire", "fossil", "generator", "tower"]:
		if not ensure_building(kind): return
	if not world.session.has_completed("laboratory"):
		if not ensure_building("lab"): return
		if not afford(5, 5): return
		for b in world.session.buildings:
			if b.kind == "lab" and b.hp > 0 and b.remaining <= 0:
				world.selected_id = b.id
				world.research()
		return
	var projects := ["pack_1", "pack_2", "tools", "defense", "medicine", "radio"] if strategy == "logistics" else ["defense", "pack_1", "medicine", "pack_2", "tools", "radio"]
	if not use_radio: projects.erase("radio")
	for tech in projects:
		if world.session.technologies.has(tech): continue
		if world.session.research_job.is_empty():
			technology(tech)
			return
		break
	# Research runs autonomously, leaving the worker time to reinforce and maintain camp.
	if count("tower") < 3:
		if world.session.demand() + 1 > world.session.supply():
			ensure_building("generator", count("generator") + 1)
		else: ensure_building("tower", count("tower") + 1)
		return
	for b in world.session.buildings:
		if b.hp > 0 and b.hp < world.Catalog.BUILDINGS[b.kind].hp * 0.7:
			if world.session.wood < 5: gather("wood")
			elif world.order != "repair": world.command(world.board.point(b.cell))
			return
	gather("wood" if world.session.wood < world.session.gold else "gold")

func run() -> void:
	var cases := 2 if "--quick" in OS.get_cmdline_user_args() else 10
	for index in range(cases):
		strategy = "logistics" if index % 2 == 0 else "defense"
		use_radio = index < 8
		invariant_failure = false
		world = load("res://scenes/main.tscn").instantiate()
		root.add_child(world)
		world.set_process(false)
		world.set_physics_process(false)
		world.sound.set_process(false)
		world.start_session(1500.0, "standard", 8100 + index if content_variation else 0)
		world.rng.seed = 65065 + index
		camp = world.hero.position
		for tick in range(1805 * 30):
			if tick % 15 == 0: think()
			world._physics_process(1.0 / 30)
			if tick % 300 == 0:
				if world.session.wood < 0 or world.session.gold < 0 or world.director.living_count() > 42: invariant_failure = true
				await process_frame
			if world.session.phase in ["won", "lost"]: break
		var entry := {"seed": 65065 + index, "strategy": strategy, "content_seed": world.session.adventure.run.get("seed", 0), "events_resolved": world.session.adventure.events_done.size(), "radio": use_radio, "invariants": not invariant_failure, "result": world.session.phase, "elapsed": snappedf(world.session.elapsed, 0.1), "hp": world.hero.health, "kills": world.session.kills, "tech": world.session.technologies.keys(), "wood": world.session.wood, "gold": world.session.gold, "buildings": world.session.buildings.size()}
		report.append(entry)
		print("FULL SESSION ", JSON.stringify(entry))
		if world.session.phase == "won": victories[strategy] += 1
		# Survival admits normal defeat. Functional gates require a terminal outcome,
		# conserved economy, bounded population and evidence both investments can win.
		if world.session.phase not in ["won", "lost"] or invariant_failure: failures += 1
		world.queue_free()
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/core"))
	var file := FileAccess.open("res://captures/core/varied-session-report.json" if content_variation else "res://captures/core/full-session-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	for path in victories:
		if victories[path] == 0: failures += 1
	print("FULL SESSION: ", cases, " runs, ", failures, " functional failures; victories=", victories)
	quit(0 if failures == 0 else 1)
