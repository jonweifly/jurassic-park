extends RefCounted
## Hard species attacks commit to visible positions and remain dodgeable.
var world: Node
var ai: RefCounted:
	get: return world.dino_ai
func _init(_owner_ai: RefCounted, owner_world: Node) -> void:
	world = owner_world

func begin(d: Node3D, target: Vector3, kind: String, id: int) -> bool:
	if world.session.mode != "hard": return false
	var species: String = d.get_meta("species", "")
	var special: String = {"spitter": "acid", "elite_raptor": "pounce", "alpha_trex": "stomp"}.get(species, "")
	if special.is_empty(): return false
	var reach: float = {"acid": 12.0, "pounce": 6.0, "stomp": 4.2}[special]
	if d.position.distance_to(target) > reach or not ai.has_line_of_sight(d.position, target): return false
	var duration: float = {"acid": 1.0, "pounce": 0.65, "stomp": 1.15}[special]
	var impact := d.position if special == "stomp" else target
	d.route.clear()
	d.attack_cooldown = d.attack_interval
	d.visual.face(target - d.position, 1)
	d.swing = 1.0
	d.play_animation("attack", 0)
	var strike := {"remaining": duration, "duration": duration, "kind": kind, "id": id, "special": special, "impact": impact, "animated": true}
	d.set_meta("ai_strike", strike)
	telegraph(d, strike)
	world.sound.play_dinosaur(d, true)
	return true

func telegraph(d: Node3D, strike: Dictionary) -> void:
	var acid: bool = strike.special == "acid"
	var radius := 1.8 if acid else (4.2 if strike.special == "stomp" else 2.0)
	var marker := impact_marker(strike.impact, radius, Color("bcd94e") if acid else Color("f19546"))
	marker.visible = d.visible
	world.effects.append({"node": marker, "remaining": strike.remaining})
	if acid:
		var orb := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.16
		mesh.height = 0.32
		mesh.radial_segments = 12
		mesh.rings = 6
		orb.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("c6da55")
		material.emission_enabled = true
		material.emission = Color("627727")
		orb.material_override = material
		world.add_child(orb)
		orb.position = d.position + Vector3.UP * 1.8
		orb.visible = d.visible
		world.effects.append({"node": orb, "remaining": strike.remaining, "flight_duration": strike.remaining,
			"flight_from": orb.position, "flight_to": strike.impact + Vector3.UP * 0.2})

func impact_marker(center: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(96):
		var a := TAU * i / 96.0
		var b := TAU * (i + 1) / 96.0
		var corners := [Vector2(cos(a), sin(a)) * radius, Vector2(cos(a), sin(a)) * (radius + 0.09),
			Vector2(cos(b), sin(b)) * radius, Vector2(cos(b), sin(b)) * (radius + 0.09)]
		for index in [0, 2, 1, 1, 2, 3]:
			var p: Vector2 = corners[index]
			var height: float = world.board.layout.height_at(center.x + p.x, center.z + p.y)
			surface.add_vertex(Vector3(p.x, height - center.y + 0.06, p.y))
	var marker := MeshInstance3D.new()
	marker.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.position = center
	world.add_child(marker)
	return marker

func advance(d: Node3D, strike: Dictionary, dt: float) -> void:
	# Stretch the actual skeletal clip over the warning, then contact at impact.
	var duration: float = strike.get("duration", {"acid": 1.0, "pounce": 0.65, "stomp": 1.15}[strike.special])
	d.swing = 1.0
	d.visual.play("attack", 0)
	var clip: Animation = d.visual.player.get_animation("attack")
	d.visual.player.seek(clampf(1.0 - float(strike.remaining) / duration, 0.0, 1.0) * clip.length * 0.65, true)
	if strike.special != "pounce" or strike.remaining > 0.2: return
	var next: Vector3 = d.position.move_toward(strike.impact, dt * 15.0 * world.DefenseCombat.slow_factor(d))
	if d.segment_open(d.position, next):
		d.position = next
		d.position.y = world.board.layout.height_at(next.x, next.z)

func resolve(d: Node3D, strike: Dictionary) -> void:
	var impact: Vector3 = strike.impact
	var radius: float = {"acid": 1.8, "stomp": 4.2, "pounce": 2.0}[strike.special]
	var multiplier := 1.35 if strike.special == "stomp" else 1.0
	if strike.special == "pounce" and d.position.distance_to(impact) > 3.0: return
	# No target tracking after wind-up, no damage through trees/walls and no friendly hits.
	# Area damage bypasses resolve_strike(), so shelter needs its own guard here or acid
	# and stomps would still kill someone inside a tent.
	for survivor in world.survivors():
		if survivor.is_sheltered(): continue
		if survivor.health > 0 and within_impact(survivor.position, impact, radius) and ai.has_line_of_sight(d.position, survivor.position):
			survivor.health -= d.attack_damage * multiplier
	for b in world.session.buildings:
		if b.hp <= 0: continue
		var point: Vector3 = world.board.point(b.cell)
		if not within_impact(point, impact, radius) or not ai.has_line_of_sight(d.position, point): continue
		var damage: float = d.attack_damage * multiplier
		if b.kind in ["tower", "shelter", "gate"]:
			if world.Regions.at(point) == "mountain": damage /= 1.18
			if world.session.technologies.has("defense"): damage *= 0.8
		world.damage_building(b, damage)
	world.sound.play_at("hit", impact)

func within_impact(point: Vector3, center: Vector3, radius: float) -> bool:
	# Ground warnings describe a horizontal footprint, including on slopes.
	return Vector2(point.x - center.x, point.z - center.z).length_squared() <= radius * radius
