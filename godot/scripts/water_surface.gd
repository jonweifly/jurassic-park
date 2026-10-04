extends RefCounted

## Build only the submerged portions of the terrain triangles.
static func build(layout: RefCounted) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(256):
		for x in range(256):
			var i := y * 257 + x
			var level: float = layout.water_level_at(x-127.5,y-127.5)
			if level <= -90.0:
				continue
			var a := Vector3(x - 128, layout.surface_heights[i], y - 128)
			var b := Vector3(a.x + 1.0, layout.surface_heights[i + 1], a.z)
			var c := Vector3(a.x, layout.surface_heights[i + 257], a.z + 1.0)
			var d := Vector3(a.x + 1.0, layout.surface_heights[i + 258], a.z + 1.0)
			if not layout.surface_water_levels.is_empty():
				var levels: PackedFloat32Array = layout.surface_water_levels
				add_continuous_triangle(surface, a, b, c, Vector3(levels[i], levels[i + 1], levels[i + 257]))
				add_continuous_triangle(surface, b, d, c, Vector3(levels[i + 1], levels[i + 258], levels[i + 257]))
				continue
			var field: PackedFloat32Array = layout.shore_field
			add_triangle(surface, a, b, c, level, Vector3(field[i],field[i+1],field[i+257]))
			add_triangle(surface, b, d, c, level, Vector3(field[i+1],field[i+258],field[i+257]))
	return surface.commit()

static func add_continuous_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, levels: Vector3) -> void:
	# Z stores water elevation and W stores depth. Interpolating both at the
	# shore makes neighbouring faces share every edge, including river mouths.
	var corners: Array[Vector4] = [Vector4(a.x, a.z, levels.x, levels.x - a.y), Vector4(b.x, b.z, levels.y, levels.y - b.y), Vector4(c.x, c.z, levels.z, levels.z - c.y)]
	var clipped: Array[Vector4] = []
	for i in range(3):
		var p := corners[i]
		var q := corners[(i + 1) % 3]
		if p.w > 0: clipped.append(p)
		if (p.w > 0) != (q.w > 0): clipped.append(p.lerp(q, p.w / (p.w - q.w)))
	for i in range(1, clipped.size() - 1):
		var edge_a := clipped[i] - clipped[0]
		var edge_b := clipped[i + 1] - clipped[0]
		if absf(edge_a.x * edge_b.y - edge_a.y * edge_b.x) < .0001: continue
		for vertex in [clipped[0], clipped[i], clipped[i + 1]]:
			surface.set_normal(Vector3.UP)
			surface.set_color(Color(1, 1, 1, clampf(vertex.w * 3, 0, 1)))
			surface.add_vertex(Vector3(vertex.x, vertex.z + .04, vertex.y))

static func add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, level: float, shore: Vector3) -> void:
	# W carries the basin field through both clips, including new shore vertices.
	var clipped: Array[Vector4] = [Vector4(a.x,a.y,a.z,shore.x),Vector4(b.x,b.y,b.z,shore.y),Vector4(c.x,c.y,c.z,shore.z)]
	for plane in range(2):
		var corners := clipped
		clipped = []
		for i in range(corners.size()):
			var p: Vector4 = corners[i]
			var q: Vector4 = corners[(i+1)%corners.size()]
			var pd := level-p.y if plane == 0 else p.w
			var qd := level-q.y if plane == 0 else q.w
			if pd > 0: clipped.append(p)
			if (pd > 0) != (qd > 0): clipped.append(p.lerp(q,pd/(pd-qd)))
	for i in range(1, clipped.size() - 1):
		var edge_a := clipped[i] - clipped[0]
		var edge_b := clipped[i + 1] - clipped[0]
		if absf(edge_a.x * edge_b.z - edge_a.z * edge_b.x) < 0.0001:
			continue
		for vertex in [clipped[0], clipped[i], clipped[i + 1]]:
			surface.set_normal(Vector3.UP)
			surface.set_color(Color(1,1,1,clampf(vertex.w,0,1)))
			surface.add_vertex(Vector3(vertex.x,level+.04,vertex.z))
