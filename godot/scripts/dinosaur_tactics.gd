extends RefCounted
## Standard-mode species roles. All coordination starts from a locally seen target.
var ai: RefCounted:
	get: return world.dino_ai
var world: Node

func _init(_owner_ai: RefCounted, owner_world: Node) -> void:
	world = owner_world

func enabled(d: Node3D) -> bool:
	return world.session.mode in ["standard", "hard"] and not d.get_meta("stationary_test", false)

func preferred_target(d: Node3D) -> Dictionary:
	if not enabled(d): return {}
	var senses: Dictionary = ai.senses_for(d)
	var home: Vector3 = d.get_meta("ai_home")
	if d.get_meta("species") in ["trex", "alpha_trex"] and d.age < float(d.get_meta("ai_commit_until", 0.0)):
		var b: Dictionary = world.session.building(int(d.get_meta("ai_commit_id", -1)))
		if not b.is_empty():
			var point: Vector3 = world.board.point(b.cell)
			if d.position.distance_to(point) <= senses.sight and point.distance_to(home) <= senses.leash * 1.5 and ai.has_line_of_sight(d.position, point):
				return {"kind": "building", "id": b.id, "position": point}
	if d.get_meta("species") not in ["raptor", "small_raptor", "elite_raptor"] or world.hero.health <= 0: return {}
	var point: Vector3 = world.hero.position
	var distance := d.position.distance_to(point)
	if distance > senses.sight or point.distance_to(home) > senses.leash * 1.5 or not ai.has_line_of_sight(d.position, point): return {}
	# Prefer an exposed survivor only if the body-sized path reaches them. An
	# open gate or short detour is attractive; sealed defenses stay real blockers.
	var route: PackedVector3Array = world.board.route(d.position, point, false, d.body_radius)
	if route.is_empty(): return {}
	var length := 0.0
	var previous := d.position
	for step in route:
		length += previous.distance_to(step)
		previous = step
	if length > minf(18.0, distance * 1.8 + 2.0): return {}
	return {"kind": "hero", "id": -1, "position": point}

func commit(d: Node3D, target: Dictionary) -> void:
	if not enabled(d) or d.get_meta("species") not in ["trex", "alpha_trex"] or target.kind != "building": return
	if int(d.get_meta("ai_commit_id", -1)) == target.id and d.age < float(d.get_meta("ai_commit_until", 0.0)): return
	d.set_meta("ai_commit_id", target.id)
	d.set_meta("ai_commit_until", d.age + 8.0)

func share_sighting(d: Node3D, seen: Dictionary) -> void:
	if not enabled(d) or d.get_meta("species") not in ["raptor", "small_raptor", "elite_raptor"]: return
	if d.age < float(d.get_meta("ai_pack_after", 0.0)): return
	d.set_meta("ai_pack_after", d.age + 5.0)
	var shared := false
	for ally in world.dinosaurs:
		if ally == d or ally.health <= 0 or ally.get_meta("species") not in ["raptor", "small_raptor", "elite_raptor"]: continue
		if ally.position.distance_to(d.position) > 10 or not ai.has_line_of_sight(d.position, ally.position): continue
		if ai.state(ally) in ["alert", "return"]: continue
		if ally.position.distance_to(ally.get_meta("ai_home")) > ai.senses_for(ally).leash: continue
		# A one-time location hint, never a live target ID or follow-the-player reference.
		ally.set_meta("ai_state", "investigate")
		ally.set_meta("ai_last_known", seen.position)
		ally.set_meta("ai_target_kind", "")
		ally.set_meta("ai_target_id", -1)
		ally.set_meta("ai_awareness", 4.0)
		ally.path_cooldown = 0
		shared = true
	if shared: world.sound.play_at("roar", d.position, -6)

func flank(d: Node3D, dt: float) -> bool:
	if not enabled(d) or d.get_meta("species") != "raptor" or ai.state(d) != "alert": return false
	var left: float = maxf(0, float(d.get_meta("ai_flank_left", 0.0)) - dt)
	d.set_meta("ai_flank_left", left)
	if left > 0 and not d.route.is_empty(): return true
	if d.age < float(d.get_meta("ai_flank_after", 0.0)): return false
	if d.get_meta("ai_target_kind") != "hero": return false
	var target: Vector3 = d.get_meta("ai_last_known")
	var distance := d.position.distance_to(target)
	if distance < 4.5 or distance > 11 or not ai.has_line_of_sight(d.position, target): return false
	var partner := false
	for ally in world.dinosaurs:
		if ally != d and ally.health > 0 and ally.get_meta("species") in ["raptor", "small_raptor", "elite_raptor"] and ally.position.distance_to(d.position) < 8:
			partner = true
			break
	if not partner: return false
	d.set_meta("ai_flank_after", d.age + 5.0)
	var heading := (target - d.position).normalized()
	var side := 1.0 if int(d.get_meta("save_id", 0)) % 2 == 0 else -1.0
	var point := target + Vector3(-heading.z, 0, heading.x) * side * 3.5
	point = world.board.point(world.board.cell_at(point))
	if point.distance_to(d.get_meta("ai_home")) > ai.senses_for(d).leash: return false
	if not world.board.is_open(world.board.cell_at(point)): return false
	var route: PackedVector3Array = world.board.route(d.position, point, false, d.body_radius)
	if route.is_empty() or route.size() > 10: return false
	d.route = route
	d.path_cooldown = 1.1
	d.set_meta("ai_flank_left", 1.1)
	return true

func heavy(d: Node3D) -> bool:
	return world.session.mode in ["standard", "hard"] and d.get_meta("species") in ["trex", "alpha_trex"]

func telegraph(d: Node3D, seconds: float) -> void:
	var marker: MeshInstance3D = world.ring(3.0, Color("efab62"))
	marker.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.position = d.position + Vector3.UP * 0.12
	marker.visible = d.visible
	world.effects.append({"node": marker, "remaining": seconds, "follow": d})
