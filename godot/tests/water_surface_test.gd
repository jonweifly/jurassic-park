extends SceneTree

const TerrainData = preload("res://scripts/terrain_data.gd")
const WaterSurface = preload("res://scripts/water_surface.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout := TerrainData.new()
	var mesh := WaterSurface.build(layout)
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var misplaced := 0
	var shoreline_vertices := 0
	var curved_domain_vertices := 0
	for i in range(0, vertices.size(), 3):
		var center := (vertices[i] + vertices[i + 1] + vertices[i + 2]) / 3.0
		var level: float = layout.water_level_at(center.x,center.z)
		if level <= -90.0 or absf(center.y - level - 0.04) > 0.001 or layout.height_at(center.x, center.z) > level + 0.001:
			misplaced += 1
		for j in range(3):
			var vertex := vertices[i + j]
			if absf(vertex.x-roundf(vertex.x)) > .001 or absf(vertex.z-roundf(vertex.z)) > .001:
				shoreline_vertices += 1
				if colors[i+j].a < .001: curved_domain_vertices += 1
	if vertices.size() < 1000 or shoreline_vertices < 50 or curved_domain_vertices < 100 or misplaced > 0:
		push_error("Water geometry invalid: vertices=%d clipped=%d misplaced=%d" % [vertices.size(), shoreline_vertices, misplaced])
		quit(1)
		return
	var world: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	var live_water: MeshInstance3D = world.get_node("Island/Water")
	var material: ShaderMaterial = world.scenery.water
	var heights: Texture2D = material.get_shader_parameter("ground_heights")
	if live_water.mesh.surface_get_array_len(0) != vertices.size() or heights.get_size() != Vector2(257, 257):
		push_error("Live water mesh or terrain textures are not bound")
		world.free()
		quit(1)
		return
	if live_water.material_overlay != null or material.get_shader_parameter("visibility_map") != world.vision.texture or material.render_priority <= world.vision.overlay.render_priority:
		push_error("Water must apply visibility once, after ground fog, without a coplanar transparent overlay")
		world.free()
		quit(1)
		return
	var image := heights.get_image()
	for y in range(0,257,7):
		for x in range(0,257,7):
			if absf(image.get_pixel(x,y).r-layout.height_at(x-128.0,y-128.0)) > .001:
				push_error("Water depth differs from the rendered terrain")
				world.free()
				quit(1)
				return
	world.free()
	print("WATER SURFACE: ", vertices.size() / 3, " triangles, ", shoreline_vertices, " shoreline vertices, 0 misplaced")
	quit()
