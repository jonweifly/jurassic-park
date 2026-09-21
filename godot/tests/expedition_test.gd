extends SceneTree
const Catalog = preload("res://scripts/expedition_catalog.gd")
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

func make_world() -> Node:
	var w = load("res://scenes/main.tscn").instantiate()
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.start_session(1500.0, "standard")
	w.spawn_clocks.clear()
	return w

func arrive(id: String) -> void:
	var cell: Vector2i = world.session.adventure.sites[id].cell
	var route: PackedVector3Array = world.board.route(world.hero.position, world.board.point(cell), true)
	if not route.is_empty(): world.hero.position = route[-1]
	world.hero.route.clear()
	world.vision.update()
	world.adventure.refresh_visibility()

func work(seconds: float) -> void:
	for step in range(ceili(seconds * 30)): world.adventure.update(1.0 / 30)

func complete(id: String, choice: int = 0) -> void:
	arrive(id)
	var error: String = world.adventure.begin(id, choice)
	expect(error.is_empty(), "Reachable site action starts: " + id + " " + error)
	world.hero.route.clear()
	work(Catalog.SITES[id].seconds + 0.1)

func add_tent() -> Dictionary:
	var center: Vector2i = world.board.cell_at(world.hero.position)
	for x in range(-2, 3):
		for y in range(-2, 3):
			var c := center + Vector2i(x, y)
			if not world.board.can_build(c): continue
			var b: Dictionary = world.session.build("tent", c)
			b.remaining = 0.0
			world.board.block_building(c, b.id)
			world.create_building_visual(b)
			return b
	return {}

func test_sites_and_save() -> void:
	world = make_world()
	expect(world.session.adventure.sites.size() == 6, "Six real sites initialize on the authored island")
	var state: Dictionary = world.session.adventure
	for id in Catalog.SITE_ORDER:
		var site: Dictionary = state.sites[id]
		expect(not world.board.route(world.hero.position, world.board.point(site.cell), true).is_empty(), "Site has an actual approach route: " + id)
		expect(not world.board.can_build(site.cell), "Site footprint cannot be overlapped by camp construction: " + id)
		expect(world.adventure.visuals.has(id), "Site has an editable 3D scene: " + id)
		expect(site.status == "hidden", "Undiscovered site remains hidden: " + id)
	expect(not world.board.route(world.hero.position, world.extraction).is_empty(), "New sites preserve the evacuation route")
	var before_rng: int = world.rng.state
	world.adventure.restore()
	expect(world.rng.state == before_rng, "Site reconstruction does not perturb dinosaur RNG")
	arrive("cache")
	expect(state.sites.cache.status == "discovered", "Physical visibility discovers a site")
	var wood: int = world.session.wood
	expect(world.adventure.begin("cache", 0).is_empty(), "Salvage begins from the discovered site")
	world.hero.route.clear()
	work(3)
	var progress: float = state.sites.cache.progress
	world.stop_order()
	work(3)
	expect(state.sites.cache.progress == progress and world.session.wood == wood, "Cancelled salvage preserves progress without granting a reward")
	expect(world.adventure.begin("cache", 0).is_empty(), "Interrupted action resumes")
	world.hero.route.clear()
	work(5)
	expect(world.session.wood == wood + 18 and state.sites.cache.status == "completed", "Salvage grants the chosen reward only after real work")
	world.adventure.finish("cache")
	expect(world.session.wood == wood + 18 and not world.adventure.begin("cache", 1).is_empty(), "Completed sites cannot be farmed or change choice")
	world.session.wood = 100
	world.session.gold = 100
	arrive("relay")
	expect(world.adventure.begin("relay", 0).is_empty(), "Repair consumes its explicit investment")
	world.hero.route.clear()
	work(4)
	expect(world.session.wood == 92 and world.session.gold == 95, "Repair charges exact costs once")
	var snapshot := Save.snapshot(world)
	expect(Save.validate(snapshot).is_empty(), "Snapshot accepts in-progress exploration")
	world.free()
	world = make_world()
	Save.apply(world, snapshot)
	state = world.session.adventure
	expect(world.order == "expedition" and state.sites.relay.progress > 3.9 and state.sites.relay.paid, "Reload restores the active repair, progress and payment")
	expect(world.session.wood == 92 and world.session.gold == 95, "Reload does not duplicate costs")
	world.paused = false
	world.stop_order()
	expect(world.adventure.begin("relay", 0).is_empty(), "Paid repair resumes after loading")
	world.hero.route.clear()
	work(13)
	expect(world.session.wood == 92 and world.session.gold == 95 and world.session.duration == 1410, "Resumed repair is free and advances rescue once")
	for id in state.sites:
		expect(state.sites[id].status != "hidden", "Repaired relay reveals coordinates without clearing map fog: " + id)
	var bank: int = world.session.gold
	complete("nest")
	expect(state.cargo.has("nest") and world.session.gold == bank and state.sites.nest.status == "carried", "Sample becomes quest cargo rather than instant bank reward")
	world.adventure.deposit_samples()
	expect(world.session.gold == bank, "A sample without a tent cannot be deposited")
	snapshot = Save.snapshot(world)
	world.free()
	world = make_world()
	Save.apply(world, snapshot)
	world.paused = false
	state = world.session.adventure
	expect(state.cargo.has("nest") and state.sites.nest.status == "carried", "Carried sample survives a second scene reconstruction")
	var tent := add_tent()
	expect(not tent.is_empty(), "Sample return fixture uses a valid built tent")
	var route: PackedVector3Array = world.board.route(world.hero.position, world.board.point(tent.cell), true)
	if not route.is_empty(): world.hero.position = route[-1]
	world.adventure.deposit_samples()
	expect(world.session.gold == bank + 24 and state.cargo.is_empty(), "Returning to a completed tent credits the sample reward")
	world.adventure.deposit_samples()
	expect(world.session.gold == bank + 24, "Sample rewards cannot repeat")
	complete("clinic")
	expect(state.kits == 2, "Clinic grants actual usable medical supplies")
	world.hero.health = world.hero.max_health
	expect(not world.adventure.use_kit().is_empty() and state.kits == 2, "Full-health use does not waste a kit")
	world.hero.health = 70
	expect(world.adventure.use_kit().is_empty() and world.hero.health == 120 and state.kits == 1, "Portable kit restores fifty health and is consumed")
	expect(not world.adventure.use_kit().is_empty() and state.kits == 1, "Kit cooldown prevents immediate repeated use")
	complete("weather")
	complete("archive")
	expect(state.cargo.has("archive"), "Archive uses the return-to-camp task type")
	var return_error: String = world.adventure.return_samples()
	expect(return_error.is_empty() and not world.hero.route.is_empty(), "Journal can order a real path home with investigation cargo")
	world.hero.position = world.hero.route[-1]
	world.hero.route.clear()
	world.adventure.deposit_samples()
	expect(state.records.size() == 6 and state.story_rewarded and state.kits == 2, "Three narrative records complete the story chain and grant its one-time reward")
	world.adventure.deposit_samples()
	expect(state.kits == 2, "Narrative reward cannot be claimed twice")
	# A v1 save has no adventure field. Migration must preserve the original session exactly.
	var legacy := Save.snapshot(world)
	legacy.version = 1
	legacy.session.erase("adventure")
	var migrated := Save.migrate(legacy)
	expect(Save.validate(migrated).is_empty() and migrated.session.wood == legacy.session.wood and migrated.rng_state == legacy.rng_state, "Version-one save migrates additively without resetting the game")
	expect(legacy.version == 1 and not legacy.session.has("adventure"), "Migration does not mutate its input record")
	var invalid := Save.snapshot(world)
	invalid.session.adventure.sites.cache.progress = "broken"
	expect(not Save.validate(invalid).is_empty(), "Malformed exploration data is rejected before load")
	world.free()

func test_interruption_and_validation() -> void:
	world = make_world()
	world.session.wood = 20
	arrive("weather")
	expect(world.adventure.begin("weather", 0).is_empty(), "Weather repair starts with a valid paid choice")
	world.hero.route.clear()
	work(2)
	var progress: float = world.session.adventure.sites.weather.progress
	var enemy: Node3D = world.spawn_dinosaur(world.hero.position, "small_raptor")
	work(3)
	expect(world.session.adventure.sites.weather.progress == progress and world.adventure.summary().contains("暂停"), "Nearby danger suspends repair with an actionable HUD reason")
	enemy.position += Vector3(20, 0, 0)
	work(1)
	expect(world.session.adventure.sites.weather.progress > progress and world.session.wood == 14 and world.session.gold == 6, "Safe repair resumes without a second charge")
	var valid := Save.snapshot(world)
	var bad := valid.duplicate(true)
	bad.session.adventure.job.inspect = "invalid"
	expect(not Save.validate(bad).is_empty(), "Invalid inspection type is rejected before reconstruction")
	bad = valid.duplicate(true)
	bad.session.adventure.sites.clinic.cell = bad.session.adventure.sites.cache.cell
	expect(not Save.validate(bad).is_empty(), "Overlapping persisted landmarks are rejected")
	bad = valid.duplicate(true)
	bad.session.adventure.sites.weather.choice = -1
	expect(not Save.validate(bad).is_empty(), "Paid repair without a valid choice is rejected")
	bad = valid.duplicate(true)
	bad.session.adventure.events_done = ["map", "map"]
	expect(not Save.validate(bad).is_empty(), "Duplicate event state is rejected")
	bad = valid.duplicate(true)
	bad.session.adventure.history.append({"text": 12})
	expect(not Save.validate(bad).is_empty(), "Malformed journal history is rejected before UI formatting")
	world.session.phase = "evacuate"
	work(0.1)
	expect(world.order == "idle" and world.session.adventure.job.is_empty(), "Rescue arrival safely interrupts unfinished field work")
	world.free()

func test_events() -> void:
	world = make_world()
	var state: Dictionary = world.session.adventure
	world.session.elapsed = 181
	world.adventure.update_events()
	expect(state.offer == "map", "First radio event appears on its authored schedule")
	world.session.wood = 0
	world.session.gold = 0
	world.adventure.choose_event(0)
	expect(state.sites.cache.status == "known" and state.sites.clinic.status == "hidden", "Coordinate event reveals only its intended facility")
	expect(world.adventure.choose_event(0) != "", "Event cannot be selected twice")
	world.session.elapsed = 301
	world.adventure.update_events()
	expect(not world.adventure.choose_event(0).is_empty() and state.offer == "battery" and world.session.gold == 0, "Unaffordable choice preserves resources and pending message")
	world.session.gold = 100
	world.session.wood = 100
	var supply: int = world.session.supply()
	expect(world.adventure.choose_event(0).is_empty() and world.session.supply() == supply + 2, "Battery choice adds temporary power for its actual cost")
	world.session.elapsed = 482
	expect(world.session.supply() == supply, "Temporary power expires using game time")
	for event in Catalog.EVENTS:
		if state.events_done.has(event.id): continue
		world.session.elapsed = event.at + 1
		world.adventure.update_events()
		expect(state.offer == event.id, "Scheduled radio event is available: " + event.id)
		var paid: String = world.adventure.choose_event(0)
		expect(paid.is_empty() and state.events_done.has(event.id), "Radio choice resolves exactly once: " + event.id + " " + paid)
	expect(state.events_done.size() == 8, "All eight radio events are reachable")
	var gold: int = world.session.gold
	world.adventure.update_events()
	expect(state.offer.is_empty() and world.session.gold == gold, "Completed event timeline cannot replay rewards or charges")
	state.events_done.clear()
	state.offer = "battery"
	state.offer_until = world.session.elapsed - 1
	world.adventure.update_events()
	expect(state.events_done.has("battery") and world.session.gold == gold, "Expired choices are ignored without a penalty")
	world.free()

func test_tactics() -> void:
	world = make_world()
	# Same flat arena strategy as existing AI tests; island reachability is tested above.
	world.board = load("res://scripts/board.gd").new()
	world.board.layout = load("res://scripts/terrain_data.gd").new()
	world.board.layout.heights.fill(0.0)
	world.board.layout.walk.fill(1)
	world.board.layout.build.fill(1)
	world.trees.clear()
	world.hero.position = world.board.point(Vector2i(65, 62))
	var leader: Node3D = world.spawn_dinosaur(world.board.point(Vector2i(62, 62)), "raptor")
	var ally: Node3D = world.spawn_dinosaur(world.board.point(Vector2i(59, 62)), "small_raptor")
	var far: Node3D = world.spawn_dinosaur(world.board.point(Vector2i(54, 62)), "raptor")
	var seen := {"kind": "hero", "id": -1, "position": world.hero.position}
	world.dino_ai.tactics.share_sighting(leader, seen)
	expect(world.dino_ai.state(ally) == "investigate" and ally.get_meta("ai_target_kind") == "", "Nearby pack mate receives a position hint without a live target lock")
	expect(world.dino_ai.state(far) == "idle", "Pack coordination cannot alert distant dinosaurs")
	var last_known: Vector3 = ally.get_meta("ai_last_known")
	world.hero.position += Vector3(4, 0, 0)
	expect(ally.get_meta("ai_last_known") == last_known, "Shared sighting does not follow subsequent player movement")
	world.hero.position = seen.position
	world.dino_ai.engage(leader, seen)
	var flanked: bool = world.dino_ai.tactics.flank(leader, 0.033)
	expect(flanked and not leader.route.is_empty(), "A partnered raptor can choose a valid local flank route")
	var trex: Node3D = world.spawn_dinosaur(world.hero.position, "trex")
	world.dino_ai.provoke(trex, "hero", -1, world.hero.position)
	world.dino_ai.attack_if_close(trex)
	expect(trex.get_meta("ai_strike").remaining == 0.65 and not world.effects.is_empty(), "Adult tyrannosaur announces its heavy attack with a readable wind-up")
	world.dino_ai.resolve_strike(trex, 0.3)
	expect(world.hero.health == 150, "Telegraphed heavy attack does not cause early damage")
	world.hero.position += Vector3(8, 0, 0)
	world.dino_ai.resolve_strike(trex, 0.4)
	expect(world.hero.health == 150, "Leaving the telegraphed reach dodges the heavy attack")
	world.session.mode = "classic"
	expect(not world.dino_ai.tactics.heavy(trex), "Classic mode preserves previous attack pacing")
	world.free()

func run() -> void:
	test_sites_and_save()
	test_interruption_and_validation()
	test_events()
	test_tactics()
	print("EXPEDITION: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
