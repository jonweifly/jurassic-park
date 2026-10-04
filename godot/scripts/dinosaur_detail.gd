extends Node3D
## Small authored close-up accents. The production GLB remains the skinned body;
## head / jaw accents follow its existing bones and share two cached surfaces.
const MAX_DISTANCE := 42.0
const MAX_ORTHOGRAPHIC_SIZE := 35.0
static var mesh_cache: Dictionary = {}
var quality_owner: Node
var clock := 0.0

static func attach(visual: Node, rig: Skeleton3D, kind: String) -> Node3D:
	if rig.find_bone("head") < 0 or rig.find_bone("jaw") < 0: return null
	var jaw_pose = load("res://scripts/dinosaur_jaw_pose.gd").new()
	jaw_pose.name = "AnatomicalJawOpening"
	rig.add_child(jaw_pose)
	var detail = load("res://scripts/dinosaur_detail.gd").new()
	detail.name = "DinosaurCloseDetail"
	rig.add_child(detail)
	var ancestor: Node = visual.get_parent()
	while ancestor:
		if "preferences" in ancestor:
			detail.quality_owner = ancestor
			break
		ancestor = ancestor.get_parent()
	for bone in ["head", "jaw"]:
		var attachment := BoneAttachment3D.new()
		attachment.name = "CloseDetail_" + bone
		attachment.bone_name = bone
		attachment.set_external_skeleton(NodePath("../.."))
		attachment.use_external_skeleton = true
		detail.add_child(attachment)
		var piece := MeshInstance3D.new()
		piece.name = "EyeSurface" if bone == "head" else "LowerTeeth"
		var key: String = kind + "_" + bone
		if not mesh_cache.has(key):
			mesh_cache[key] = make_surface(kind, bone, rig.get_bone_global_rest(rig.find_bone(bone)).affine_inverse(), rig)
		piece.mesh = mesh_cache[key]
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.visibility_range_end = MAX_DISTANCE
		attachment.add_child(piece)
	detail.refresh_visibility()
	return detail

func _process(dt: float) -> void:
	clock += dt
	if clock < 0.25: return
	clock = 0.0
	refresh_visibility()

func refresh_visibility() -> void:
	var quality := 2
	if is_instance_valid(quality_owner) and quality_owner.preferences:
		quality = int(quality_owner.preferences.values.quality)
	var camera := get_viewport().get_camera_3d()
	visible = quality > 0 and (not camera or (camera.global_position.distance_to(global_position) < MAX_DISTANCE and (camera.projection != Camera3D.PROJECTION_ORTHOGONAL or camera.size <= MAX_ORTHOGRAPHIC_SIZE)))

static func anatomy(point: Vector3, kind: String) -> Vector3:
	if kind in ["young_trex", "trex", "alpha_trex"]:
		point = Vector3(point.x * 1.36, 1.80 + (point.y - 1.80) * 1.45, point.z + 0.15)
	elif kind == "spitter":
		point.x *= 0.86
		point.z = 0.8 + (point.z - 0.8) * 1.23
	return point

static func vertex(surface: SurfaceTool, point: Vector3, kind: String, rest_inverse: Transform3D, tint: Color) -> void:
	surface.set_color(tint)
	surface.add_vertex(rest_inverse * anatomy(point, kind))

static func ellipsoid(surface: SurfaceTool, center: Vector3, radius: Vector3, kind: String, inverse: Transform3D, tint: Color) -> void:
	# 120 triangles, with explicit pole fans and no degenerate pole triangles.
	var rows: Array[PackedVector3Array] = []
	for row in range(1, 6):
		var points := PackedVector3Array()
		var latitude := -PI * 0.5 + PI * row / 6.0
		for column in range(12):
			var angle := TAU * column / 12.0
			points.append(center + Vector3(cos(latitude) * cos(angle), sin(latitude), cos(latitude) * sin(angle)) * radius)
		rows.append(points)
	for column in range(12):
		var next := (column + 1) % 12
		for point in [center - Vector3(0, radius.y, 0), rows[0][column], rows[0][next]]:
			vertex(surface, point, kind, inverse, tint)
		for point in [center + Vector3(0, radius.y, 0), rows[-1][next], rows[-1][column]]:
			vertex(surface, point, kind, inverse, tint)
		for row in range(4):
			for point in [rows[row][column], rows[row + 1][column], rows[row + 1][next], rows[row][column], rows[row + 1][next], rows[row][next]]:
				vertex(surface, point, kind, inverse, tint)

static func tooth(surface: SurfaceTool, at: Vector3, height: float, kind: String, inverse: Transform3D) -> void:
	var tint := Color("d8cfad")
	for column in range(6):
		var angle := TAU * column / 6.0
		var next := TAU * (column + 1) / 6.0
		var a := at + Vector3(cos(angle) * .013, 0, sin(angle) * .013)
		var b := at + Vector3(cos(next) * .013, 0, sin(next) * .013)
		for point in [a, at + Vector3(0, height, .008), b, at, b, a]:
			surface.set_color(tint)
			surface.add_vertex(inverse * point)

static func jaw_surface(rig: Skeleton3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for child in rig.find_children("*", "MeshInstance3D", true, false):
		if child.skin == null: continue
		var arrays: Array = child.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride: int = weights.size() / points.size()
		var transform: Transform3D = rig.global_transform.affine_inverse() * child.global_transform
		for index in range(points.size()):
			for weight_index in range(stride):
				var slot := index * stride + weight_index
				if weights[slot] > .99 and child.skin.get_bind_name(joints[slot]) == &"jaw":
					result.append(transform * points[index])
	return result

static func make_surface(kind: String, bone: String, inverse: Transform3D, rig: Skeleton3D) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := 1.30 if kind in ["young_trex", "trex", "alpha_trex"] else 1.0
	var jaw_points := jaw_surface(rig) if bone == "jaw" else PackedVector3Array()
	for side in [-1.0, 1.0]:
		if bone == "head":
			ellipsoid(surface, Vector3(side * (.213 * width + .024), 2.005, .983), Vector3(.018, .042, .058), kind, inverse, Color("b88a39"))
			ellipsoid(surface, Vector3(side * (.213 * width + .039), 2.007, .996), Vector3(.006, .026, .013), kind, inverse, Color("10170e"))
		else:
			for index in range(5):
				var z := 1.054 + index * .083
				var x: float = side * (.120 - (z - 1.0) * .035) * width
				var target := anatomy(Vector3(x, 1.758, z), kind)
				var anchor := target
				var closest := INF
				for point in jaw_points:
					var distance: float = point.distance_squared_to(target)
					if distance < closest:
						closest = distance
						anchor = point
				# Root sits slightly inside the actual subdivided mandible, never
				# at the wider pre-subdivision authoring approximation.
				anchor.y -= .004
				if closest < .01:
					tooth(surface, anchor, .028 + .012 * sin((index + 1) * PI / 6.0), kind, inverse)
	var material := StandardMaterial3D.new()
	material.resource_name = "Dinosaur_Eye_Gloss" if bone == "head" else "Dinosaur_Tooth_Enamel"
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.24 if bone == "head" else 0.43
	material.metallic_specular = 0.65 if bone == "head" else 0.40
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.set_material(material)
	surface.generate_normals()
	surface.index()
	return surface.commit()
