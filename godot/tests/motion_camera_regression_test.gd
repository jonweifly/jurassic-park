extends SceneTree
var failures := 0
var checks := 0
class FlatGround extends RefCounted:
	func height_at(_x: float, _z: float) -> float: return 0.0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var pawn: Node3D = load("res://scenes/models/survivor.tscn").instantiate()
	root.add_child(pawn)
	pawn.navigation = load("res://scripts/board.gd").new()
	pawn.navigation.layout = FlatGround.new()
	var minimum := 1.0
	for action in ["walk", "idle", "chop", "mine", "build"]:
		for frame in range(90):
			if action in ["walk", "idle"]:
				pawn.route = PackedVector3Array([pawn.position + Vector3(0,0,5)]) if action == "walk" else PackedVector3Array()
				pawn.advance(1.0/60)
			else: pawn.work_pose(action, pawn.position + Vector3(0,0,1.5), frame/90.0 * (0.9 if action == "build" else 1.35), 1.0/60)
			var contact: RefCounted = pawn.visual.contact
			for side in ["L", "R"]:
				var hip: Vector3 = contact.pose("thigh"+side).origin
				var knee: Vector3 = contact.pose("shin"+side).origin
				var ankle: Vector3 = contact.pose("foot"+side).origin
				var axis := (ankle-hip).normalized()
				var bend := knee-hip-axis*(knee-hip).dot(axis)
				minimum = minf(minimum, bend.dot(Vector3.BACK))
	print("KNEE minimum forward bend: ",minimum)
	expect(minimum >= -0.002, "Human knees bend toward the survivor's facing direction throughout movement and work")
	pawn.free()
	var w: Node = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.start_session(1500,"standard")
	w.paused = true
	w.preferences.values.perspective = true
	w.preferences.values.impact_motion = false
	w.camera_rig.center(false)
	w.camera_size = 36
	w.update_camera(0)
	var maximum_tilt := 0.0
	var initial: Vector3 = w.camera.global_basis.z
	for target in [18.0, 68.0, 24.0, 36.0]:
		w.camera_size = target
		for frame in range(90):
			w.update_camera(1.0/60)
			maximum_tilt = maxf(maximum_tilt, initial.angle_to(w.camera.global_basis.z))
	print("ZOOM maximum unintended tilt degrees: ",rad_to_deg(maximum_tilt))
	expect(maximum_tilt < 0.002, "Zoom on unobstructed ground cannot rock the camera's pitch")
	w.camera_rig.center(false)
	w.camera_focus += Vector3(8,0,0)
	w.camera_size = 25
	w.update_camera(0)
	var focus: Vector3 = w.camera_focus
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	w.camera_rig.handle(wheel)
	w.update_camera(0.02)
	expect(not w.camera_rig.following and w.camera_focus.distance_to(focus) < 0.001, "Zooming through the close-view threshold must not recenter a free camera")
	w.free()
	print("MOTION CAMERA: ", checks," checks, ",failures," failures")
	quit(1 if failures else 0)
