extends RefCounted
## Silhouette detail on existing blocked banks. No collisions, height edits or RNG use.
const CHUNK_SIZE := 24.0
var root: Node3D
var placements: Array[Dictionary] = []
var batches: Array[MultiMeshInstance3D] = []

func _init(world: Node, parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "TerrainRelief"
	parent.add_child(root)
	if not world.board.layout: return
	var groups := {}
	for y in range(1,127):
		for x in range(1,127):
			var cell := Vector2i(x,y)
			var seed_value := posmod(x*1973+y*9277+x*y*17,101)
			# Keep paths, resource cells and building plots clear and unambiguous.
			if world.board.layout.walk[y*128+x] or world.trees.has(cell) or seed_value > 52: continue
			var p: Vector3 = world.board.point(cell)
			if world.board.layout.submerged_at(p.x,p.z): continue
			var dx: float = world.board.layout.height_at(p.x+.6,p.z)-world.board.layout.height_at(p.x-.6,p.z)
			var dz: float = world.board.layout.height_at(p.x,p.z+.6)-world.board.layout.height_at(p.x,p.z-.6)
			if Vector2(dx,dz).length() < .55: continue
			var normal := Vector3(-dx,1.2,-dz).normalized()
			var across := Vector3(normal.y,-normal.x,0).normalized()
			var basis := Basis(across,normal,across.cross(normal)).rotated(normal,float(seed_value)*2.399)
			var size := .45+float(seed_value%7)*.045
			basis = basis * Basis.from_scale(Vector3(size,.40+float(seed_value%5)*.055,size*.78))
			# The mesh base is buried in the bank and its projected radius stays
			# inside this already blocked cell, including on the steepest slope.
			var at := Transform3D(basis,p-normal*.035)
			var chunk := Vector2i(floori(p.x/CHUNK_SIZE),floori(p.z/CHUNK_SIZE))
			if not groups.has(chunk): groups[chunk] = []
			var color := Color("83907a") if world.Regions.at(p) != "ice" else Color("a5b4b3")
			var entry := {"cell":cell,"transform":at,"color":color}
			groups[chunk].append(entry)
			placements.append(entry)
	var mesh := make_bank_stone()
	for chunk in groups:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = mesh
		multi.instance_count = groups[chunk].size()
		var center := Vector3((chunk.x+.5)*CHUNK_SIZE,0,(chunk.y+.5)*CHUNK_SIZE)
		for i in range(multi.instance_count):
			var entry: Dictionary = groups[chunk][i]
			var at: Transform3D = entry.transform
			at.origin -= center
			multi.set_instance_transform(i,at)
			multi.set_instance_color(i,entry.color)
		var node := MultiMeshInstance3D.new()
		node.name = "BankStones_%d" % batches.size()
		node.multimesh = multi
		node.position = center
		node.material_overlay = world.vision.overlay
		node.visibility_range_end = 120
		node.visibility_range_end_margin = 12
		root.add_child(node)
		batches.append(node)

static func make_bank_stone() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Three uneven rings give each outcrop a broken shelf and a broad lit top.
	var rings: Array[PackedVector3Array] = []
	for ring in range(3):
		var points := PackedVector3Array()
		for i in range(7):
			var angle := float(i)*TAU/7.0
			var radius: float = [1.0,.92,.56][ring] * (1.0+sin(i*3.7)*.14)
			points.append(Vector3(cos(angle)*radius,[-.38,.22,.61][ring]+sin(i*2.3+ring)*.08,sin(angle)*radius))
		rings.append(points)
	for ring in range(2):
		for i in range(7):
			var j := (i+1)%7
			for vertex in [rings[ring][i],rings[ring+1][j],rings[ring+1][i],rings[ring][i],rings[ring][j],rings[ring+1][j]]:
				surface.set_color(Color("657063").lerp(Color("c0b998"),clampf((vertex.y+.25)/.9,0,1)))
				surface.add_vertex(vertex)
	for i in range(7):
		for vertex in [Vector3(0,.65,0),rings[2][i],rings[2][(i+1)%7]]:
			surface.set_color(Color("bab99b"))
			surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = .96
	mesh.surface_set_material(0,material)
	return mesh
