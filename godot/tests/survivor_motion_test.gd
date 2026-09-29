extends SceneTree
const Pawn = preload("res://scenes/models/survivor.tscn")
const Board = preload("res://scripts/board.gd")
var checks := 0
var failures := 0

class FlatGround extends RefCounted:
	func height_at(_x: float, _z: float) -> float: return 0.0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void: call_deferred("run")

func make_pawn() -> Node3D:
	var pawn := Pawn.instantiate()
	root.add_child(pawn)
	pawn.navigation = Board.new()
	pawn.navigation.layout = FlatGround.new()
	return pawn

func run() -> void:
	var pawn := make_pawn()
	var raw := make_pawn()
	var contact: RefCounted = pawn.visual.contact
	expect(pawn.visual.motion != null, "Production survivor receives the additive motion layer")
	pawn.route = PackedVector3Array([Vector3(0, 0, 12)])
	var support := true
	var joined := true
	var moving_hips := false
	for frame in range(45):
		pawn.advance(1.0 / 60.0)
		raw.visual.play("walk", 0)
		raw.visual.player.seek(pawn.visual.player.current_animation_position, true)
		moving_hips = moving_hips or absf(contact.pose("root").origin.x - raw.visual.contact.pose("root").origin.x) > 0.01
		var lowest := INF
		for side in ["L", "R"]:
			var foot: Transform3D = contact.pose("foot" + side)
			lowest = minf(lowest, foot.origin.y)
			var rest: Vector3 = contact.skeleton.get_bone_rest(contact.bones["foot" + side]).origin
			var gap: float = (contact.pose("shin" + side) * rest).distance_to(foot.origin)
			joined = joined and gap < 0.001
			if gap >= 0.001:
				var original_gap: float = (raw.visual.contact.pose("shin" + side) * rest).distance_to(raw.visual.contact.pose("foot" + side).origin)
				print("STRIDE_JOIN frame=", frame, " side=", side, " gap=", gap, " authored_gap=", original_gap, " foot=", foot.origin)
		support = support and absf(lowest - 0.146) < 0.035
		if absf(lowest - 0.146) >= 0.035: print("STRIDE_SUPPORT frame=", frame, " lowest=", lowest)
	expect(moving_hips, "Walking weight transfers sideways across the actual pelvis")
	expect(support and joined, "Weight transfer preserves planted support and connected legs throughout a stride")
	pawn.route = PackedVector3Array([pawn.position + Vector3(8, 0, 0)])
	for frame in range(5): pawn.advance(1.0 / 60.0)
	expect(absf(pawn.visual.motion.bank) > 0.015 and absf(pawn.visual.motion.bank) <= 0.10, "Turning creates a bounded body bank")
	pawn.route.clear()
	for frame in range(60): pawn.advance(1.0 / 60.0)
	expect(pawn.visual.motion.gait_weight < 0.001 and absf(pawn.visual.motion.bank) < 0.001, "Stopping settles movement and turn lean instead of freezing the last step")
	pawn.position = Vector3.ZERO
	pawn.visual.model.rotation.y = 0.0
	for fixture in [["chop", 1.34, 1.1, Vector3(0, 1.25, 1.04)], ["mine", 1.5, 1.1, Vector3(0, 0.34, 0.85)], ["build", 1.7, 0.65, Vector3(0, 1.15, 0.85)]]:
		var action: String = fixture[0]
		var windup := 0.48 if action == "build" else 0.85
		pawn.work_pose(action, Vector3(0, 0, fixture[1]), windup, 0.1)
		raw.visual.play(action, 0)
		raw.visual.player.seek(windup, true)
		var authored: Basis = raw.visual.contact.pose("spine").basis
		expect(contact.pose("spine").basis.get_rotation_quaternion().angle_to(authored.get_rotation_quaternion()) > 0.07, action + " has a visible torso windup in addition to the arm clip")
		pawn.work_pose(action, Vector3(0, 0, fixture[1]), fixture[2], 0.1)
		var first: Vector3 = pawn.visual.work_tip()
		expect(first.distance_to(fixture[3]) < 0.12, action + " retains the original work contact frame and surface")
		pawn.work_pose(action, Vector3(0, 0, fixture[1]), fixture[2], 0.1)
		expect(pawn.visual.work_tip().distance_to(first) < 0.001, action + " poses do not accumulate additive offsets when reevaluated")
	pawn.health = 0
	pawn.advance(0.1)
	expect(pawn.animation_state == "death" and not pawn.visual.axe.visible and not pawn.visual.hammer.visible, "Death releases the additive work pose and equipment")
	pawn.free()
	raw.free()
	print("SURVIVOR MOTION: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
