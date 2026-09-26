extends RefCounted
## Territorial perception. Exact inherited Warcraft acquisition ranges are unresolved;
## these meter values are provisional and intentionally local rather than map-wide.
const Specials = preload("res://scripts/dinosaur_specials.gd")
const Tactics = preload("res://scripts/dinosaur_tactics.gd")
const SENSES = {
	"small_raptor": {"sight": 8.0, "leash": 24.0, "wander": 6.0, "hearing": 0.9},
	"raptor": {"sight": 10.0, "leash": 30.0, "wander": 8.0, "hearing": 1.0},
	"young_trex": {"sight": 12.0, "leash": 36.0, "wander": 8.0, "hearing": 1.1},
	"spitter": {"sight": 17.0, "leash": 40.0, "wander": 8.0, "hearing": 1.1},
	"elite_raptor": {"sight": 13.0, "leash": 40.0, "wander": 9.0, "hearing": 1.15},
	"alpha_trex": {"sight": 18.0, "leash": 55.0, "wander": 10.0, "hearing": 1.3},
	"trex": {"sight": 15.0, "leash": 46.0, "wander": 10.0, "hearing": 1.2},
}

var world: Node
var noises: Array[Dictionary] = []
var next_noise_id := 1
var generator_clock := 0.0
var tactics: RefCounted
var specials: RefCounted

func spawn_patrol(species: String, destination_override: Variant = null) -> Node3D:
	# One member of each timed group approaches a snapshot of the camp location.
	# Other members remain territorial. No live target identity is assigned here.
	var destination: Vector3 = world.hero.position
	for b in world.session.buildings:
		if b.kind == "tent" and b.hp > 0 and b.remaining <= 0:
			destination = world.board.point(b.cell)
			break
	if destination_override is Vector3: destination = destination_override
	var center: Vector2i = world.board.cell_at(destination)
	var candidates: Array[Vector2i] = []
	for x in range(-24, 25):
		for y in range(-24, 25):
			var offset := Vector2i(x, y)
			if Vector2(offset).length() < 13 or Vector2(offset).length() > 24: continue
			if world.board.inside(center + offset): candidates.append(center + offset)
	# Seeded rotation gives varied entrances without a nondeterministic global shuffle.
	var start: int = world.rng.randi_range(0, candidates.size() - 1)
	for i in range(candidates.size()):
		var p: Vector3 = world.board.point(candidates[(start + i) % candidates.size()])
		if not safe_spawn(p) or not world.board.body_open(p, world.Board.species_radius(species)): continue
		var route := patrol_route(p, destination, world.Board.species_radius(species))
		if route.is_empty() or route.size() > 70: continue
		var d: Node3D = world.spawn_dinosaur(p, species)
		if not is_instance_valid(d): continue
		d.set_meta("ai_state", "patrol")
		d.set_meta("ai_patrol_destination", destination)
		d.set_meta("ai_patrol_seconds", 60.0)
		d.route = route
		d.path_cooldown = 1.0
		return d
	return world.spawn_dinosaur(Vector3(10000, 0, 0), species)

func patrol_route(from: Vector3, destination: Vector3, radius: float) -> PackedVector3Array:
	var route: PackedVector3Array = world.board.route(from, destination, true, radius)
	if not route.is_empty() or world.session.mode != "hard": return route
	# A sealed camp or narrow landing pad must not turn heavy attackers into
	# unrelated wilderness spawns. Approach a reachable outer defense first.
	for b in world.session.buildings:
		if b.hp <= 0: continue
		var point: Vector3 = world.board.point(b.cell)
		if point.distance_to(destination) > 24.0: continue
		route = world.board.route(from, point, true, radius)
		if not route.is_empty(): return route
	# Large bodies can contest the landing pad approaches from open ground without
	# ignoring collision or clearing vegetation to force a path.
	var center: Vector2i = world.board.cell_at(destination)
	for distance in [3, 4, 6, 8]:
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var cell: Vector2i = center + offset * distance
			if not world.board.inside(cell): continue
			var point: Vector3 = world.board.point(cell)
			if not world.board.body_open(point, radius): continue
			route = world.board.route(from, point, false, radius)
			if not route.is_empty(): return route
	return route

func redirect_patrol(d: Node3D, destination: Vector3) -> bool:
	if d.health <= 0 or state(d) not in ["idle", "wander", "return"]: return false
	var route := patrol_route(d.position, destination, d.body_radius)
	if route.is_empty() or route.size() > 70: return false
	d.set_meta("ai_state", "patrol")
	d.set_meta("ai_patrol_destination", destination)
	d.set_meta("ai_patrol_seconds", 60.0)
	d.route = route
	d.path_cooldown = 1.0
	return true

func _init(owner_world: Node) -> void:
	world = owner_world
	tactics = Tactics.new(self, world)
	specials = Specials.new(self, world)

func register(d: Node3D, species: String) -> void:
	d.set_meta("ai_state", "idle")
	d.set_meta("ai_home", d.position)
	d.set_meta("ai_last_known", d.position)
	d.set_meta("ai_target_kind", "")
	d.set_meta("ai_target_id", -1)
	d.set_meta("ai_awareness", 0.0)
	d.set_meta("ai_wander_clock", world.rng.randf_range(1.5, 4.5))
	d.set_meta("ai_species", species)
	d.set_meta("ai_last_noise", 0)
	d.set_meta("ai_sense_clock", 0.0)
	d.set_meta("ai_retaliation", 0.0)
	d.target_id = -1
	d.last_board_revision = world.board.revision

func emit_noise(position: Vector3, radius: float, source_kind: String = "", source_id: int = -1, lifetime: float = 0.8) -> void:
	noises.append({"id": next_noise_id, "position": position, "radius": radius, "source_kind": source_kind, "source_id": source_id, "remaining": lifetime})
	next_noise_id += 1

func provoke(d: Node3D, source_kind: String, source_id: int, position: Vector3) -> void:
	if not is_instance_valid(d) or d.health <= 0: return
	d.set_meta("ai_state", "alert")
	d.set_meta("ai_target_kind", source_kind)
	d.set_meta("ai_target_id", source_id)
	d.set_meta("ai_last_known", position)
	d.set_meta("ai_awareness", 12.0)
	d.set_meta("ai_retaliation", 3.0)
	d.route.clear()
	d.path_cooldown = 0

func state(d: Node3D) -> String:
	return d.get_meta("ai_state", "idle")

func update(dt: float) -> void:
	generator_clock -= dt
	if generator_clock <= 0:
		generator_clock = 2.0
		for b in world.session.buildings:
			if b.kind == "generator" and b.hp > 0 and b.remaining <= 0:
				emit_noise(world.board.point(b.cell), 5.0, "building", b.id)
	for d in world.dinosaurs.duplicate(): update_one(d, dt)
	for event in noises.duplicate():
		event.remaining -= dt
		if event.remaining <= 0: noises.erase(event)

func update_one(d: Node3D, dt: float) -> void:
	if d.health <= 0:
		update_death(d, dt)
		return
	var frozen: bool = world.Regions.at(d.position) == "ice"
	if not d.get_meta("stationary_test", false): d.speed = d.get_meta("base_speed") * (0.7 if frozen else 1.0) * world.DefenseCombat.slow_factor(d)
	if d.has_meta("ai_electric_slow"): d.set_meta("ai_electric_slow", maxf(0.0, float(d.get_meta("ai_electric_slow")) - dt))
	d.attack_interval = d.get_meta("base_interval") / (0.7 if frozen else 1.0)
	d.set_meta("ai_awareness", maxf(0, float(d.get_meta("ai_awareness")) - dt))
	d.set_meta("ai_wander_clock", float(d.get_meta("ai_wander_clock")) - dt)
	d.set_meta("ai_retaliation", maxf(0, float(d.get_meta("ai_retaliation")) - dt))
	d.set_meta("ai_sense_clock", float(d.get_meta("ai_sense_clock")) - dt)
	if d.last_board_revision != world.board.revision:
		d.route.clear()
		d.path_cooldown = 0
		d.set_meta("ai_wander_clock", 0.0)
		d.last_board_revision = world.board.revision
	d.advance(dt)
	d.position.y = world.board.layout.height_at(d.position.x, d.position.z)
	if resolve_strike(d, dt): return

	if float(d.get_meta("ai_sense_clock")) <= 0:
		d.set_meta("ai_sense_clock", 0.25)
		# Returning animals do not immediately reacquire a distant camp or old noise.
		var returning: bool = state(d) == "return" and d.position.distance_to(d.get_meta("ai_home")) > 2.5
		if not returning:
			var seen := visible_target(d)
			if not seen.is_empty():
				engage(d, seen)
				tactics.share_sighting(d, seen)
			elif float(d.get_meta("ai_retaliation")) <= 0:
				var noise := audible_noise(d)
				if not noise.is_empty(): investigate(d, noise)

	var current_state := state(d)
	if current_state in ["alert", "investigate"]:
		var home: Vector3 = d.get_meta("ai_home")
		var senses: Dictionary = senses_for(d)
		if float(d.get_meta("ai_awareness")) <= 0 or d.position.distance_to(home) > senses.leash:
			begin_return(d)
		elif not tactics.flank(d, dt):
			pursue_last_known(d)
	elif current_state == "return":
		update_return(d)
	elif current_state == "patrol":
		update_patrol(d, dt)
	else:
		update_wander(d)

	attack_if_close(d)

func update_death(d: Node3D, dt: float) -> void:
	if not d.dying:
		world.sound.play_at("collapse", d.position, -4)
		d.dying = true
		d.route.clear()
		world.session.record_kill(str(d.get_meta("species", "")))
		world.session.gold += 3 # Existing provisional kill reward.
		# Hunting reward feeds the optional survival loop without changing the
		# existing gold economy.
		world.session.add_hunted_food(2 if d.get_meta("ai_species", "raptor") in ["trex", "young_trex"] else 1)
	d.advance(dt)
	d.death_clock -= dt
	if d.death_clock <= 0:
		world.dinosaurs.erase(d)
		d.queue_free()

func senses_for(d: Node3D) -> Dictionary:
	return SENSES.get(d.get_meta("ai_species", "raptor"), SENSES.raptor)

func visible_target(d: Node3D) -> Dictionary:
	var senses := senses_for(d)
	var home: Vector3 = d.get_meta("ai_home")
	var best := float(senses.sight)
	var result: Dictionary = {}
	# Briefly prioritize the actual attacker over a nearer, unrelated camp building.
	var retaliating: bool = float(d.get_meta("ai_retaliation")) > 0
	if retaliating:
		var kind: String = d.get_meta("ai_target_kind")
		var id: int = d.get_meta("ai_target_id")
		var survivor: Node3D = world.survivor_by_id(id)
		# Give up retaliation against someone who reached a tent, otherwise the early
		# return below skips the building fallback and the dinosaur freezes on nothing.
		if kind == "hero" and survivor and survivor.is_sheltered():
			d.set_meta("ai_retaliation", 0.0)
			retaliating = false
	if retaliating:
		var position: Vector3 = d.get_meta("ai_last_known")
		var kind: String = d.get_meta("ai_target_kind")
		var id: int = d.get_meta("ai_target_id")
		var alive := false
		var survivor: Node3D = world.survivor_by_id(id)
		if kind == "hero" and survivor and survivor.health > 0:
			position = survivor.position
			alive = true
		elif kind == "building":
			var b: Dictionary = world.session.building(id)
			if not b.is_empty():
				position = world.board.point(b.cell)
				alive = true
		if alive and d.position.distance_to(position) <= best and has_line_of_sight(d.position, position):
			return {"kind": kind, "id": id, "position": position}
		return {}
	var preferred: Dictionary = tactics.preferred_target(d)
	if not preferred.is_empty(): return preferred
	for survivor in world.survivors():
		if survivor.health <= 0 or survivor.is_sheltered(): continue
		var distance := d.position.distance_to(survivor.position)
		if distance <= best and survivor.position.distance_to(home) <= senses.leash * 1.5 and has_line_of_sight(d.position, survivor.position):
			best = distance
			result = {"kind": "hero", "id": world.survivor_id(survivor), "position": survivor.position}
	for b in world.session.buildings:
		if b.hp <= 0: continue
		var position: Vector3 = world.board.point(b.cell)
		var distance := d.position.distance_to(position)
		if distance <= best and position.distance_to(home) <= senses.leash * 1.5 and has_line_of_sight(d.position, position):
			best = distance
			result = {"kind": "building", "id": b.id, "position": position}
	return result

func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	return world.vision.clear_line(world.board.cell_at(from), world.board.cell_at(to))

func audible_noise(d: Node3D) -> Dictionary:
	var hearing: float = senses_for(d).hearing
	var best := -INF
	var heard: Dictionary = {}
	for event in noises:
		if event.id <= int(d.get_meta("ai_last_noise")): continue
		var distance := d.position.distance_to(event.position)
		var reach: float = event.radius * hearing
		var strength := reach - distance
		if strength >= 0 and strength > best:
			best = strength
			heard = event
	return heard

func engage(d: Node3D, target: Dictionary) -> void:
	tactics.commit(d, target)
	if state(d) == "patrol": d.set_meta("ai_home", d.position)
	if d.get_meta("ai_target_kind") != target.kind or d.get_meta("ai_target_id") != target.id or state(d) not in ["alert", "investigate"]:
		d.path_cooldown = 0
		d.route.clear()
	d.set_meta("ai_state", "alert")
	d.set_meta("ai_target_kind", target.kind)
	d.set_meta("ai_target_id", target.id)
	d.set_meta("ai_last_known", target.position)
	d.set_meta("ai_awareness", 7.0)
	d.target_id = target.id if target.kind == "building" else -1

func investigate(d: Node3D, event: Dictionary) -> void:
	if state(d) == "return" and d.position.distance_to(d.get_meta("ai_home")) > senses_for(d).leash: return
	if state(d) == "patrol": d.set_meta("ai_home", d.position)
	d.set_meta("ai_state", "investigate")
	d.set_meta("ai_last_noise", event.id)
	d.set_meta("ai_last_known", event.position)
	d.set_meta("ai_target_kind", event.source_kind)
	d.set_meta("ai_target_id", event.source_id)
	d.set_meta("ai_awareness", maxf(5.0, float(d.get_meta("ai_awareness"))))
	d.path_cooldown = 0

func pursue_last_known(d: Node3D) -> void:
	var destination: Vector3 = d.get_meta("ai_last_known")
	if world.session.mode == "hard" and d.get_meta("species") == "spitter" and d.position.distance_to(destination) <= 11.5 and has_line_of_sight(d.position, destination):
		d.route.clear()
		return
	if d.position.distance_to(destination) <= 2.5 and visible_target(d).is_empty():
		d.set_meta("ai_awareness", minf(0.6, float(d.get_meta("ai_awareness"))))
		d.route.clear()
		return
	if d.path_cooldown > 0 and d.last_board_revision == world.board.revision: return
	d.path_cooldown = 0.65
	d.last_board_revision = world.board.revision
	d.route = patrol_route(d.position, destination, d.body_radius)
	if d.route.is_empty() and d.position.distance_to(destination) > 3:
		var blocker := reachable_local_building(d)
		if blocker.is_empty():
			d.set_meta("ai_awareness", minf(0.6, float(d.get_meta("ai_awareness"))))
		else:
			engage(d, {"kind": "building", "id": blocker.id, "position": world.board.point(blocker.cell)})
			d.route = world.board.route(d.position, world.board.point(blocker.cell), true, d.body_radius)

func reachable_local_building(d: Node3D) -> Dictionary:
	var best_route := INF
	var result: Dictionary = {}
	var radius: float = senses_for(d).sight + 4.0
	for b in world.session.buildings:
		if b.hp <= 0: continue
		var position: Vector3 = world.board.point(b.cell)
		if position.distance_to(d.position) > radius: continue
		if not has_line_of_sight(d.position, position): continue
		var route: PackedVector3Array = world.board.route(d.position, position, true, d.body_radius)
		if not route.is_empty() and route.size() < best_route:
			best_route = route.size()
			result = b
	return result

func begin_return(d: Node3D) -> void:
	d.set_meta("ai_state", "return")
	d.set_meta("ai_target_kind", "")
	d.set_meta("ai_target_id", -1)
	d.set_meta("ai_awareness", 0.0)
	d.target_id = -1
	d.path_cooldown = 0
	d.route.clear()

func update_return(d: Node3D) -> void:
	var home: Vector3 = d.get_meta("ai_home")
	if d.position.distance_to(home) <= 2.5:
		d.set_meta("ai_state", "idle")
		d.set_meta("ai_wander_clock", world.rng.randf_range(1.5, 4.0))
		d.route.clear()
		return
	if d.path_cooldown <= 0 or d.last_board_revision != world.board.revision:
		d.path_cooldown = 1.0
		d.last_board_revision = world.board.revision
		d.route = world.board.route(d.position, home, false, d.body_radius)

func update_wander(d: Node3D) -> void:
	if not d.route.is_empty() or float(d.get_meta("ai_wander_clock")) > 0: return
	var home: Vector3 = d.get_meta("ai_home")
	var radius: float = senses_for(d).wander
	for attempt in range(12):
		var angle: float = world.rng.randf() * TAU
		var distance: float = world.rng.randf_range(2.0, radius)
		var destination := home + Vector3(sin(angle) * distance, 0, cos(angle) * distance)
		if not world.board.inside(world.board.cell_at(destination)): continue
		var route: PackedVector3Array = world.board.route(d.position, world.board.point(world.board.cell_at(destination)), false, d.body_radius)
		if route.is_empty(): continue
		d.route = route
		d.set_meta("ai_state", "wander")
		break
	d.set_meta("ai_wander_clock", world.rng.randf_range(3.0, 7.0))

func update_patrol(d: Node3D, dt: float) -> void:
	var destination: Vector3 = d.get_meta("ai_patrol_destination")
	d.set_meta("ai_patrol_seconds", float(d.get_meta("ai_patrol_seconds")) - dt)
	if d.position.distance_to(destination) <= 3 or float(d.get_meta("ai_patrol_seconds")) <= 0:
		d.set_meta("ai_home", d.position)
		d.set_meta("ai_state", "idle")
		d.route.clear()
		return
	if d.path_cooldown > 0: return
	d.path_cooldown = 1.0
	d.route = patrol_route(d.position, destination, d.body_radius)
	if d.route.is_empty():
		var blocker := reachable_local_building(d)
		if not blocker.is_empty():
			engage(d, {"kind": "building", "id": blocker.id, "position": world.board.point(blocker.cell)})

func attack_if_close(d: Node3D) -> void:
	if state(d) != "alert" or d.attack_cooldown > 0: return
	var kind: String = d.get_meta("ai_target_kind", "")
	var position := Vector3.ZERO
	var building: Dictionary = {}
	if kind == "hero":
		var survivor: Node3D = world.survivor_by_id(int(d.get_meta("ai_target_id",-1)))
		if not survivor or survivor.health <= 0: return
		position = survivor.position
	elif kind == "building":
		building = world.session.building(int(d.get_meta("ai_target_id", -1)))
		if building.is_empty(): return
		position = world.board.point(building.cell)
	else: return
	if specials.begin(d, position, kind, int(d.get_meta("ai_target_id", -1))): return
	# Adjacent diagonal grid centers are sqrt(8) meters apart.
	if d.position.distance_to(position) > 3.0 or not has_line_of_sight(d.position, position): return
	d.route.clear()
	d.attack_cooldown = d.attack_interval
	var heavy: bool = tactics.heavy(d)
	d.swing = 0 if heavy else 1
	d.visual.face(position - d.position, 1)
	if not heavy: d.play_animation("attack", 0)
	if heavy:
		tactics.telegraph(d, 0.65)
		world.sound.play_dinosaur(d, true)
	d.set_meta("ai_strike", {"remaining": 0.65 if heavy else 0.18, "kind": kind, "id": int(d.get_meta("ai_target_id", -1)), "heavy": heavy, "animated": not heavy})

func resolve_strike(d: Node3D, dt: float) -> bool:
	var strike: Dictionary = d.get_meta("ai_strike", {})
	if strike.is_empty(): return false
	strike.remaining -= dt
	d.route.clear()
	if strike.has("special"):
		specials.advance(d, strike, dt)
		if strike.remaining <= 0:
			d.set_meta("ai_strike", {})
			specials.resolve(d, strike)
		return true
	if strike.remaining <= 0.18 and not strike.get("animated", true):
		strike.animated = true
		d.swing = 1
		d.play_animation("attack", 0)
	if strike.remaining > 0: return true
	d.set_meta("ai_strike", {})
	var survivor: Node3D = world.survivor_by_id(strike.id)
	var position: Vector3 = survivor.position if survivor else Vector3.ZERO
	var building: Dictionary = {}
	if strike.kind == "building":
		building = world.session.building(strike.id)
		if building.is_empty(): return true
		position = world.board.point(building.cell)
	elif not survivor or survivor.health <= 0 or survivor.is_sheltered(): return true
	# Damage is committed at contact; a survivor who leaves reach can dodge the bite.
	if d.position.distance_to(position) > 3.0 or not has_line_of_sight(d.position, position): return true
	world.sound.play_at("hit", position)
	var damage: float = d.attack_damage
	if building.is_empty(): survivor.health -= damage
	else:
		if strike.get("heavy", false): damage *= 1.5
		if building.kind in ["tower", "shelter", "gate"] and world.Regions.at(position) == "mountain": damage /= 1.18
		if building.kind in ["tower", "shelter", "gate"] and world.session.technologies.has("defense"): damage *= 0.8
		world.damage_building(building, damage)
	return true

func safe_spawn(position: Vector3) -> bool:
	if not world.board.is_open(world.board.cell_at(position)): return false
	if world.vision.is_visible(world.board.cell_at(position)): return false
	for survivor in world.survivors():
		if position.distance_to(survivor.position) < 24: return false
	for b in world.session.buildings:
		if b.hp > 0 and position.distance_to(world.board.point(b.cell)) < 20: return false
	return true
