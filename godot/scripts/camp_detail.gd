extends RefCounted
## Shared camp construction language: substantial timber, iron joints and working mechanisms.
## All geometry is visual-only and fits the existing two metre construction cells.
const Catalog = preload("res://scripts/catalog.gd")
const WOOD := Color("705334")
const END_GRAIN := Color("ac8958")
const IRON := Color("344942")
const STONE := Color("62685b")
const CANVAS := Color("a4925e")
static var mesh_cache := {}
static var surface_material: StandardMaterial3D
static var smoke_mesh: QuadMesh

static func prepare(scenery: RefCounted, building: Node3D, kind: String) -> void:
	if kind not in ["tent", "fire", "fossil", "tower", "lab", "laboratory"] or building.has_node("CampDetail"): return
	var detail := Node3D.new()
	detail.name = "CampDetail"
	building.add_child(detail)
	var key := "lab" if kind == "laboratory" else kind
	attach(detail, "Structure", cached_structure(key))
	if kind == "fossil":
		var drum := Node3D.new()
		drum.name = "Winch"
		drum.position = Vector3(0, 1.39, -.33)
		detail.add_child(drum)
		var geometry := begin_mesh()
		tube(geometry, Vector3(-.35, 0, 0), Vector3(.35, 0, 0), .095, WOOD)
		for x in [-.33, .33]: tube(geometry, Vector3(x - .025, 0, 0), Vector3(x + .025, 0, 0), .17, IRON)
		beam(geometry, Vector3(.43, 0, 0), Vector3(.43, .24, 0), .07, IRON)
		tube(geometry, Vector3(.43, .24, 0), Vector3(.64, .24, 0), .045, END_GRAIN)
		attach(drum, "Drum", finish_mesh(geometry))
		var bucket := Node3D.new()
		bucket.name = "Bucket"
		bucket.position = Vector3(0, .66, -.33)
		detail.add_child(bucket)
		geometry = begin_mesh()
		tube(geometry, Vector3(0, -.17, 0), Vector3(0, .15, 0), .20, WOOD)
		for y in [-.12, .13]: tube(geometry, Vector3(0, y - .025, 0), Vector3(0, y + .025, 0), .213, IRON)
		for x in [-.18, .18]: beam(geometry, Vector3(x, .15, 0), Vector3(0, .37, 0), .025, IRON)
		attach(bucket, "Basket", finish_mesh(geometry))
		geometry = begin_mesh()
		tube(geometry, Vector3.ZERO, Vector3.UP, .018, CANVAS)
		attach(detail, "Rope", finish_mesh(geometry))
	elif kind == "fire":
		var pot := Node3D.new()
		pot.name = "CookingPot"
		pot.position = Vector3(0, .78, -.08)
		detail.add_child(pot)
		var geometry := begin_mesh()
		tube(geometry, Vector3(0, -.19, 0), Vector3(0, .1, 0), .22, IRON)
		tube(geometry, Vector3(0, .1, 0), Vector3(0, .13, 0), .24, STONE)
		for x in [-.2, .2]: beam(geometry, Vector3(x, .10, 0), Vector3(0, .38, 0), .025, IRON)
		attach(pot, "IronPot", finish_mesh(geometry))
	elif key == "lab":
		var fan := Node3D.new()
		fan.name = "Ventilator"
		fan.position = Vector3(-.49, 1.91, -.32)
		detail.add_child(fan)
		var geometry := begin_mesh()
		tube(geometry, Vector3(0, -.06, 0), Vector3(0, .07, 0), .08, IRON)
		for angle in [0.0, PI / 2.0]:
			box(geometry, Vector3(.59, .035, .11), Vector3.ZERO, STONE, Basis(Vector3.UP, angle))
		attach(fan, "Blades", finish_mesh(geometry))
	if kind in ["tent", "tower", "lab", "laboratory"]:
		add_lamp(detail, Vector3(.70, 1.33 if kind == "tent" else (1.45 if kind == "tower" else 1.57), .65))
		add_damage_smoke(detail, 1.55 if kind != "tower" else 2.0)
	scenery.world.vision.shade(detail)

static func update(scenery: RefCounted, building: Node3D, data: Dictionary) -> void:
	var detail: Node3D = building.get_node_or_null("CampDetail")
	if detail == null: return
	var complete: bool = data.remaining <= 0
	detail.visible = complete or data.get("upgrading", false)
	var clock: float = scenery.clock
	var health: float = clampf(float(data.hp) / Catalog.max_health(data), 0.0, 1.0)
	var powered: bool = complete and scenery.world.session.supply() >= scenery.world.session.demand()
	if data.kind == "tower":
		# Upgraded towers already have their own heavy structural supports.
		detail.get_node("Structure").visible = data.get("refit", "").is_empty()
	if detail.has_node("Lamp"):
		var light: MeshInstance3D = detail.get_node("Lamp")
		var status: int = 2 if health < .35 else (1 if data.kind == "tent" or powered else 0)
		if int(detail.get_meta("lamp_state", -1)) != status:
			var material: StandardMaterial3D = light.material_override
			material.albedo_color = [Color("333e36"), Color("edb764"), Color("e57543")][status]
			material.emission = material.albedo_color
			material.emission_energy_multiplier = 0.75 if status > 0 else 0.0
			detail.set_meta("lamp_state", status)
		light.visible = complete and (status != 2 or sin(clock * 5.0) > -.25)
	if detail.has_node("DamageSmoke"):
		var smoke: CPUParticles3D = detail.get_node("DamageSmoke")
		smoke.emitting = complete and health < .35 and not scenery.world.paused and scenery.world.preferences.values.quality > 0
	if detail.has_node("Ventilator"):
		var fan: Node3D = detail.get_node("Ventilator")
		# Accumulate only while powered so restoring supply never jumps the blades.
		var previous: float = detail.get_meta("mechanism_clock", clock)
		if powered: fan.rotation.y += clampf(clock - previous, 0.0, .1) * 9.0
		detail.set_meta("mechanism_clock", clock)
	if detail.has_node("CookingPot"):
		detail.get_node("CookingPot").rotation.z = sin(clock * 1.7) * .035
	if detail.has_node("Winch"):
		var working := false
		if complete:
			for survivor in scenery.world.survivors():
				if survivor.work_state == "mine" and survivor.work_timeout > 0 and survivor.global_position.distance_squared_to(building.global_position) < 10.0:
					working = true
					break
		var previous: float = detail.get_meta("mechanism_clock", clock)
		var phase: float = detail.get_meta("winch_phase", 0.0)
		if working: phase += clampf(clock - previous, 0.0, .1) * 2.0
		detail.set_meta("winch_phase", phase)
		detail.set_meta("mechanism_clock", clock)
		detail.get_node("Winch").rotation.x = phase
		var bucket: Node3D = detail.get_node("Bucket")
		bucket.position.y = .66 + sin(phase) * .15
		var rope: Node3D = detail.get_node("Rope")
		rope.position = bucket.position + Vector3.UP * .37
		rope.scale.y = 1.39 - rope.position.y

static func cached_structure(kind: String) -> ArrayMesh:
	if mesh_cache.has(kind): return mesh_cache[kind]
	var geometry := begin_mesh()
	match kind:
		"tent":
			# Thick end frames and ridge make the silhouette legible from the RTS camera.
			for z in [-.82, .82]:
				for x in [-.87, .87]:
					beam(geometry, Vector3(x, .14, z), Vector3(x, .54, z), .095, WOOD)
					beam(geometry, Vector3(x, .54, z), Vector3(0, 1.87, z), .065, END_GRAIN)
					box(geometry, Vector3(.15, .14, .15), Vector3(x, .24, z), IRON)
			beam(geometry, Vector3(0, 1.87, -.91), Vector3(0, 1.87, .94), .085, WOOD)
			for x in [-.91, .91]: box(geometry, Vector3(.13, .20, 1.87), Vector3(x, .13, 0), WOOD)
			for z in [.85, .95]: box(geometry, Vector3(.60, .085, .085), Vector3(0, .10, z), END_GRAIN)
			beam(geometry, Vector3(.70, .30, .65), Vector3(.70, 1.58, .65), .055, IRON)
		"fire":
			for x in [-.67, .67]:
				beam(geometry, Vector3(x, .1, -.31), Vector3(x * .38, 1.44, -.08), .075, WOOD)
			beam(geometry, Vector3(-.40, 1.40, -.08), Vector3(.40, 1.40, -.08), .075, END_GRAIN)
			tube(geometry, Vector3(0, 1.39, -.08), Vector3(0, 1.12, -.08), .018, IRON)
			# A low split-log bench gives the hearth an inhabited human scale.
			box(geometry, Vector3(1.12, .10, .25), Vector3(0, .29, .78), WOOD)
			for x in [-.38, .38]: box(geometry, Vector3(.13, .24, .20), Vector3(x, .15, .78), STONE)
		"fossil":
			for x in [-.77, .77]:
				for z in [-.55, .02]:
					beam(geometry, Vector3(x, .05, z), Vector3(x * .88, 1.75, -.33), .135, WOOD)
				box(geometry, Vector3(.22, .19, .64), Vector3(x, .08, -.28), STONE)
				beam(geometry, Vector3(x, .20, -.69), Vector3(x * .88, 1.15, -.33), .08, END_GRAIN)
			beam(geometry, Vector3(-.80, 1.76, -.33), Vector3(.80, 1.76, -.33), .17, WOOD)
			for x in [-.61, .61]: box(geometry, Vector3(.12, .23, .23), Vector3(x, 1.75, -.33), IRON)
			# Excavation retaining beams frame the exposed ribs, without hiding the fossil.
			for x in [-.9, .9]: box(geometry, Vector3(.10, .18, 1.6), Vector3(x, .10, 0), END_GRAIN)
			box(geometry, Vector3(1.7, .18, .10), Vector3(0, .10, -.8), WOOD)
		"tower":
			for x in [-.58, .58]:
				for z in [-.58, .58]:
					beam(geometry, Vector3(x, .17, z), Vector3(x * .85, 1.74, z * .85), .13, WOOD)
					box(geometry, Vector3(.21, .24, .21), Vector3(x, .31, z), IRON)
				beam(geometry, Vector3(x, .35, -.55), Vector3(x * .85, 1.47, .47), .09, END_GRAIN)
				beam(geometry, Vector3(x, .35, .55), Vector3(x * .85, 1.47, -.47), .09, END_GRAIN)
			box(geometry, Vector3(1.62, .15, .14), Vector3(0, 1.71, .69), WOOD)
			box(geometry, Vector3(1.62, .15, .14), Vector3(0, 1.71, -.69), WOOD)
			beam(geometry, Vector3(.52, 1.5, .50), Vector3(.70, 1.61, .65), .055, IRON)
		"lab":
			# Roof ventilation and shaded window hoods are functional, large shapes.
			box(geometry, Vector3(.72, .12, .72), Vector3(-.49, 1.83, -.32), IRON)
			for x in [-.78, -.20]:
				beam(geometry, Vector3(x, 1.86, -.61), Vector3(x, 2.05, -.61), .035, IRON)
				beam(geometry, Vector3(x, 1.86, -.03), Vector3(x, 2.05, -.03), .035, IRON)
			for x in [-.83, -.15]: box(geometry, Vector3(.045, .045, .73), Vector3(x, 2.08, -.32), IRON)
			for z in [-.66, -.32, .02]: box(geometry, Vector3(.73, .045, .035), Vector3(-.49, 2.08, z), IRON)
			for x in [-.57, .57]: box(geometry, Vector3(.49, .10, .28), Vector3(x, 1.51, .85), WOOD)
			for x in [-.82, .82]: box(geometry, Vector3(.15, 1.48, .16), Vector3(x, 1.01, -.78), WOOD)
	var mesh := finish_mesh(geometry)
	mesh_cache[kind] = mesh
	return mesh

static func add_lamp(parent: Node3D, at: Vector3) -> void:
	var geometry := begin_mesh()
	for y in [-.14, .14]: box(geometry, Vector3(.23, .055, .23), at + Vector3.UP * y, IRON)
	for x in [-.095, .095]:
		for z in [-.095, .095]: box(geometry, Vector3(.025, .27, .025), at + Vector3(x, 0, z), IRON)
	attach(parent, "LampFrame", finish_mesh(geometry))
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.16, .22, .16)
	lamp.mesh = mesh
	lamp.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("edb764")
	# Keep this small status surface independent of obstruction material conversion.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = .75
	material.roughness = .75
	lamp.material_override = material
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lamp)

static func add_damage_smoke(parent: Node3D, height: float) -> void:
	if smoke_mesh == null:
		var gradient := GradientTexture2D.new()
		gradient.width = 32
		gradient.height = 32
		gradient.fill = GradientTexture2D.FILL_RADIAL
		gradient.fill_from = Vector2(.5, .5)
		gradient.fill_to = Vector2(1, .5)
		gradient.gradient = Gradient.new()
		gradient.gradient.colors = PackedColorArray([Color(1, 1, 1, .4), Color(1, 1, 1, 0)])
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("56544c")
		material.albedo_texture = gradient
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke_mesh = QuadMesh.new()
		smoke_mesh.size = Vector2.ONE
		smoke_mesh.material = material
	var smoke := CPUParticles3D.new()
	smoke.name = "DamageSmoke"
	smoke.position = Vector3(.35, height, -.2)
	smoke.mesh = smoke_mesh
	smoke.amount = 6
	smoke.lifetime = 2.2
	smoke.direction = Vector3.UP
	smoke.spread = 16
	smoke.gravity = Vector3(.13, .03, .02)
	smoke.initial_velocity_min = .3
	smoke.initial_velocity_max = .5
	smoke.scale_amount_min = .3
	smoke.scale_amount_max = .7
	smoke.emitting = false
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0, .2, 1])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0)])
	smoke.color_ramp = fade
	parent.add_child(smoke)

static func begin_mesh() -> SurfaceTool:
	var geometry := SurfaceTool.new()
	geometry.begin(Mesh.PRIMITIVE_TRIANGLES)
	return geometry

static func finish_mesh(geometry: SurfaceTool) -> ArrayMesh:
	if surface_material == null:
		surface_material = StandardMaterial3D.new()
		surface_material.vertex_color_use_as_albedo = true
		surface_material.roughness = .96
		surface_material.metallic_specular = .18
	geometry.set_material(surface_material)
	geometry.index()
	return geometry.commit()

static func attach(parent: Node3D, title: String, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	parent.add_child(node)
	return node

static func box(geometry: SurfaceTool, size: Vector3, at: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	append_mesh(geometry, mesh, Transform3D(basis, at), color)

static func beam(geometry: SurfaceTool, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	box(geometry, Vector3(width, a.distance_to(b), width), (a + b) * .5, color, Basis(Quaternion(Vector3.UP, (b - a).normalized())))

static func tube(geometry: SurfaceTool, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.height = a.distance_to(b)
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.radial_segments = 10
	mesh.rings = 1
	append_mesh(geometry, mesh, Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) * .5), color)

static func append_mesh(geometry: SurfaceTool, mesh: PrimitiveMesh, transform: Transform3D, color: Color) -> void:
	var arrays: Array = mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		geometry.set_color(color)
		geometry.set_normal(transform.basis * normals[index])
		geometry.add_vertex(transform * vertices[index])
