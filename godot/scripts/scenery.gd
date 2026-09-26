extends RefCounted
const TowerVisuals = preload("res://scripts/tower_visuals.gd")
## Render-only decoration. Never consumes gameplay RNG or changes navigation.
const FlameShader = preload("res://shaders/flame.gdshader")
const GroundShader = preload("res://shaders/ground.gdshader")
const FoliageShader = preload("res://shaders/foliage.gdshader")
const FoliageFog = preload("res://shaders/foliage_fog.gdshader")
const WaterShader = preload("res://shaders/water.gdshader")
const ForestRenderer = preload("res://scripts/forest_renderer.gd")
const FernScene = preload("res://assets/models/fern.glb")
const Visual = preload("res://scripts/pawn_visual.gd")
const ObstructionFade = preload("res://scripts/obstruction_fade.gd")
const TreeVariation = preload("res://scripts/tree_variation.gd")
const GroundPalette = preload("res://scripts/ground_palette.gd")
var ground_palette: RefCounted
var variation: RefCounted
var ground: ShaderMaterial
var water: ShaderMaterial
var wind_materials: Array[ShaderMaterial] = []
var obstructions: RefCounted
var world: Node
var foliage_cache := {}
var clock := 0.0
var leaf_fog: ShaderMaterial
var forest: RefCounted

func _init(owner_world: Node) -> void:
	world = owner_world
	obstructions = ObstructionFade.new(world)
	leaf_fog = make_foliage_fog(0.055)
	leaf_fog.set_shader_parameter("canopy_cutout",true)
	if not world.has_node("Island"): return
	var island: Node = world.get_node("Island")
	if island.has_node("ReferenceGround"):
		ground = ShaderMaterial.new()
		ground.shader = GroundShader
		ground.set_shader_parameter("detail_map",load("res://assets/materials/ground_detail.png"))
		ground_palette = GroundPalette.new(world)
		ground.set_shader_parameter("usage_map",ground_palette.texture)
		ground.set_shader_parameter("soil_map",load("res://assets/materials/camp_soil.png"))
		ground.set_shader_parameter("forest_map",load("res://assets/materials/forest_floor.png"))
		for surface in ["turf", "soil", "litter", "rock"]:
			ground.set_shader_parameter(surface + "_surface", load("res://assets/materials/terrain/%s.png" % surface))
		var mask := Image.create(128,128,false,Image.FORMAT_R8)
		for y in range(128):
			for x in range(128): mask.set_pixel(x,y,Color(1 if world.board.layout.build[y*128+x] else 0,0,0))
		ground.set_shader_parameter("buildable_map",ImageTexture.create_from_image(mask))
		island.get_node("ReferenceGround").material_override = ground
	if island.has_node("Water"):
		water = ShaderMaterial.new()
		water.shader = WaterShader
		island.get_node("Water").material_override = water
	variation = TreeVariation.new(world)
	style_leaves(island)
	forest = ForestRenderer.new(world, "--unbatched-forest" not in OS.get_cmdline_user_args())
	add_ground_cover(island)
	for node in island.find_children("*", "Node3D", true, false):
		if node.scene_file_path.contains("rock.tscn"): obstructions.register(node)

func update_view(dt: float = 0.0) -> void:
	obstructions.update(dt)
	if ground_palette: ground_palette.update()
	if world.weather:
		for mat in wind_materials:
			mat.set_shader_parameter("weather_clock",world.weather.clock)
			mat.set_shader_parameter("wind_power",world.weather.wind)
			mat.set_shader_parameter("wind_direction",world.weather.direction)
		if ground:
			ground.set_shader_parameter("wetness",world.weather.wetness)
			ground.set_shader_parameter("build_preview",not world.build_mode.is_empty() and not world.paused)
			ground.set_shader_parameter("builder_position",world.hero.position)
		if water:
			water.set_shader_parameter("weather_clock",world.weather.clock)
			water.set_shader_parameter("wind_power",world.weather.wind)
	if forest: forest.update_lod(world.camera_rig.focus,world.camera.size)
	var enabled := 1.0 if world.hero.health > 0 and "--no-canopy-cutout" not in OS.get_cmdline_user_args() else 0.0
	for mat in foliage_cache.values() + [leaf_fog]:
		mat.set_shader_parameter("actor_focus",world.hero.global_position + Vector3.UP * 1.15)
		mat.set_shader_parameter("camera_axis",world.camera.global_basis.z.normalized())
		mat.set_shader_parameter("camera_world_position",world.camera.global_position)
		mat.set_shader_parameter("cutout_enabled",enabled)

func make_foliage_fog(strength: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FoliageFog
	mat.set_shader_parameter("visibility_map",world.vision.texture)
	mat.set_shader_parameter("strength",strength)
	wind_materials.append(mat)
	return mat

func style_leaves(node: Node) -> void:
	if node is MeshInstance3D and (str(node.name).begins_with("Crown") or str(node.name) in ["Left", "Top", "Foliage", "Lower", "Upper"]):
		var original: Material = node.get_active_material(0)
		if original is StandardMaterial3D:
			var color: Color = original.albedo_color
			var key := color.to_html() + ("_vertex" if original.vertex_color_use_as_albedo else "")
			if not foliage_cache.has(key):
				var mat := ShaderMaterial.new()
				mat.shader = FoliageShader
				mat.set_shader_parameter("strength", 0.055)
				mat.set_shader_parameter("canopy_cutout",true)
				mat.set_shader_parameter("leaf_detail",true)
				mat.set_shader_parameter("tint", color.lerp(Color("405936"), 0.4))
				mat.set_shader_parameter("vertex_color", original.vertex_color_use_as_albedo)
				foliage_cache[key] = mat
				wind_materials.append(mat)
			node.material_override = foliage_cache[key]
			node.material_overlay = leaf_fog
	for child in node.get_children(): style_leaves(child)

func add_ground_cover(island: Node) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 6506502
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(7):
		var angle := blade * 2.399
		var side := Vector3(cos(angle), 0, sin(angle))
		var bend := Vector3(sin(angle), 0, cos(angle))
		var base := bend * 0.07
		var height := 0.19 + (blade % 4) * 0.046
		for segment in range(3):
			var low := segment / 3.0
			var high := (segment + 1) / 3.0
			var a := base + Vector3.UP * height * low + bend * low * low * 0.18
			var b := base + Vector3.UP * height * high + bend * high * high * 0.18
			var wa := side * 0.035 * (1.0 - low)
			var wb := side * 0.035 * (1.0 - high)
			for v in [a-wa,a+wa,b+wb,a-wa,b+wb,b-wb]:
				surface.set_color(Color("3e5137").lerp(Color("78845a"),clampf(v.y/height,0,1)))
				surface.add_vertex(v)
	surface.generate_normals()
	var mesh := surface.commit()
	var mat := ShaderMaterial.new()
	mat.shader = FoliageShader
	mat.set_shader_parameter("vertex_color", true)
	mat.set_shader_parameter("strength", 0.12)
	wind_materials.append(mat)
	mesh.surface_set_material(0, mat)
	var chunks := {}
	for i in range(24000):
		var p := Vector3(random.randf_range(-126,126), 0, random.randf_range(-126,126))
		# Broad uneven patches, with open lanes between them instead of uniform dots.
		var patch := sin(p.x*.39+sin(p.z*.17)*1.8)*cos(p.z*.31)
		if patch < -.15: continue
		var cell: Vector2i = world.board.cell_at(p)
		if not world.board.is_open(cell): continue
		p.y = world.board.layout.height_at(p.x, p.z)
		var index := cell.y * 129 + cell.x
		if world.board.layout.water[index] != null and float(world.board.layout.water[index]) > p.y - 0.08: continue
		if world.Regions.at(p) == "ice": continue
		# Leave the opening camp legible; cover grows mostly outside its center.
		if p.distance_to(world.hero.position) < 4.5: continue
		var chunk := Vector2i(floori(p.x/24), floori(p.z/24))
		if not chunks.has(chunk): chunks[chunk] = []
		var size := random.randf_range(0.65,1.35)
		chunks[chunk].append(Transform3D(Basis(Vector3.UP, random.randf()*TAU).scaled(Vector3.ONE*size),p))
	var root := Node3D.new()
	root.name = "GroundCover"
	island.add_child(root)
	var grass_fog := make_foliage_fog(0.12)
	for key in chunks:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = chunks[key].size()
		var center := Vector3((key.x+0.5)*24,0,(key.y+0.5)*24)
		for i in range(mm.instance_count):
			var at: Transform3D = chunks[key][i]
			at.origin -= center
			mm.set_instance_transform(i,at)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = mm
		instance.position = center
		instance.material_overlay = grass_fog
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = 115
		instance.visibility_range_end_margin = 12
		root.add_child(instance)
	add_ferns(root)

func add_ferns(parent: Node3D) -> void:
	var source: Node3D = FernScene.instantiate()
	var random := RandomNumberGenerator.new()
	random.seed = 650908
	var chunks := {}
	for i in range(2300):
		var p := Vector3(random.randf_range(-126,126),0,random.randf_range(-126,126))
		var cell: Vector2i = world.board.cell_at(p)
		if not world.board.is_open(cell) or world.Regions.at(p) == "ice": continue
		if p.distance_to(world.hero.position) < 4.5: continue
		p.y = world.board.layout.height_at(p.x,p.z)
		var index := cell.y*129+cell.x
		if world.board.layout.water[index] != null and float(world.board.layout.water[index]) > p.y-0.08: continue
		var chunk := Vector2i(floori(p.x/16),floori(p.z/16))
		if not chunks.has(chunk): chunks[chunk] = []
		var size := random.randf_range(0.55,1.05)
		chunks[chunk].append(Transform3D(Basis(Vector3.UP,random.randf()*TAU).scaled(Vector3.ONE*size),p))
	var fog := make_foliage_fog(0.045)
	var fern_material := ShaderMaterial.new()
	fern_material.shader = FoliageShader
	fern_material.set_shader_parameter("vertex_color",true)
	fern_material.set_shader_parameter("strength",0.045)
	wind_materials.append(fern_material)
	for mesh in source.find_children("*","MeshInstance3D",true,false):
		for key in chunks:
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = mesh.mesh
			multi.instance_count = chunks[key].size()
			var center := Vector3((key.x+0.5)*16,0,(key.y+0.5)*16)
			for i in range(multi.instance_count):
				var at: Transform3D = chunks[key][i]
				at.origin -= center
				multi.set_instance_transform(i,at)
			var instance := MultiMeshInstance3D.new()
			instance.name = "Ferns"
			instance.multimesh = multi
			instance.position = center
			instance.visibility_range_end = 125
			instance.visibility_range_end_margin = 10
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mesh.name == "Foliage":
				instance.material_override = fern_material
				instance.material_overlay = fog
			else: instance.material_overlay = world.vision.overlay
			parent.add_child(instance)
	source.free()

func prepare_building(node: Node3D, kind: String) -> void:
	polish_building_materials(node, kind)
	add_building_contact_shadow(node, kind)
	var family := "lab" if kind == "laboratory" else kind
	if family in ["tent", "tower", "generator", "lab"]:
		var dressing: Node3D = load("res://assets/models/%s_dressing.glb" % family).instantiate()
		dressing.name = "CampDressing"
		node.add_child(dressing)
		world.vision.shade(dressing)
	var scaffold := Node3D.new()
	scaffold.name = "Scaffold"
	node.add_child(scaffold)
	for x in [-0.85,0.85]:
		for z in [-0.85,0.85]:
			Visual.box(scaffold,Vector3(0.08,1.8,0.08),Vector3(x,0.9,z),Color("7c6444"))
	for z in [-0.85,0.85]:
		Visual.box(scaffold,Vector3(1.85,0.10,0.10),Vector3(0,1.5,z),Color("a1895c"))
	obstructions.register(node)
	if kind != "fire": return
	var flame_mat := ShaderMaterial.new()
	flame_mat.shader = FlameShader
	for title in ["Flame","FlameCore"]: node.get_node("Model/"+title).material_override = flame_mat
	var sparks := CPUParticles3D.new()
	sparks.name = "Embers"
	sparks.position.y = 0.75
	sparks.amount = 12
	sparks.lifetime = 1.6
	sparks.direction = Vector3.UP
	sparks.spread = 18
	sparks.gravity = Vector3(0.12,0.4,0)
	sparks.initial_velocity_min = 0.35
	sparks.initial_velocity_max = 0.9
	sparks.scale_amount_min = 0.025
	sparks.scale_amount_max = 0.055
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1
	mesh.radial_segments = 4
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("edb76b")
	mesh.material = mat
	sparks.mesh = mesh
	node.add_child(sparks)
	var smoke := CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position.y = 0.8
	smoke.amount = 9
	smoke.lifetime = 3.2
	smoke.direction = Vector3.UP
	smoke.spread = 12
	smoke.gravity = Vector3(0.12,0.05,0.05)
	smoke.initial_velocity_min = .35
	smoke.initial_velocity_max = .65
	smoke.scale_amount_min = .35
	smoke.scale_amount_max = .65
	var radial := GradientTexture2D.new()
	radial.width = 64
	radial.height = 64
	radial.fill = GradientTexture2D.FILL_RADIAL
	radial.fill_from = Vector2(.5,.5)
	radial.fill_to = Vector2(1,.5)
	radial.gradient = Gradient.new()
	radial.gradient.colors = PackedColorArray([Color(1,1,1,0.16),Color(1,1,1,0)])
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.albedo_color = Color("7d8278")
	smoke_mat.albedo_texture = radial
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mat.no_depth_test = false
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = smoke_mat
	smoke.mesh = quad
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0,.2,1])
	fade.colors = PackedColorArray([Color(1,1,1,0),Color.WHITE,Color(1,1,1,0)])
	smoke.color_ramp = fade
	node.add_child(smoke)

func polish_building_materials(node: Node3D, kind: String) -> void:
	# Imported building materials vary by asset. Duplicate the surface material
	# at runtime so every structure shares the same grounded, slightly worn look
	# without changing the source GLB files.
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override != null: continue
		var source: Material = mesh.get_active_material(0)
		if not source is StandardMaterial3D: continue
		var mat: StandardMaterial3D = source.duplicate()
		# Mixed atlas surfaces include timber, cloth and metal on the same mesh.
		# Global metallic/toon overrides made wood and canvas look like plastic.
		mat.roughness = 1.0
		mat.metallic = 0.0
		mat.metallic_specular = 0.22
		mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		mesh.material_override = mat

func add_building_contact_shadow(node: Node3D, kind: String) -> void:
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow"
	shadow.rotation_degrees.x = -90.0
	shadow.position.y = 0.026
	var quad := QuadMesh.new()
	quad.size = Vector2(2.65, 2.05) if kind not in ["tower", "gate"] else Vector2(2.2, 1.55)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	gradient.colors = PackedColorArray([Color(0.04,0.055,0.04,0.30), Color(0.04,0.055,0.04,0.12), Color(0.04,0.055,0.04,0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 96
	texture.height = 96
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	quad.material = material
	shadow.mesh = quad
	node.add_child(shadow)

func update_building(node: Node3D, data: Dictionary) -> void:
	var complete: bool = data.remaining <= 0
	if data.kind == "tower": TowerVisuals.update(self, node, data)
	if node.has_node("CampDressing"):
		node.get_node("CampDressing").visible = complete and world.preferences.values.quality > 0 and not (data.kind == "tower" and not data.get("refit", "").is_empty())
	node.scale = Vector3.ONE
	node.get_node("Scaffold").visible = not complete
	var progress: float = 1.0 - data.remaining / world.Catalog.BUILDINGS[data.kind].time
	var model: Node3D = node.get_node("Model")
	# Assemble pieces bottom-up instead of stretching the whole building and its light.
	for part in model.get_children():
		if part is Node3D:
			var height: float = part.position.y
			if part is MeshInstance3D: height += part.mesh.get_aabb().get_center().y
			part.visible = complete or data.get("upgrading", false) or progress >= clampf(height / 2.2,0.05,0.90)
	if data.get("refit", "") == "brace":
		if not node.has_node("Refit"):
			var fittings := Node3D.new()
			fittings.name = "Refit"
			node.add_child(fittings)
			for x in [-0.82, 0.82]:
				Visual.box(fittings, Vector3(0.20, 1.8, 0.25), Vector3(x, 0.9, 0), Color("60766c"))
				for y in [0.35, 1.25]: Visual.box(fittings, Vector3(0.30, 0.10, 0.30), Vector3(x, y, 0), Color("b4aa83"))
			world.vision.shade(fittings)
		node.get_node("Refit").visible = complete
	if data.kind == "fire":
		node.get_node("FireLight").visible = complete
		node.get_node("FireLight").light_energy = (0.85 if world.night else 0.28) + sin(clock*8)*0.025 + sin(clock*13)*0.018
		node.get_node("Embers").emitting = complete and not world.paused
		node.get_node("Smoke").emitting = complete and not world.paused
		for name in ["Flame","FlameCore"]:
			var flame: Node3D = model.get_node(name)
			flame.visible = complete
			flame.scale = Vector3(1+sin(clock*7)*0.09,1+sin(clock*11)*0.15,1+cos(clock*9)*0.08)
