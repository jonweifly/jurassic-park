extends RefCounted
const TowerVisuals = preload("res://scripts/tower_visuals.gd")
const CampDetail = preload("res://scripts/camp_detail.gd")
const TerrainRelief = preload("res://scripts/terrain_relief.gd")
const TerrainSurface = preload("res://scripts/terrain_surface.gd")
## Render-only decoration. Never consumes gameplay RNG or changes navigation.
const FlameShader = preload("res://shaders/flame.gdshader")
const GroundShader = preload("res://shaders/ground.gdshader")
const FoliageShader = preload("res://shaders/foliage.gdshader")
const FoliageFog = preload("res://shaders/foliage_fog.gdshader")
const GroundMarkShader = preload("res://shaders/ground_mark.gdshader")
const WaterShader = preload("res://shaders/water.gdshader")
const WaterSurface = preload("res://scripts/water_surface.gd")
const ForestRenderer = preload("res://scripts/forest_renderer.gd")
const FernScene = preload("res://assets/models/fern.glb")
const CinematicFernScene = preload("res://assets/cinematic/gameplay/fern.glb")
const Visual = preload("res://scripts/pawn_visual.gd")
const ObstructionFade = preload("res://scripts/obstruction_fade.gd")
const TreeVariation = preload("res://scripts/tree_variation.gd")
const GroundPalette = preload("res://scripts/ground_palette.gd")
var ground_palette: RefCounted
var variation: RefCounted
var ground: ShaderMaterial
var buildable_image: Image
var buildable_texture: ImageTexture
var buildable_dirty := false
var water: ShaderMaterial
var wind_materials: Array[ShaderMaterial] = []
var obstructions: RefCounted
var world: Node
var foliage_cache := {}
var clock := 0.0
var leaf_fog: ShaderMaterial
var forest: RefCounted
var terrain_relief: RefCounted
var cinematic_enabled := false
var particles_paused := false
var footprint_root: Node3D
var footprint_multi: MultiMesh
var footprint_marks: Array[Dictionary] = []
var footprint_cursor := 0
var footprint_last := Vector3.INF
var footprint_side := -1.0

func _init(owner_world: Node) -> void:
	world = owner_world
	cinematic_enabled = "--cinematic-art" in OS.get_cmdline_user_args() and "--original-environment" not in OS.get_cmdline_user_args()
	obstructions = ObstructionFade.new(world)
	leaf_fog = make_foliage_fog(0.055)
	leaf_fog.set_shader_parameter("canopy_cutout",true)
	if not world.has_node("Island"): return
	var island: Node = world.get_node("Island")
	var ground_node: MeshInstance3D = island.get_node_or_null("IslandGround")
	if not ground_node: ground_node = island.get_node_or_null("ReferenceGround")
	var tree_root: Node = island.get_node_or_null("IslandTrees")
	if not tree_root: tree_root = island.get_node_or_null("TreesFromMap")
	if ground_node:
		ground_node.mesh = TerrainSurface.build(world.board.layout)
		# Picking and the rendered bank share the same tessellation. Walkable
		# cells are pinned by TerrainSurface, including existing building plots.
		for child in ground_node.get_children():
			if child is StaticBody3D: child.free()
		ground_node.create_trimesh_collision()
		for cluster in tree_root.get_children():
			if cluster.has_meta("harvest_tree"):
				for part in cluster.get_children():
					if part is Node3D: part.global_position.y = world.board.layout.height_at(part.global_position.x,part.global_position.z)
			elif cluster is Node3D:
				cluster.global_position.y = world.board.layout.height_at(cluster.global_position.x,cluster.global_position.z)
		ground = ShaderMaterial.new()
		ground.shader = GroundShader
		var water_levels := Image.create_from_data(128,128,false,Image.FORMAT_RF,world.board.layout.water_cells.to_byte_array())
		ground.set_shader_parameter("water_levels",ImageTexture.create_from_image(water_levels))
		if not world.board.layout.surface_water_levels.is_empty():
			var river_levels := Image.create_from_data(257,257,false,Image.FORMAT_RF,world.board.layout.surface_water_levels.to_byte_array())
			ground.set_shader_parameter("continuous_water_levels",ImageTexture.create_from_image(river_levels))
			ground.set_shader_parameter("has_continuous_water",true)
		ground.set_shader_parameter("detail_map",load("res://assets/materials/ground_detail.png"))
		ground_palette = GroundPalette.new(world)
		ground.set_shader_parameter("usage_map",ground_palette.texture)
		ground.set_shader_parameter("soil_map",load("res://assets/materials/camp_soil.png"))
		ground.set_shader_parameter("forest_map",load("res://assets/materials/forest_floor.png"))
		for surface in ["turf", "soil", "litter", "rock"]:
			ground.set_shader_parameter(surface + "_surface", load("res://assets/materials/terrain/%s.png" % surface))
		buildable_image = Image.create(128,128,false,Image.FORMAT_R8)
		for y in range(128):
			for x in range(128): buildable_image.set_pixel(x,y,Color(1 if world.board.layout.build[y*128+x] else 0,0,0))
		buildable_texture = ImageTexture.create_from_image(buildable_image)
		ground.set_shader_parameter("buildable_map",buildable_texture)
		ground_node.material_override = ground
	if island.has_node("Water"):
		island.get_node("Water").mesh = WaterSurface.build(world.board.layout)
		water = ShaderMaterial.new()
		water.shader = WaterShader
		# Water already has alpha: a second coplanar transparent fog pass sorts
		# against the entire island as the camera moves. Apply fog once in-shader.
		water.render_priority = 1
		water.set_shader_parameter("visibility_map",world.vision.texture)
		island.get_node("Water").material_overlay = null
		island.get_node("Water").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Depth comes from the terrain height map: gl_compatibility has no
		# usable depth texture, and the pond beds never change at runtime.
		var bed: Image = world.board.layout.height_image()
		water.set_shader_parameter("ground_heights",ImageTexture.create_from_image(bed))
		island.get_node("Water").material_override = water
	variation = TreeVariation.new(world, cinematic_enabled)
	style_leaves(island)
	forest = ForestRenderer.new(world, "--unbatched-forest" not in OS.get_cmdline_user_args(), cinematic_enabled)
	add_ground_cover(island)
	terrain_relief = TerrainRelief.new(world, island.get_node("GroundCover"))
	for node in island.find_children("*", "Node3D", true, false):
		if node.scene_file_path.contains("rock.tscn"): obstructions.register(node)

func update_view(dt: float = 0.0) -> void:
	if particles_paused != world.presentation_paused():
		particles_paused = world.presentation_paused()
		for building in world.visuals.values():
			for particle in building.find_children("*", "CPUParticles3D", true, false):
				particle.speed_scale = 0.0 if particles_paused else 1.0
	obstructions.update(dt)
	update_footprints(dt)
	if ground_palette: ground_palette.update()
	if world.weather:
		for mat in wind_materials:
			mat.set_shader_parameter("weather_clock",world.weather.clock)
			mat.set_shader_parameter("wind_power",world.weather.wind)
			mat.set_shader_parameter("wind_direction",world.weather.direction)
			mat.set_shader_parameter("rain_power",world.weather.rain)
			if mat.shader == FoliageShader:
				mat.set_shader_parameter("wetness",world.weather.wetness)
		if ground:
			ground.set_shader_parameter("wetness",world.weather.wetness)
			ground.set_shader_parameter("build_preview",not world.build_mode.is_empty() and not world.paused)
			ground.set_shader_parameter("builder_position",world.hero.position)
		if water:
			water.set_shader_parameter("weather_clock",world.weather.clock)
			water.set_shader_parameter("wind_power",world.weather.wind)
	if buildable_dirty and buildable_texture:
		buildable_texture.update(buildable_image)
		buildable_dirty = false
	if forest: forest.update_lod(world.camera_rig.focus,world.camera.size)
	var enabled := 1.0 if world.hero.health > 0 and "--no-canopy-cutout" not in OS.get_cmdline_user_args() else 0.0
	for mat in foliage_cache.values() + [leaf_fog]:
		mat.set_shader_parameter("actor_focus",world.hero.global_position + Vector3.UP * 1.15)
		mat.set_shader_parameter("camera_axis",world.camera.global_basis.z.normalized())
		mat.set_shader_parameter("camera_world_position",world.camera.global_position)
		mat.set_shader_parameter("cutout_enabled",enabled)

func refresh_buildable_cell(cell: Vector2i) -> void:
	if buildable_image == null or not Rect2i(0, 0, 128, 128).has_point(cell): return
	var allowed: bool = world.board.can_build(cell)
	buildable_image.set_pixel(cell.x, cell.y, Color(1 if allowed else 0, 0, 0))
	buildable_dirty = true

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
		if world.board.layout.water_level_at(p.x,p.z) > p.y-0.08: continue
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
			var source_at: Transform3D = chunks[key][i]
			var at := Transform3D(surface_basis(source_at.origin, source_at.basis.get_euler().y, source_at.basis.get_scale()), source_at.origin)
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
	add_surface_layers(root)
	add_footprint_layer(root)

func add_surface_layers(parent: Node3D) -> void:
	# These are small, low-poly foreground cues rather than a second forest.
	# They sit on open terrain only and are kept in the cosmetic GroundCover root.
	var random := RandomNumberGenerator.new()
	random.seed = 651204
	var groups := {"dry": {}, "litter": {}, "pebbles": {}}
	for i in range(4800):
		var p := Vector3(random.randf_range(-126,126),0,random.randf_range(-126,126))
		var cell: Vector2i = world.board.cell_at(p)
		if not world.board.is_open(cell): continue
		p.y = world.board.layout.height_at(p.x,p.z)
		if world.board.layout.water_level_at(p.x,p.z) > p.y-0.08: continue
		if p.distance_to(world.hero.position) < 3.5: continue
		var patch := sin(p.x*.19+sin(p.z*.13)*1.6)*cos(p.z*.27-p.x*.04)
		if patch < -0.04: continue
		var slope := Vector2(world.board.layout.height_at(p.x+.8,p.z)-world.board.layout.height_at(p.x-.8,p.z), world.board.layout.height_at(p.x,p.z+.8)-world.board.layout.height_at(p.x,p.z-.8)).length()
		var roll := random.randf()
		# Keep stones tied to exposed, uneven ground. A uniform scatter reads as
		# gameplay glyphs at the tactical zoom, especially on the open clearing.
		var stone_patch := slope > .28 or patch > .58
		var kind := "pebbles" if stone_patch and roll > .86 else ("dry" if roll < (0.26 if slope > .55 else .15) else "litter")
		var chunk := Vector2i(floori(p.x/24.0),floori(p.z/24.0))
		if not groups[kind].has(chunk): groups[kind][chunk] = []
		groups[kind][chunk].append({"position":p,"scale":random.randf_range(.72,1.28),"angle":random.randf()*TAU,"tone":random.randf()})
	var configs := [
		{"kind":"dry","mesh":make_dry_grass_mesh(),"limit":1500},
		{"kind":"litter","mesh":make_leaf_litter_mesh(),"limit":900},
		{"kind":"pebbles","mesh":make_pebble_mesh(),"limit":520}
	]
	var surface_material := make_ground_mark_material()
	var pebble_material := make_pebble_material()
	for config in configs:
		var batches: Dictionary = groups[config.kind]
		var emitted := 0
		for chunk in batches:
			if emitted >= config.limit: break
			var entries: Array = batches[chunk]
			var count := mini(entries.size(),config.limit-emitted)
			if count <= 0: continue
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.mesh = config.mesh
			multi.instance_count = count
			var center := Vector3((chunk.x+0.5)*24.0,0,(chunk.y+0.5)*24.0)
			for i in range(count):
				var entry: Dictionary = entries[i]
				var p: Vector3 = entry.position
				var scale: float = entry.scale
				var local := p-center
				var lift := .022 if config.kind == "pebbles" else .012
				var normal := surface_normal(p)
				var basis := surface_basis(p,entry.angle,Vector3.ONE*scale)
				multi.set_instance_transform(i,Transform3D(basis,local+normal*lift))
				var base := Color("6f8051")
				if config.kind == "dry": base = Color("8e8554")
				elif config.kind == "litter": base = Color("5d573b")
				else: base = Color("596159")
				var target := Color("a1a476") if config.kind != "pebbles" else Color("858875")
				var tint_amount := .28 if config.kind != "pebbles" else .16
				multi.set_instance_color(i,base.lerp(target,entry.tone*tint_amount))
			var instance := MultiMeshInstance3D.new()
			instance.name = "Surface_%s_%s_%s" % [config.kind,chunk.x,chunk.y]
			instance.position = center
			instance.multimesh = multi
			instance.material_override = pebble_material if config.kind == "pebbles" else surface_material
			instance.material_overlay = world.vision.overlay
			instance.visibility_range_end = 105
			instance.visibility_range_end_margin = 12
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(instance)
			emitted += count

func add_footprint_layer(parent: Node3D) -> void:
	footprint_root = Node3D.new()
	footprint_root.name = "Footprints"
	parent.add_child(footprint_root)
	footprint_multi = MultiMesh.new()
	footprint_multi.transform_format = MultiMesh.TRANSFORM_3D
	footprint_multi.use_colors = true
	footprint_multi.mesh = make_pressed_grass_mesh()
	footprint_multi.instance_count = 28
	footprint_multi.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.name = "PressedGrass"
	instance.multimesh = footprint_multi
	instance.material_override = make_ground_mark_material()
	instance.material_overlay = world.vision.overlay
	instance.visibility_range_end = 78
	instance.visibility_range_end_margin = 8
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	footprint_root.add_child(instance)

func update_footprints(dt: float) -> void:
	if footprint_multi == null or world.hero == null: return
	for mark in footprint_marks: mark.age += dt
	footprint_marks = footprint_marks.filter(func(mark: Dictionary): return mark.age < 16.0)
	var current: Vector3 = world.hero.position
	if footprint_last == Vector3.INF: footprint_last = current
	var moved := current.distance_to(footprint_last)
	if moved > .42 and world.hero.health > 0 and not world.paused:
		var delta := current-footprint_last
		delta.y = 0
		if delta.length() > .01:
			var forward := delta.normalized()
			var lateral := Vector3(-forward.z,0,forward.x)*.16*footprint_side
			var at := current - forward*.12 + lateral
			at.y = world.board.layout.height_at(at.x,at.z)+.01
			footprint_marks.append({"position":at,"angle":atan2(forward.x,forward.z),"age":0.0,"side":footprint_side})
			footprint_side *= -1.0
			footprint_last = current
	if footprint_marks.size() > 28: footprint_marks = footprint_marks.slice(footprint_marks.size()-28)
	footprint_multi.visible_instance_count = footprint_marks.size()
	for i in range(footprint_marks.size()):
		var mark: Dictionary = footprint_marks[i]
		var fade := 1.0-smoothstep(8.0,16.0,float(mark.age))
		var at: Vector3 = mark.position
		var normal := surface_normal(at)
		footprint_multi.set_instance_transform(i,Transform3D(surface_basis(at,float(mark.angle),Vector3(.82,1.0,.64)),at+normal*.012))
		footprint_multi.set_instance_color(i,Color(.26,.30,.20,.18*fade))

func surface_normal(at: Vector3) -> Vector3:
	var dx: float = world.board.layout.height_at(at.x+.45,at.z)-world.board.layout.height_at(at.x-.45,at.z)
	var dz: float = world.board.layout.height_at(at.x,at.z+.45)-world.board.layout.height_at(at.x,at.z-.45)
	return Vector3(-dx,2.0,-dz).normalized()

func surface_basis(at: Vector3, yaw: float, scale: Vector3 = Vector3.ONE) -> Basis:
	var normal := surface_normal(at)
	var axis := Vector3.UP.cross(normal)
	var align := Basis.IDENTITY
	if axis.length_squared() > 0.000001:
		align = Basis(axis.normalized(),acos(clampf(Vector3.UP.dot(normal),-1.0,1.0)))
	return (align * Basis(Vector3.UP,yaw)).scaled(scale)

func make_ground_mark_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GroundMarkShader
	return material

func make_pebble_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = .96
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

static func make_dry_grass_mesh() -> ArrayMesh:
	return make_blade_cluster(Color("887b4e"),Color("b0a36a"),.28,5)

static func make_leaf_litter_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Asymmetric, partly overlapping leaves avoid a repeated rosette silhouette.
	var centers := [Vector3(-.09,.018,-.02),Vector3(.03,.021,.07),Vector3(.08,.014,-.06),Vector3(-.01,.017,-.10)]
	var angles := [-.52,1.18,2.55,-1.72]
	var lengths := [.16,.13,.18,.11]
	for i in range(centers.size()):
		var angle: float = angles[i]
		var direction := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-direction.z,0,direction.x)*(.035+float(i%2)*.012)
		var center: Vector3 = centers[i]
		var tip := center+direction*float(lengths[i])+Vector3.UP*(.008+float(i%2)*.006)
		for vertex in [center-side,center+side,tip,center-side,tip,center+side*.35]:
			surface.set_color(Color("45412f").lerp(Color("6b6240"),float(i%3)/3.0))
			surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := surface.commit()
	return mesh

static func make_pebble_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# An uneven eight-sided chip avoids the bright, regular hexagon silhouette.
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for i in range(8):
		var angle := float(i)*TAU/8.0 + .12*sin(float(i)*2.7)
		var radius := .085 + float((i*3)%5)*.012
		lower.append(Vector3(cos(angle)*radius,.018+float(i%2)*.006,sin(angle)*radius*.72))
		upper.append(Vector3(cos(angle)*radius*.68,sin(float(i)*1.9)*.012+.065,sin(angle)*radius*.52))
	for i in range(8):
		var next := (i+1)%8
		for vertex in [lower[i],upper[next],upper[i],lower[i],lower[next],upper[next]]:
			surface.set_color(Color("4f5750").lerp(Color("92927a"),clampf((vertex.y-.01)/.07,0,1)))
			surface.add_vertex(vertex)
	for i in range(8):
		var next := (i+1)%8
		for vertex in [Vector3(.012,.085,-.006),upper[i],upper[next]]:
			surface.set_color(Color("8b8a73"))
			surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

static func make_pressed_grass_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Flattened radial blades read as a soft pressed mark from the tactical camera.
	for i in range(5):
		var angle := float(i)*TAU/5.0
		var direction := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-direction.z,0,direction.x)*.028
		var base := direction*.015+Vector3.UP*.006
		var tip := direction*(.16+float(i%2)*.035)+Vector3.UP*(.012+float(i%3)*.004)
		for vertex in [base-side,tip,base+side,base-side,base+side,tip]:
			surface.set_color(Color("34422f").lerp(Color("5c6740"),clampf(vertex.y/.018,0,1)))
			surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

static func make_blade_cluster(bottom: Color, top: Color, height: float, count: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(count):
		var angle := float(i)*TAU/count
		var direction := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-direction.z,0,direction.x)*.035
		var base := direction*.03+Vector3.UP*.008
		var tip := direction*(.11+float(i%3)*.03)+Vector3.UP*(height*(.72+float(i%3)*.08))
		for vertex in [base-side,tip,base+side,base-side,base+side,tip]:
			surface.set_color(bottom.lerp(top,clampf(vertex.y/maxf(height,.01),0,1)))
			surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

func add_ferns(parent: Node3D) -> void:
	var source: Node3D = (CinematicFernScene if cinematic_enabled else FernScene).instantiate()
	var random := RandomNumberGenerator.new()
	random.seed = 650908
	var chunks := {}
	for i in range(2300):
		var p := Vector3(random.randf_range(-126,126),0,random.randf_range(-126,126))
		var cell: Vector2i = world.board.cell_at(p)
		if not world.board.is_open(cell) or world.Regions.at(p) == "ice": continue
		if p.distance_to(world.hero.position) < 4.5: continue
		p.y = world.board.layout.height_at(p.x,p.z)
		if world.board.layout.water_level_at(p.x,p.z) > p.y-0.08: continue
		var chunk := Vector2i(floori(p.x/16),floori(p.z/16))
		if not chunks.has(chunk): chunks[chunk] = []
		var size := random.randf_range(0.55,1.05)
		chunks[chunk].append(Transform3D(Basis(Vector3.UP,random.randf()*TAU).scaled(Vector3.ONE*size),p))
	var fog := make_foliage_fog(0.045)
	var fern_material := ShaderMaterial.new()
	fern_material.shader = FoliageShader
	fern_material.set_shader_parameter("vertex_color",not cinematic_enabled)
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
	CampDetail.prepare(self, node, kind)
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
	# Cinematic meshes have multiple steel, paint and concrete surfaces. Keep
	# those source materials for the per-surface obstruction shader conversion.
	if world.cinematic_art_enabled and kind in ["generator", "lab", "laboratory", "gate", "shelter"]: return
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

func show_tent_occupant(node: Node3D, occupied: bool) -> void:
	# The survivor's own model is hidden while inside, so the tent has to say "someone
	# is in here" or it just looks like the character died.
	if not node.has_node("Occupant"):
		if not occupied: return
		var marker := Node3D.new()
		marker.name = "Occupant"
		node.add_child(marker)
		var glow := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.62, 0.62)
		glow.mesh = quad
		glow.position = Vector3(0, 1.55, 0)
		var glow_gradient := Gradient.new()
		glow_gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		glow_gradient.colors = PackedColorArray([Color(1, 0.92, 0.68, 0.85), Color(1, 0.85, 0.54, 0.35), Color(1, 0.85, 0.54, 0.0)])
		var glow_texture := GradientTexture2D.new()
		glow_texture.gradient = glow_gradient
		glow_texture.width = 64
		glow_texture.height = 64
		glow_texture.fill = GradientTexture2D.FILL_RADIAL
		glow_texture.fill_from = Vector2(0.5, 0.5)
		glow_texture.fill_to = Vector2(1.0, 0.5)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("ffd98a")
		material.albedo_texture = glow_texture
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.no_depth_test = true
		glow.material_override = material
		marker.add_child(glow)
		var label := Label3D.new()
		label.text = "有人在里面"
		label.font_size = 26
		label.pixel_size = 0.011
		label.position = Vector3(0, 2.25, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color("ffe6a8")
		marker.add_child(label)
	node.get_node("Occupant").visible = occupied

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
	if data.kind == "tower" and data.get("reinforced", false):
		if not node.has_node("Fortification"):
			var fortification := Node3D.new()
			fortification.name = "Fortification"
			node.add_child(fortification)
			for x in [-0.78, 0.78]:
				for z in [-0.78, 0.78]:
					Visual.box(fortification, Vector3(0.26, 1.3, 0.26), Vector3(x, 0.65, z), Color("65756e"))
					Visual.box(fortification, Vector3(0.34, 0.16, 0.34), Vector3(x, 1.2, z), Color("b5a77d"))
			world.vision.shade(fortification)
		node.get_node("Fortification").visible = complete
	if data.kind == "fire":
		var rain_dampen: float = 1.0 - (world.weather.rain * 0.24 if world.weather else 0.0)
		node.get_node("FireLight").visible = complete
		node.get_node("FireLight").light_energy = ((0.85 if world.night else 0.28) + sin(clock*8)*0.025 + sin(clock*13)*0.018) * rain_dampen
		node.get_node("Embers").emitting = complete and not world.paused
		node.get_node("Smoke").emitting = complete and not world.paused
		for name in ["Flame","FlameCore"]:
			var flame: Node3D = model.get_node(name)
			flame.visible = complete
			flame.scale = Vector3(1+sin(clock*7)*0.09,1+(sin(clock*11)*0.15)*rain_dampen,1+cos(clock*9)*0.08)
	CampDetail.update(self, node, data)
