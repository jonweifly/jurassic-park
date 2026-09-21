extends RefCounted
## Static buildings/rocks share a camera-only stipple aperture; physics and vision are untouched.
const ShaderSource = preload("res://shaders/obstruction.gdshader")
var world: Node
var materials := {}
var meshes := 0
var strength := 0.0

func _init(owner_world: Node) -> void:
	world = owner_world

func register(node: Node) -> void:
	if "--original-obstruction-materials" in OS.get_cmdline_user_args(): return
	if node is MeshInstance3D and node.mesh and node.skin == null:
		var converted := false
		for i in range(node.mesh.get_surface_count()):
			var source: Material = node.get_active_material(i)
			if not source is StandardMaterial3D: continue
			if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: continue
			var key := source.get_instance_id()
			if not materials.has(key):
				var mat := ShaderMaterial.new()
				mat.shader = ShaderSource
				mat.set_shader_parameter("tint", source.albedo_color)
				mat.set_shader_parameter("roughness", source.roughness)
				mat.set_shader_parameter("metallic", source.metallic)
				mat.set_shader_parameter("specular", source.metallic_specular)
				mat.set_shader_parameter("source_cull_mode", source.cull_mode)
				mat.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
				mat.set_shader_parameter("normal_scale", source.normal_scale)
				for pair in [["albedo", source.albedo_texture], ["normal", source.normal_texture if source.normal_enabled else null], ["roughness", source.roughness_texture]]:
					mat.set_shader_parameter("has_" + pair[0], pair[1] != null)
					if pair[1]: mat.set_shader_parameter(pair[0] + "_tex", pair[1])
				mat.set_shader_parameter("visibility_map", world.vision.texture)
				materials[key] = mat
			node.set_surface_override_material(i, materials[key])
			converted = true
		if converted:
			node.material_override = null
			node.material_overlay = null # Visibility is evaluated inside the same cutout pass.
			meshes += 1
	for child in node.get_children(): register(child)

func update(dt: float) -> void:
	var enabled: bool = world.hero.health > 0 and "--no-obstruction-fade" not in OS.get_cmdline_user_args()
	strength = lerpf(strength, 1.0 if enabled else 0.0, 1.0 if dt == 0 else 1.0 - exp(-10.0 * dt))
	for material in materials.values():
		material.set_shader_parameter("actor_focus", world.hero.global_position + Vector3.UP * 1.0)
		material.set_shader_parameter("camera_axis", world.camera.global_basis.z.normalized())
		material.set_shader_parameter("camera_world_position", world.camera.global_position)
		material.set_shader_parameter("cutout_enabled", strength)
