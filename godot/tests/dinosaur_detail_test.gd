extends SceneTree
const Catalog = preload("res://scripts/dinosaur_catalog.gd")
var checks := 0
var failures := 0

class PreferenceStub extends RefCounted:
	var values := {"quality": 2}
class Stage extends Node3D:
	var preferences = PreferenceStub.new()

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func deformed_vertex(points: PackedVector3Array, joints: PackedInt32Array, weights: PackedFloat32Array, skin: Skin, rig: Skeleton3D, index: int) -> Vector3:
	var stride: int = weights.size() / points.size()
	var point := Vector3.ZERO
	for slot_offset in range(stride):
		var slot := index * stride + slot_offset
		var bone := rig.find_bone(skin.get_bind_name(joints[slot]))
		point += (rig.get_bone_global_pose(bone) * skin.get_bind_pose(joints[slot]) * points[index]) * weights[slot]
	return point

func imported_vertex(points: PackedVector3Array, source_position: Array) -> int:
	var target := Vector3(source_position[0], source_position[1], source_position[2])
	for index in range(points.size()):
		if points[index].distance_squared_to(target) < 0.00000001: return index
	return -1

func closest_point(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return a
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0: return a + ab * d1 / (d1 - d3)
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0: return a + ac * d2 / (d2 - d6)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * (d4 - d3) / ((d4 - d3) + (d5 - d6))
	return a + ab * (vb / (va + vb + vc)) + ac * (vc / (va + vb + vc))

func run() -> void:
	var refinements: Array = JSON.parse_string(FileAccess.get_file_as_string("res://../art/dinosaur-detail-refinement.json"))
	var stage := Stage.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(4, 3, 6)
	camera.current = true
	for kind in Catalog.SPECIES:
		var pawn: Node3D = load("res://scenes/models/%s.tscn" % kind).instantiate()
		pawn.is_dinosaur = true
		stage.add_child(pawn)
		var detail: Node3D = pawn.visual.dinosaur_detail
		expect(detail != null, kind + " adds budgeted close detail")
		if not detail:
			pawn.free()
			continue
		var rig := pawn.get_node("Model/Rig/Skeleton3D") as Skeleton3D
		var mesh_nodes := detail.find_children("*", "MeshInstance3D", true, false)
		var triangles := 0
		for mesh_node in mesh_nodes:
			var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
			expect(mesh_node.mesh.get_surface_count() == 1 and mesh_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, kind + " single cached surface with no tiny shadow pass")
		expect(mesh_nodes.size() == 2 and triangles <= 600, kind + " keeps head and jaw at two surfaces / 600 triangles")
		var jaw_attachment := detail.get_node("CloseDetail_jaw") as BoneAttachment3D
		pawn.visual.play("attack", .3)
		await process_frame
		await process_frame
		var jaw_index := rig.find_bone("jaw")
		var skinned_body := rig.find_children("*", "MeshInstance3D", true, false).filter(func(node): return node.skin != null)[0] as MeshInstance3D
		var body_arrays: Array = skinned_body.mesh.surface_get_arrays(0)
		var report: Dictionary = refinements.filter(func(entry): return entry.name == kind)[0]
		for contact: Dictionary in report.foreclaw_contacts + report.scute_contacts:
			var root_sum := Vector3.ZERO
			for source_position: Array in contact.root_positions:
				var imported_index := imported_vertex(body_arrays[Mesh.ARRAY_VERTEX], source_position)
				root_sum += deformed_vertex(body_arrays[Mesh.ARRAY_VERTEX], body_arrays[Mesh.ARRAY_BONES], body_arrays[Mesh.ARRAY_WEIGHTS], skinned_body.skin, rig, imported_index)
			var claw_root: Vector3 = root_sum / contact.root_positions.size()
			var tri: Array = contact.skin_positions.map(func(position): return imported_vertex(body_arrays[Mesh.ARRAY_VERTEX], position))
			var skin_point := closest_point(claw_root,
				deformed_vertex(body_arrays[Mesh.ARRAY_VERTEX], body_arrays[Mesh.ARRAY_BONES], body_arrays[Mesh.ARRAY_WEIGHTS], skinned_body.skin, rig, tri[0]),
				deformed_vertex(body_arrays[Mesh.ARRAY_VERTEX], body_arrays[Mesh.ARRAY_BONES], body_arrays[Mesh.ARRAY_WEIGHTS], skinned_body.skin, rig, tri[1]),
				deformed_vertex(body_arrays[Mesh.ARRAY_VERTEX], body_arrays[Mesh.ARRAY_BONES], body_arrays[Mesh.ARRAY_WEIGHTS], skinned_body.skin, rig, tri[2]))
			expect(claw_root.distance_to(skin_point) < .018, kind + " decorative roots stay seated against the deformed skin in the attack pose")
		var rest_rotation := rig.get_bone_rest(jaw_index).basis.get_rotation_quaternion()
		var delta := rest_rotation.inverse() * rig.get_bone_pose_rotation(jaw_index)
		var corrected := rest_rotation * Quaternion(-delta.x, delta.y, delta.z, delta.w)
		var corrected_local := Transform3D(Basis(corrected).scaled(rig.get_bone_pose_scale(jaw_index)), rig.get_bone_pose_position(jaw_index))
		var expected := rig.global_transform * rig.get_bone_global_pose(rig.get_bone_parent(jaw_index)) * corrected_local
		expect(jaw_attachment.global_transform.is_equal_approx(expected), kind + " lower teeth follow the full corrected jaw transform")
		var tip := Vector3(0, 1.735, 1.48)
		if kind in ["young_trex", "trex", "alpha_trex"]: tip = Vector3(0, 1.8 + (tip.y - 1.8) * 1.45, tip.z + .15)
		elif kind == "spitter": tip.z = .8 + (tip.z - .8) * 1.23
		var tip_local := rig.get_bone_global_rest(jaw_index).affine_inverse() * tip
		var uncorrected := rig.global_transform * rig.get_bone_global_pose(jaw_index) * tip_local
		var corrected_tip := jaw_attachment.global_transform * tip_local
		expect(corrected_tip.y < uncorrected.y - .1, kind + " attack opens the mandible downwards instead of through the snout")
		stage.preferences.values.quality = 0
		detail.refresh_visibility()
		expect(not detail.visible, kind + " skips additional draw calls in low quality")
		stage.preferences.values.quality = 2
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 50
		detail.refresh_visibility()
		expect(not detail.visible, kind + " omits subpixel detail at wide zoom")
		camera.size = 15
		detail.refresh_visibility()
		expect(detail.visible, kind + " restores close detail at readable zoom")
		camera.position = Vector3(0, 0, 80)
		detail.refresh_visibility()
		expect(not detail.visible, kind + " distance culls beyond the close-up budget")
		camera.position = Vector3(4, 3, 6)
		pawn.free()
	stage.free()
	print("DINOSAUR DETAIL: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
