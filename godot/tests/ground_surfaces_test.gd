extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	load("res://scripts/save_store.gd").directory = "user://ground_surfaces_fixture"
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500,"standard")
	var ground: ShaderMaterial = world.scenery.ground
	expect(ground != null and ground.shader != null,"Live terrain has the surface shader")
	var layout: RefCounted = world.board.layout
	var protected_error := 0.0
	var modified := 0
	var maximum_change := 0.0
	for y in range(128):
		for x in range(128):
			for offset in [Vector2(.25,.25),Vector2(.8,.3),Vector2(.7,.8)]:
				var px: float = (x+offset.x)*2-128
				var pz: float = (y+offset.y)*2-128
				var change := absf(layout.height_at(px,pz)-layout.source_height_at(px,pz))
				maximum_change = maxf(maximum_change,change)
				if Vector2(px,pz).length() < 35: continue # Authored opening has a new continuous profile.
				if layout.walk[y*128+x] or layout.build[y*128+x]: protected_error = maxf(protected_error,change)
				elif change > .02: modified += 1
	expect(protected_error < .0001,"All traversable cells and building plots retain their original surface, not only their centres")
	expect(modified > 1000 and maximum_change < .721,"Blocked slopes and shores become curved within a bounded height change")
	var ground_node: MeshInstance3D = world.get_node("Island/ReferenceGround")
	var arrays := ground_node.mesh.surface_get_arrays(0)
	var terrain_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var terrain_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	expect(terrain_vertices.size()==257*257 and terrain_indices.size()==256*256*6,"Terrain uses shared vertices and one-metre surface samples")
	await physics_frame
	var pick_error := 0.0
	for i in range(0,terrain_indices.size(),1239):
		var at := (terrain_vertices[terrain_indices[i]]+terrain_vertices[terrain_indices[i+1]]+terrain_vertices[terrain_indices[i+2]])/3.0
		var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*30,at-Vector3.UP*30,1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): pick_error = INF
		else: pick_error = maxf(pick_error,absf(hit.position.y-layout.height_at(at.x,at.z)))
	expect(pick_error < .002,"Rendered terrain, CPU surface samples and physics picking match across the island")
	print("TERRAIN GEOMETRY: protected_error=",protected_error," modified_samples=",modified," maximum_change=",maximum_change," pick_error=",pick_error)
	for kind in ["turf","soil","litter","rock"]:
		var texture: Texture2D = ground.get_shader_parameter(kind+"_surface")
		expect(texture != null and texture.get_size()==Vector2(1024,1024),kind+" texture is imported and bound to terrain")
		var source := texture.get_image()
		expect(not source.is_empty() and source.get_format()==Image.FORMAT_RGBA8,kind+" carries colour and relief")
		expect(source.has_mipmaps(),kind+" is filtered at distance instead of aliasing")
		var heights := {}
		var colours := {}
		for y in range(0,1024,32):
			for x in range(0,1024,32):
				var pixel := source.get_pixel(x,y)
				heights[pixel.a8] = true
				colours[pixel.to_html(false)] = true
		expect(heights.size()>20 and colours.size()>100,kind+" retains surface variation and relief data")
	var rng_state: int = world.rng.state
	var revision: int = world.board.revision
	var relief: RefCounted = world.scenery.terrain_relief
	expect(relief.placements.size()>100 and relief.batches.size()<relief.placements.size()/3,"Real bank silhouettes use spatial batches rather than one node per stone")
	var blocked_only := true
	var footprints_contained := true
	var stone_vertices: PackedVector3Array = relief.batches[0].multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for entry in relief.placements:
		var cell: Vector2i = entry.cell
		blocked_only = blocked_only and not world.board.layout.walk[cell.y*128+cell.x] and not world.trees.has(cell)
		for vertex in stone_vertices:
			footprints_contained = footprints_contained and world.board.cell_at(entry.transform*vertex)==cell
	expect(blocked_only and footprints_contained,"Bank stones stay completely within existing blocked cells and never cover walkable/buildable lanes")
	expect(relief.root.find_children("*","CollisionObject3D",true,false).is_empty(),"Visual bank relief adds no physics or picking collision")
	var forms := {}
	for y in range(0,256,4):
		for x in range(0,256,4): forms[world.scenery.ground_palette.landform_image.get_pixel(x,y).b8] = true
	expect(forms.size()>30,"Terrain shading follows actual ridges and concave banks")
	var root_batches: Array = world.scenery.forest.batches.filter(func(batch):return str(batch.node.name).begins_with("RootFlares_"))
	expect(not root_batches.is_empty(),"The live forest has physical trunk roots")
	for quality in [0,1,2]:
		world.preferences.values.quality = quality
		world.preferences.apply(world,false)
		expect(relief.root.is_visible_in_tree()==(quality>0),"Bank geometry respects the existing ground detail quality setting")
		for weather in [0,2]:
			world.weather.preview_kind = weather
			world.weather.update()
			world.scenery.update_view(0)
			expect(is_equal_approx(float(ground.get_shader_parameter("wetness")),world.weather.wetness),"Actual weather drives ground wetness at each quality")
	expect(world.rng.state==rng_state and world.board.revision==revision,"Surface and quality changes preserve navigation and gameplay RNG")
	if not root_batches.is_empty():
		var root_slot: Dictionary = root_batches[0].entries[0]
		var tree_cell: Vector2i = root_slot.cell
		var forest: RefCounted = world.scenery.forest
		var before: int = forest.live_parts()
		var owned: int = forest.cells[tree_cell].size()
		world.clear_tree(tree_cell)
		expect(forest.live_parts()==before-owned and not forest.cells.has(tree_cell),"Harvest removes the trunk roots together with every part of its tree")
	world.free()
	print("GROUND SURFACES: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
