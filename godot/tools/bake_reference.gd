extends SceneTree
const Data = preload("res://scripts/terrain_data.gd")
const Regions = preload("res://scripts/regions.gd")
var data = Data.new()

func _initialize() -> void:
	call_deferred("bake")

func bake() -> void:
	var island := Node3D.new()
	island.name = "Island"
	root.add_child(island)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wet := SurfaceTool.new()
	wet.begin(Mesh.PRIMITIVE_TRIANGLES)
	var palette := [Color("726c47"), Color("8c815a"), Color("81724e"), Color("444840"), Color("b7a87e"), Color("777e75"), Color("596c40"), Color("3a5735"), Color("bccdd0")]
	for y in range(128):
		for x in range(128):
			var i := y * 129 + x
			var a := Vector3(x * 2 - 128, data.heights[i], y * 2 - 128)
			var b := Vector3(a.x + 2, data.heights[i + 1], a.z)
			var c := Vector3(a.x, data.heights[i + 129], a.z + 2)
			var d := Vector3(a.x + 2, data.heights[i + 130], a.z + 2)
			add_triangle(st, a, b, c, palette)
			add_triangle(st, b, d, c, palette)
			var water: float = data.water[i]
			if water > -90 and minf(minf(a.y, b.y), minf(c.y, d.y)) < water + 0.05:
				for p in [a, b, c, b, d, c]:
					p.y = water + 0.04
					wet.set_color(Color("457f7c"))
					wet.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.92
	var noise := FastNoiseLite.new()
	noise.seed = 65065
	noise.frequency = 0.16
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.66, 0.7, 0.62), Color(1, 1, 0.97)])
	texture.color_ramp = ramp
	material.albedo_texture = texture
	mesh.surface_set_material(0, material)
	var ground := MeshInstance3D.new()
	ground.name = "IslandGround"
	ground.mesh = mesh
	island.add_child(ground)
	ground.create_trimesh_collision()
	wet.generate_normals()
	var water_mesh := wet.commit()
	water_mesh.surface_set_material(0, material)
	var water_node := MeshInstance3D.new()
	water_node.name = "Water"
	water_node.mesh = water_mesh
	island.add_child(water_node)
	var forest := Node3D.new()
	forest.name = "IslandTrees"
	island.add_child(forest)
	var models := {"broadleaf": load("res://scenes/models/broadleaf.tscn"), "snow_tree": load("res://scenes/models/snow_tree.tscn"), "rock": load("res://scenes/models/rock.tscn")}
	var tree_cells: Dictionary = {}
	for entry in data.placements:
		var x: float = entry[1]
		var z: float = entry[2]
		if entry[0] != "rock" and data.submerged_at(x, z): continue
		var p := Vector3(x, data.height_at(x, z), z)
		var cell := Vector2i(floori(x / 2) + 64, floori(z / 2) + 64)
		if cell.x < 0 or cell.y < 0 or cell.x >= 128 or cell.y >= 128: continue
		var parent: Node3D = forest
		if entry[0] != "rock":
			if not tree_cells.has(cell):
				var group := Node3D.new()
				group.name = "Trees_%d_%d" % [cell.x, cell.y]
				group.position = Vector3(cell.x * 2 - 127, 0, cell.y * 2 - 127)
				group.set_meta("harvest_tree", true)
				forest.add_child(group)
				tree_cells[cell] = group
			parent = tree_cells[cell]
		var n: Node3D = models[entry[0]].instantiate()
		n.name = "%s_%d" % [entry[0], parent.get_child_count()]
		parent.add_child(n)
		n.global_position = p
		n.rotation.y = -entry[3]
		var factor := 0.62 if entry[0] != "rock" else 0.85
		n.scale = Vector3(entry[4], entry[5], entry[4]) * factor
		if entry[0] == "rock": n.set_meta("navigation_blocker", true)
	assign_owner(island, island)
	var scene := PackedScene.new()
	var err := scene.pack(island)
	if err == OK: err = ResourceSaver.save(scene, "res://scenes/original_island.tscn")
	print("ORIGINAL ISLAND BAKE: ", tree_cells.size(), " tree clusters, save=", err)
	quit(err)

func add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, palette: Array) -> void:
	for p in [a, b, c]:
		var gx := clampi(roundi((p.x + 128) / 2), 0, 128)
		var gy := clampi(roundi((p.z + 128) / 2), 0, 128)
		var color := Color(0, 0, 0, 0)
		for dy in [-1, 0]:
			for dx in [-1, 0]:
				var index := clampi(gy + dy, 0, 128) * 129 + clampi(gx + dx, 0, 128)
				color += palette[int(data.tiles[index])] * 0.25
		var biome := Regions.at(p)
		if biome == "ice": color = color.lerp(Color("bacbce"), 0.62)
		if biome == "swamp": color = color.lerp(Color("415c43"), 0.3)
		if biome == "rainforest": color = color.lerp(Color("375d32"), 0.22)
		st.set_color(color)
		st.set_uv(Vector2(p.x, p.z) / 12.0)
		st.add_vertex(p)

func assign_owner(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		if child.scene_file_path.is_empty(): assign_owner(child, scene_root)
