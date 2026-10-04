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
	if kind not in ["tent", "fire", "fossil", "tower", "generator", "shelter", "gate", "lab", "laboratory"] or building.has_node("CampDetail"): return
	var detail := Node3D.new()
	detail.name = "CampDetail"
	building.add_child(detail)
	var key := "lab" if kind == "laboratory" else kind
	attach(detail, "Structure", cached_structure(key))
	# A single cached surface adds readable craftsmanship close to the camp.
	# Far views and low quality keep the existing structural silhouette.
	var joinery := attach(detail, "Joinery", cached_joinery(key))
	joinery.visibility_range_end = 38.0
	joinery.visibility_range_end_margin = 4.0
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
	elif kind == "generator":
		var flywheel := Node3D.new()
		flywheel.name = "Flywheel"
		flywheel.position = Vector3(-.57, .66, .48)
		detail.add_child(flywheel)
		var geometry := begin_mesh()
		tube(geometry, Vector3(-.11, 0, 0), Vector3(.11, 0, 0), .12, IRON)
		for angle in [0.0, PI / 2.0]:
			box(geometry, Vector3(.22, .025, .025), Vector3.ZERO, END_GRAIN, Basis(Vector3.RIGHT, angle))
		attach(flywheel, "Wheel", finish_mesh(geometry))
		var exhaust := Node3D.new()
		exhaust.name = "Exhaust"
		exhaust.position = Vector3(.52, 1.05, -.42)
		detail.add_child(exhaust)
		geometry = begin_mesh()
		tube(geometry, Vector3.ZERO, Vector3(0, .48, 0), .065, IRON)
		tube(geometry, Vector3(0, .48, 0), Vector3(.13, .48, 0), .045, IRON)
		box(geometry, Vector3(.17, .06, .14), Vector3(.10, .52, 0), STONE)
		attach(exhaust, "Pipe", finish_mesh(geometry))
		add_lamp(detail, Vector3(.53, 1.24, .48))
		add_damage_smoke(detail, 1.58)
	elif kind in ["shelter", "gate"]:
		add_power_beacon(detail, Vector3(-.78, 1.18, .02))
		add_power_beacon(detail, Vector3(.78, 1.18, .02))
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
	detail.get_node("Joinery").visible = scenery.world.preferences.values.quality > 0 and (data.kind != "tower" or data.get("refit", "").is_empty())
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
		if detail.has_node("LampLight"):
			var lamp_light: OmniLight3D = detail.get_node("LampLight")
			var weather: Variant = scenery.world.get("weather")
			var storm_flicker: float = 0.82 + 0.18 * sin(clock * 3.7) if weather and weather.kind == 3 else 1.0
			lamp_light.visible = light.visible and status > 0 and scenery.world.preferences.values.quality > 0
			lamp_light.light_energy = (0.0 if status == 0 else (0.72 if status == 1 else 0.34)) * storm_flicker
	if detail.has_node("DamageSmoke"):
		var smoke: CPUParticles3D = detail.get_node("DamageSmoke")
		smoke.emitting = complete and health < .35 and not scenery.world.paused and scenery.world.preferences.values.quality > 0
	if detail.has_node("Ventilator"):
		var fan: Node3D = detail.get_node("Ventilator")
		# Accumulate only while powered so restoring supply never jumps the blades.
		var previous: float = detail.get_meta("mechanism_clock", clock)
		if powered: fan.rotation.y += clampf(clock - previous, 0.0, .1) * 9.0
		detail.set_meta("mechanism_clock", clock)
	if detail.has_node("Flywheel"):
		var wheel: Node3D = detail.get_node("Flywheel")
		var previous: float = detail.get_meta("generator_clock", clock)
		var generator_running: bool = complete and health > 0.0
		if generator_running: wheel.rotation.x += clampf(clock - previous, 0.0, .1) * 7.0
		detail.set_meta("generator_clock", clock)
	if detail.has_node("PowerBeacon"):
		var active: bool = complete and powered and (data.kind != "gate" or not data.get("open", false))
		var moving: bool = data.get("gate_timer", 0.0) > 0.0
		var beacons := detail.find_children("PowerBeacon*", "MeshInstance3D", true, false)
		var beacon_visible: bool = active and scenery.world.preferences.values.quality > 0
		for beacon_node in beacons:
			var beacon: MeshInstance3D = beacon_node
			beacon.visible = beacon_visible
			if beacon.visible:
				var material: StandardMaterial3D = beacon.material_override
				material.emission_energy_multiplier = 1.0 + 0.5 * (0.5 + 0.5 * sin(clock * (8.0 if moving else 3.0)))
		if detail.has_node("PowerBeaconLight"):
			var beacon_light: OmniLight3D = detail.get_node("PowerBeaconLight")
			beacon_light.visible = beacon_visible
			beacon_light.light_energy = .35 if not moving else .55 + .25 * sin(clock * 8.0)
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
		"generator":
			# A service frame and capped exhaust make the imported machine read at a distance.
			for x in [-.72, .72]: beam(geometry, Vector3(x, .08, -.63), Vector3(x, 1.12, -.63), .07, IRON)
			beam(geometry, Vector3(-.72, 1.12, -.63), Vector3(.72, 1.12, -.63), .07, IRON)
			for x in [-.72, .72]: box(geometry, Vector3(.20, .12, .20), Vector3(x, .14, -.63), STONE)
			box(geometry, Vector3(.32, .08, .26), Vector3(.52, 1.58, -.42), IRON)
		"shelter", "gate":
			# Insulators sit on the existing posts and remain below the imported fence silhouette.
			# The gate's center belongs to the moving leaf, so keep fixed accents on its posts.
			var post_positions := [-.78, .78] if kind == "gate" else [-.78, 0.0, .78]
			for x in post_positions:
				box(geometry, Vector3(.12, .16, .12), Vector3(x, 1.13, .02), IRON)
				tube(geometry, Vector3(x, 1.19, -.04), Vector3(x, 1.19, .10), .035, STONE)
	var mesh := finish_mesh(geometry)
	mesh_cache[kind] = mesh
	return mesh

static func cached_joinery(kind: String) -> ArrayMesh:
	var key := kind + "_joinery"
	if mesh_cache.has(key): return mesh_cache[key]
	var geometry := begin_mesh()
	match kind:
		"tent":
			for z in [-.86, .86]:
				for x in [-.82, .82]:
					box(geometry, Vector3(.16, .20, .035), Vector3(x, .53, z), IRON)
					for y in [.48, .58]: rivet(geometry, Vector3(x, y, z), Vector3(0, 0, signf(z)))
					# Roof ties follow the canvas slope instead of floating above it.
					cord(geometry, PackedVector3Array([Vector3(x, .55, z), Vector3(x * .63, 1.00, z), Vector3(x * .28, 1.52, z), Vector3(0, 1.88, z)]), .012, CANVAS)
			for x in [-.78, .78]:
				tube(geometry, Vector3(x, .02, .95), Vector3(x, .22, .89), .025, END_GRAIN)
				cord(geometry, PackedVector3Array([Vector3(x, .18, .92), Vector3(x * .75, .53, .89), Vector3(x * .40, 1.18, .87), Vector3(0, 1.86, .86)]), .012, CANVAS)
		"tower":
			for x in [-.57, .57]:
				for z in [-.58, .58]:
					box(geometry, Vector3(.22, .25, .035), Vector3(x, .43, z), IRON)
					for y in [.36, .50]: rivet(geometry, Vector3(x, y, z), Vector3(0, 0, signf(z)))
			for x in [-.23, .23]: beam(geometry, Vector3(x, .13, .82), Vector3(x, 1.67, .61), .055, WOOD)
			for step in range(7):
				var y := .26 + step * .20
				var z := .82 - (y - .13) * .136
				tube(geometry, Vector3(-.24, y, z), Vector3(.24, y, z), .027, END_GRAIN)
		"fossil":
			for x in [-.65, .65]:
				box(geometry, Vector3(.20, .22, .035), Vector3(x, 1.74, -.225), IRON)
				for dx in [-.055, .055]: rivet(geometry, Vector3(x + dx, 1.74, -.202), Vector3.FORWARD * -1.0)
				for z in [-.56, .02]:
					box(geometry, Vector3(.19, .13, .035), Vector3(x, .37, z), IRON)
					rivet(geometry, Vector3(x, .37, z + .025), Vector3.BACK)
			# Strung soil sieve and individually spaced slats at the pit edge.
			for x in [.35, .78]: box(geometry, Vector3(.04, .035, .48), Vector3(x, .24, .48), WOOD)
			for z in [.25, .71]: box(geometry, Vector3(.47, .035, .04), Vector3(.565, .24, z), END_GRAIN)
			for i in range(6):
				var offset := i * .07
				tube(geometry, Vector3(.36 + offset, .237, .27), Vector3(.36 + offset, .237, .69), .005, IRON)
				tube(geometry, Vector3(.37, .233, .28 + offset), Vector3(.76, .233, .28 + offset), .005, IRON)
		"fire":
			# Split firewood rests beside the hearth with light exposed end grain.
			for i in range(4):
				var x := -.74 + (i % 2) * .13
				var y := .11 + (i / 2) * .11
				tube(geometry, Vector3(x, y, .18), Vector3(x, y, .60), .064, WOOD)
				tube(geometry, Vector3(x, y, .602), Vector3(x, y, .608), .051, END_GRAIN)
			for x in [-.38, .38]:
				for z in [.70, .86]: rivet(geometry, Vector3(x, .342, z), Vector3.UP)
		"lab":
			# Louvres, fasteners and cable saddles add scale to the roof mechanism.
			for i in range(6): box(geometry, Vector3(.54, .025, .035), Vector3(-.49, 2.08, -.55 + i * .09), STONE)
			for x in [-.78, -.20]:
				for z in [-.61, -.03]: rivet(geometry, Vector3(x, 1.90, z), Vector3.UP)
			cord(geometry, PackedVector3Array([Vector3(.77, .28, -.87), Vector3(.77, .80, -.87), Vector3(.72, 1.57, -.87), Vector3(.36, 1.74, -.83)]), .022, IRON)
			for y in [.42, .90, 1.38]: box(geometry, Vector3(.09, .045, .065), Vector3(.76, y, -.87), STONE)
		"generator":
			for x in [-.72, .72]:
				for y in [.24, .96]: rivet(geometry, Vector3(x, y, -.66), Vector3.FORWARD)
			for x in [-.52, .52]: box(geometry, Vector3(.08, .035, .22), Vector3(x, .92, .49), STONE)
		"shelter", "gate":
			var post_positions := [-.78, .78] if kind == "gate" else [-.78, 0.0, .78]
			for x in post_positions:
				for z in [-.06, .10]: rivet(geometry, Vector3(x, 1.10, z), Vector3.UP)
	var mesh := finish_mesh(geometry)
	mesh_cache[key] = mesh
	return mesh

static func cord(geometry: SurfaceTool, points: PackedVector3Array, radius: float, color: Color) -> void:
	for i in range(points.size() - 1): tube(geometry, points[i], points[i + 1], radius, color)

static func rivet(geometry: SurfaceTool, at: Vector3, normal: Vector3) -> void:
	tube(geometry, at, at + normal * .018, .023, STONE)

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
	var light := OmniLight3D.new()
	light.name = "LampLight"
	light.position = at + Vector3.UP * 0.05
	light.light_color = Color("f3bd72")
	light.light_energy = 0.72
	light.omni_range = 4.8
	light.shadow_enabled = false
	parent.add_child(light)

static func add_power_beacon(parent: Node3D, at: Vector3) -> void:
	var beacon := MeshInstance3D.new()
	beacon.name = "PowerBeacon" if not parent.has_node("PowerBeacon") else "PowerBeacon_%d" % parent.get_child_count()
	var mesh := SphereMesh.new()
	mesh.radius = .065
	mesh.height = .13
	mesh.radial_segments = 8
	mesh.rings = 4
	beacon.mesh = mesh
	beacon.position = at
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("7ac9ed")
	material.emission_enabled = true
	material.emission = Color("62c9ff")
	material.emission_energy_multiplier = 1.4
	beacon.material_override = material
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(beacon)
	if not parent.has_node("PowerBeaconLight"):
		var light := OmniLight3D.new()
		light.name = "PowerBeaconLight"
		light.position = at
		light.light_color = Color("6acbff")
		light.omni_range = 1.8
		light.light_energy = .35
		light.shadow_enabled = false
		parent.add_child(light)

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
	# Small real chamfers catch the key light; large flat faces remain planar.
	# Keep very thin strips simple to avoid spending triangles on distant noise.
	var shortest := minf(size.x, minf(size.y, size.z))
	if shortest >= .065:
		chamfered_box(geometry, size, at, color, basis, minf(.018, shortest * .12))
		return
	var mesh := BoxMesh.new()
	mesh.size = size
	append_mesh(geometry, mesh, Transform3D(basis, at), color)

static func chamfered_box(geometry: SurfaceTool, size: Vector3, at: Vector3, color: Color, basis: Basis, bevel: float) -> void:
	var half := size * .5
	var inset := half - Vector3.ONE * bevel
	var transform := Transform3D(basis, at)
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for side in [-1.0, 1.0]:
			var points := PackedVector3Array()
			for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = half[axis] * side
				point[u] = inset[u] * uv.x
				point[v] = inset[v] * uv.y
				points.append(point)
			var normal := Vector3.ZERO
			normal[axis] = side
			facet(geometry, points, normal, transform, color)
	# Twelve bevel strips join the inset faces, then eight triangular corners.
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var a := Vector3.ZERO
				a[axis] = -inset[axis]
				a[u] = half[u] * su
				a[v] = inset[v] * sv
				var b := a
				b[axis] = inset[axis]
				var c := b
				c[u] = inset[u] * su
				c[v] = half[v] * sv
				var d := c
				d[axis] = -inset[axis]
				var normal := Vector3.ZERO
				normal[u] = su
				normal[v] = sv
				facet(geometry, PackedVector3Array([a, b, c, d]), normal.normalized(), transform, color.lightened(.025))
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				var sign_vector := Vector3(x, y, z)
				var a := Vector3(half.x, inset.y, inset.z) * sign_vector
				var b := Vector3(inset.x, half.y, inset.z) * sign_vector
				var c := Vector3(inset.x, inset.y, half.z) * sign_vector
				facet(geometry, PackedVector3Array([a, b, c]), sign_vector.normalized(), transform, color.lightened(.025))

static func facet(geometry: SurfaceTool, points: PackedVector3Array, normal: Vector3, transform: Transform3D, color: Color) -> void:
	# Godot's front faces use clockwise winding. Keep outward normals explicit.
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) > 0: points.reverse()
	for i in range(1, points.size() - 1):
		for point in [points[0], points[i], points[i + 1]]:
			geometry.set_color(color)
			geometry.set_normal(transform.basis * normal)
			geometry.add_vertex(transform * point)

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
