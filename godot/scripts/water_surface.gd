extends RefCounted

## Build only the submerged portions of the terrain triangles.
static func build(layout: RefCounted) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(128):
		for x in range(128):
			var i := y * 129 + x
			var level: float = layout.water[i]
			if level <= -90.0:
				continue
			var a := Vector3(x * 2 - 128, float(layout.heights[i]), y * 2 - 128)
			var b := Vector3(a.x + 2.0, float(layout.heights[i + 1]), a.z)
			var c := Vector3(a.x, float(layout.heights[i + 129]), a.z + 2.0)
			var d := Vector3(a.x + 2.0, float(layout.heights[i + 130]), a.z + 2.0)
			add_triangle(surface, a, b, c, level)
			add_triangle(surface, b, d, c, level)
	return surface.commit()

static func add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, level: float) -> void:
	var corners: Array[Vector3] = [a, b, c]
	var clipped: Array[Vector3] = []
	for i in range(3):
		var p := corners[i]
		var q := corners[(i + 1) % 3]
		var p_wet := p.y < level
		var q_wet := q.y < level
		if p_wet:
			clipped.append(p)
		if p_wet != q_wet:
			clipped.append(p.lerp(q, (level - p.y) / (q.y - p.y)))
	for i in range(1, clipped.size() - 1):
		var edge_a := clipped[i] - clipped[0]
		var edge_b := clipped[i + 1] - clipped[0]
		if absf(edge_a.x * edge_b.z - edge_a.z * edge_b.x) < 0.0001:
			continue
		for vertex in [clipped[0], clipped[i], clipped[i + 1]]:
			vertex.y = level + 0.04
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
