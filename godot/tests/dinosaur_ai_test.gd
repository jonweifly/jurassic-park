extends SceneTree
## Exercise actual pawns and navigation in a flat, deterministic arena. The existing
## world_test separately covers the imported island, towers, power and death rewards.
const Board = preload("res://scripts/board.gd")
const Data = preload("res://scripts/terrain_data.gd")
var world: Node
var failures := 0
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func reset_arena() -> void:
	for d in world.dinosaurs: d.free()
	world.dinosaurs.clear()
	world.board = Board.new()
	world.board.layout = Data.new()
	world.board.layout.heights.fill(0.0)
	world.board.layout.walk.fill(1)
	world.board.layout.build.fill(1)
	world.board.layout.rebuild_surface()
	world.trees.clear()
	world.session.buildings.clear()
	world.session.next_id = 1
	world.session.phase = "playing"
	world.session.wood = 10000
	world.session.gold = 10000
	world.hero.position = Vector3(81, 0, 81)
	world.hero.health = 10000
	world.hero.route.clear()
	world.order = "idle"
	world.dino_ai.noises.clear()
	world.dino_ai.generator_clock = 0
	world.vision.update()
	world.paused = false

func step(seconds: float) -> void:
	for i in range(ceili(seconds * 30)):
		world.dino_ai.update(1.0 / 30)

func spawn(position: Vector3, species: String = "raptor", stationary: bool = false) -> Node3D:
	var d: Node3D = world.spawn_dinosaur(position, species)
	if stationary:
		d.speed = 0
		d.set_meta("stationary_test", true)
	return d

func building(kind: String, position: Vector3) -> Dictionary:
	var b: Dictionary = world.session.build(kind, world.board.cell_at(position))
	if b.is_empty():
		expect(false, "Building fixture prerequisites: " + kind)
		return b
	b.remaining = 0
	world.board.block_building(b.cell, b.id)
	return b

func screen_between() -> void:
	# Dense trees block sight but have a reachable route around the ends.
	for z in range(-3, 4):
		var c: Vector2i = world.board.cell_at(Vector3(5, 0, 1 + z * 2))
		world.trees[c] = {}
		world.board.block_terrain(c)

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.spawn_clocks.clear()
	reset_arena()
	var tent := building("tent", Vector3(61, 0, 61))
	var d := spawn(Vector3(1, 0, 1))
	var home := d.position
	var moved := false
	for i in range(120):
		step(0.25)
		moved = moved or d.position.distance_to(home) > 1
		if i == 119: expect(d.position.distance_to(home) <= 12, "Distant idle dinosaur stays in its territory")
	expect(moved and world.dino_ai.state(d) in ["idle", "wander"], "Unaware dinosaur must wander without pursuing distant hero or tent")
	expect(d.get_meta("ai_target_kind") == "" and tent.hp == 100, "Distant camp must not become a target")

	reset_arena()
	world.hero.position = Vector3(9, 0, 1)
	d = spawn(Vector3(1, 0, 1), "raptor", true)
	step(0.3)
	expect(world.dino_ai.state(d) == "alert" and d.get_meta("ai_target_kind") == "hero", "Unobstructed target inside sight must be acquired")
	var last_seen: Vector3 = d.get_meta("ai_last_known")
	world.hero.position = Vector3(71, 0, 51)
	step(0.4)
	expect(d.get_meta("ai_last_known") == last_seen, "Lost sight must preserve last known position, not track unseen target")
	step(8)
	expect(world.dino_ai.state(d) in ["return", "idle", "wander"] and d.get_meta("ai_target_kind") == "", "Memory expires without permanent pursuit")

	reset_arena()
	world.hero.position = Vector3(9, 0, 1)
	screen_between()
	d = spawn(Vector3(1, 0, 1), "raptor", true)
	step(0.3)
	expect(world.dino_ai.state(d) == "idle", "Trees must prevent visual acquisition through forest")
	world.dino_ai.emit_noise(world.hero.position, 6, "hero")
	step(0.3)
	expect(world.dino_ai.state(d) == "idle", "Quiet gathering outside hearing radius must not alert dinosaur")
	world.dino_ai.emit_noise(world.hero.position, 22, "hero")
	step(0.3)
	expect(world.dino_ai.state(d) == "investigate", "Gunshot through forest should investigate its location")
	expect(not d.route.is_empty(), "Investigation must path around trees rather than through them")
	last_seen = d.get_meta("ai_last_known")
	world.hero.position = Vector3(61, 0, 61)
	step(1)
	expect(world.dino_ai.noises.is_empty() and d.get_meta("ai_last_known") == last_seen, "Noise expires and does not reveal subsequent source movement")

	reset_arena()
	world.hero.position = Vector3(13, 0, 1)
	var small := spawn(Vector3(1, 0, 1), "small_raptor", true)
	var large := spawn(Vector3(1, 0, 3), "trex", true)
	step(0.3)
	expect(world.dino_ai.state(small) == "idle" and world.dino_ai.state(large) == "alert", "Larger species has larger perception range")

	reset_arena()
	d = spawn(Vector3(1, 0, 1), "raptor", true)
	world.hero.position = Vector3(17, 0, 1)
	world.dino_ai.provoke(d, "hero", -1, world.hero.position)
	step(0.3)
	expect(world.dino_ai.state(d) == "alert" and d.get_meta("ai_target_kind") == "hero", "Actual damage provokes retaliation beyond normal sight")
	expect(d.get_meta("ai_last_known") == Vector3(17, 0, 1), "Retaliation remembers attack origin")
	world.hero.position = Vector3(51, 0, 51)
	step(13)
	expect(d.get_meta("ai_target_kind") == "", "Retaliation expires after target escapes")

	reset_arena()
	building("tent", Vector3(41, 0, 41))
	var generator := building("generator", Vector3(9, 0, 1))
	screen_between()
	d = spawn(Vector3(1, 0, 1), "raptor", true)
	step(3)
	expect(world.dino_ai.state(d) == "idle", "Generator beyond five-meter hearing range cannot alert through trees")
	world.board.remove_building(generator.cell)
	generator.cell = world.board.cell_at(Vector3(5, 0, 1))
	generator.remaining = 5
	world.dino_ai.generator_clock = 0
	step(0.1)
	expect(world.dino_ai.noises.is_empty(), "Unfinished generator must not emit engine noise")
	generator.remaining = 0
	world.dino_ai.generator_clock = 0
	step(0.1)
	expect(world.dino_ai.noises.size() == 1, "Completed generator emits localized gameplay noise independently of audio")
	generator.hp = 0
	world.dino_ai.generator_clock = 0
	step(1)
	expect(world.dino_ai.noises.is_empty(), "Destroyed generator stops emitting noise")

	reset_arena()
	world.hero.position = Vector3(9, 0, 1)
	d = spawn(Vector3(1, 0, 1))
	step(0.6)
	world.hero.position = Vector3(81, 0, 81)
	step(15)
	expect(d.position.distance_to(home) < 12 and world.dino_ai.state(d) in ["idle", "wander"], "After losing target dinosaur physically returns to its home territory")

	reset_arena()
	d = spawn(Vector3(1, 0, 1), "raptor", true)
	d.position = Vector3(33, 0, 1)
	world.hero.position = Vector3(35, 0, 1)
	step(0.1)
	expect(world.dino_ai.state(d) == "return", "Visible target cannot drag dinosaur indefinitely beyond its territory leash")

	reset_arena()
	world.hero.position = Vector3(9, 0, 1)
	d = spawn(Vector3(1, 0, 1))
	# A full barrier makes the hero unreachable; only a local visible wall is eligible.
	for y in range(Board.SIDE): world.board.block_terrain(Vector2i(66, y))
	var wall := building("tent", Vector3(3, 0, 3))
	var distant := building("tent", Vector3(-61, 0, -61))
	step(2)
	expect(wall.hp < 100 and distant.hp == 100, "Blocked attacker can damage nearby camp wall without selecting a remote building")
	wall.hp = 0
	step(0.4)
	expect(d.get_meta("ai_target_id") != distant.id, "Destroyed local target must never fall back to an unseen map-wide building")

	reset_arena()
	world.hero.position = Vector3(1, 0, 1)
	building("tent", Vector3(31, 0, 31))
	world.vision.update()
	expect(not world.dino_ai.safe_spawn(Vector3(3, 0, 1)), "Ambient spawns must not appear beside survivor")
	expect(not world.dino_ai.safe_spawn(Vector3(33, 0, 31)), "Ambient spawns must not appear beside a camp")
	for i in range(20):
		d = world.spawn_dinosaur()
		expect(is_instance_valid(d) and world.dino_ai.safe_spawn(d.position), "Random spawn must respect player and camp safe distance")

	# Audio settings and camera cannot affect gameplay perception.
	reset_arena()
	d = spawn(Vector3(1, 0, 1), "raptor", true)
	world.camera_focus = Vector3(100, 0, 100)
	world.dino_ai.emit_noise(Vector3(7, 0, 1), 7, "hero")
	step(0.3)
	expect(world.dino_ai.state(d) == "investigate", "Off-camera sounds still affect simulation, independent of sound playback culling")
	world.paused = true
	var remaining: float = world.dino_ai.noises[0].remaining
	world._physics_process(2)
	expect(world.dino_ai.noises[0].remaining == remaining, "Pause freezes noise events and dinosaur AI")

	reset_arena()
	world.hero.position = Vector3(1, 0, 1)
	d = spawn(Vector3(7, 0, 1), "raptor", true)
	world.vision.update()
	world.command(d.position)
	world.hero.attack_cooldown = 0
	world.update_order(0.1)
	expect(d.health == 87 and d.get_meta("ai_target_kind") == "hero", "Actual survivor shot must provoke the struck dinosaur")
	expect(world.dino_ai.noises.size() == 1 and world.dino_ai.noises[0].radius == 22, "Actual shot emits a local gunshot event")

	reset_arena()
	world.hero.position = Vector3(1, 0, 1)
	var cell: Vector2i = world.board.cell_at(Vector3(3, 0, 1))
	world.trees[cell] = {"wood": 20}
	world.board.block_terrain(cell)
	world.vision.update()
	world.worker.cargo = 0
	world.command(world.board.point(cell))
	world.hero.route.clear()
	world.worker.update(1.1)
	expect(world.worker.cargo == 1 and world.dino_ai.noises.size() == 1 and world.dino_ai.noises[0].radius == 6, "Actual harvesting emits only six-meter noise while preserving cargo flow")

	reset_arena()
	world.hero.position = Vector3(1, 0, 1)
	tent = building("tent", Vector3(3, 0, 1))
	tent.remaining = 10
	world.worker.noise_clock = 0
	world.worker.assign("build", world.board.point(tent.cell), tent.id)
	world.hero.route.clear()
	world.worker.update(0.1)
	expect(tent.remaining < 10 and world.dino_ai.noises.size() == 1 and world.dino_ai.noises[0].radius == 5, "Active construction emits five-meter noise from worker, not an idle site")
	world.order = "idle"
	world.dino_ai.noises.clear()
	world.worker.update(2)
	expect(world.dino_ai.noises.is_empty(), "Interrupted construction emits no noise")

	reset_arena()
	world.hero.position = Vector3(1, 0, 1)
	world.vision.update()
	d = world.dino_ai.spawn_patrol("raptor")
	expect(is_instance_valid(d) and world.dino_ai.state(d) == "patrol" and world.dino_ai.safe_spawn(d.position), "Scheduled patrol starts outside camp safety range with a reachable approach")
	var snapshot: Vector3 = d.get_meta("ai_patrol_destination")
	world.hero.position = Vector3(-101, 0, -101)
	step(20)
	expect(d.get_meta("ai_patrol_destination") == snapshot and d.get_meta("ai_target_kind") == "", "Patrol follows its initial area, never the escaped survivor's live position")
	expect(d.position.distance_to(snapshot) < 12, "Unopposed patrol reaches the camp area and resumes local wandering")

	reset_arena()
	world.hero.position = Vector3(3, 0, 1)
	d = spawn(Vector3(0.1, 0, 3.9))
	var health_before: float = world.hero.health
	step(3)
	expect(world.hero.health < health_before, "Replanning inside the final adjacent cell must finish approaching melee range")
	world.queue_free()
	await create_timer(0.15).timeout
	print("DINOSAUR AI: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
