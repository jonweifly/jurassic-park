extends RefCounted
## Bounded render-only correction for the production survivor rig. No resource events here.
var visual: Node
var skeleton: Skeleton3D
var bones := {}

func _init(owner_visual: Node, rig: Skeleton3D) -> void:
	visual = owner_visual
	skeleton = rig
	for name in ["root", "spine", "neck", "head", "thighL", "shinL", "footL", "thighR", "shinR", "footR", "upper_armL", "forearmL", "upper_armR", "forearmR", "handR"]:
		bones[name] = skeleton.find_bone(name)

func ready() -> bool:
	return not bones.values().has(-1)

func clear() -> void:
	skeleton.clear_bones_global_pose_override()

func pose(name: String) -> Transform3D:
	return skeleton.get_bone_global_pose(bones[name])

func override_pose(name: String, value: Transform3D) -> void:
	skeleton.set_bone_global_pose_override(bones[name], value, 1.0, true)
	skeleton.force_update_all_bone_transforms()

func rotate_towards(basis: Basis, from: Vector3, to: Vector3) -> Basis:
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001: return basis
	var from_axis := from.normalized()
	var to_axis := to.normalized()
	var cross_axis := from_axis.cross(to_axis)
	var sine := cross_axis.length()
	# Quaternion(from, to) rounds very small arcs to identity. Those arcs matter
	# when retaining a foot joint after a subtle pelvis shift every render tick.
	if sine > 0.000001:
		return Basis(Quaternion(cross_axis / sine, atan2(sine, clampf(from_axis.dot(to_axis), -1.0, 1.0)))) * basis
	return Basis(Quaternion(from_axis, to_axis)) * basis

func solve(upper: String, lower: String, end: String, target: Vector3, end_basis: Basis) -> void:
	var a := pose(upper)
	var b := pose(lower)
	var c := pose(end)
	# Imported IK keys can contain millimetres of translation in the foot joint.
	# Solving from those animated distances would retain that stretch each frame.
	var upper_link := skeleton.get_bone_rest(bones[lower]).origin
	var lower_link := skeleton.get_bone_rest(bones[end]).origin
	var l1 := upper_link.length()
	var l2 := lower_link.length()
	var axis := (target - a.origin).normalized()
	var distance := clampf(a.origin.distance_to(target), absf(l1 - l2) + 0.002, l1 + l2 - 0.002)
	var bend := b.origin - a.origin
	# A straight imported leg has no reliable bend plane. Pelvis motion can
	# flip the tiny authored offset backward; human knees need a forward pole.
	if upper.begins_with("thigh"): bend = pose("root").basis.z
	bend -= axis * bend.dot(axis)
	if bend.length() < 0.0001: bend = Vector3.FORWARD - axis * Vector3.FORWARD.dot(axis)
	bend = bend.normalized()
	var along := (l1*l1 + distance*distance - l2*l2) / (2.0*distance)
	var knee := a.origin + axis * along + bend * sqrt(maxf(0, l1*l1 - along*along))
	var ankle := a.origin + axis * distance
	a.basis = rotate_towards(a.basis, a.basis * upper_link, knee - a.origin)
	b.origin = knee
	b.basis = rotate_towards(b.basis, b.basis * lower_link, ankle - knee)
	c.origin = ankle
	c.basis = end_basis
	override_pose(upper, a)
	override_pose(lower, b)
	override_pose(end, c)

func ground(layout: RefCounted) -> void:
	if not layout: return
	var pawn: Node3D = visual.get_parent()
	var lower := 0.0
	for side in ["L", "R"]:
		var at := skeleton.to_global(pose("foot" + side).origin)
		lower = minf(lower, layout.height_at(at.x, at.z) - pawn.position.y)
	# Lower the visual pelvis slightly so the downhill leg can reach without stretching.
	visual.model.position.y = clampf(lower, -0.12, 0.0)
	for side in ["L", "R"]:
		var foot := pose("foot" + side)
		var world_foot := skeleton.to_global(foot.origin)
		# Preserve authored swing lift; add only terrain height relative to the root.
		var delta: float = clampf(layout.height_at(world_foot.x, world_foot.z) - pawn.position.y - visual.model.position.y, -0.16, 0.16)
		if absf(delta) < 0.001: continue
		var target := skeleton.to_local(world_foot + Vector3.UP * delta)
		var epsilon := 0.16
		var dx: float = layout.height_at(world_foot.x + epsilon, world_foot.z) - layout.height_at(world_foot.x - epsilon, world_foot.z)
		var dz: float = layout.height_at(world_foot.x, world_foot.z + epsilon) - layout.height_at(world_foot.x, world_foot.z - epsilon)
		var normal := Vector3(-dx, epsilon * 2, -dz).normalized()
		var local_normal := skeleton.global_basis.inverse() * normal
		var tilt := Quaternion(Vector3.UP, local_normal)
		var angle := tilt.get_angle()
		if angle > 0.3: tilt = Quaternion.IDENTITY.slerp(tilt, 0.3 / angle)
		var planted := 1.0 - smoothstep(0.18, 0.28, foot.origin.y)
		var basis := Basis(Quaternion.IDENTITY.slerp(tilt, planted)) * foot.basis
		solve("thigh" + side, "shin" + side, "foot" + side, target, basis)

func tool_transform(action: String) -> Transform3D:
	var prop: Node3D = (visual.chainsaw if visual.saw_equipped else visual.axe) if action == "chop" else (visual.pickaxe if action == "mine" else visual.hammer)
	var grip: Node3D = visual.get_node(visual.hand_socket_path)
	return grip.transform * prop.transform

func tip_offset(action: String) -> Vector3:
	var point := Vector3(0, 0, 0.88) if visual.saw_equipped else Vector3(0.34, 0, 0.70)
	if action == "mine": point = Vector3(0.35, -0.03, 0.53)
	if action == "build": point = Vector3(0, 0, 0.65)
	return tool_transform(action) * point

func tip(action: String) -> Vector3:
	return skeleton.to_global(pose("handR") * tip_offset(action))

func work(action: String, target: Vector3, phase: float) -> void:
	if action not in ["chop", "mine", "build"]: return
	var contact_time := 0.65 if action == "build" else 1.1
	var weight := smoothstep(contact_time - 0.28, contact_time - 0.02, phase) * (1.0 - smoothstep(contact_time + 0.04, contact_time + 0.25, phase))
	if weight <= 0: return
	var pawn: Node3D = visual.get_parent()
	var direction := target - pawn.global_position
	direction.y = 0
	if direction.length() < 0.1: return
	var surface_radius := 0.30 if action == "chop" else (0.65 if action == "mine" else 0.85)
	var height := 1.25 if action == "chop" else (0.34 if action == "mine" else 1.15)
	var contact := skeleton.to_local(target - direction.normalized() * surface_radius + Vector3.UP * height)
	if action == "mine":
		var spine := pose("spine")
		spine.basis = Basis(Vector3.RIGHT, 0.45 * weight) * spine.basis
		override_pose("spine", spine)
	var hand := pose("handR")
	var offset := hand.basis * tip_offset(action)
	var desired := contact - hand.origin
	var rotation := Quaternion(offset.normalized(), desired.normalized())
	var angle := rotation.get_angle()
	var max_angle := 1.5 if action == "mine" else 0.85
	if angle > max_angle: rotation = Quaternion.IDENTITY.slerp(rotation, max_angle / angle)
	rotation = Quaternion.IDENTITY.slerp(rotation, weight)
	var basis := Basis(rotation) * hand.basis
	var wrist := contact - basis * tip_offset(action)
	# An unreachable target never stretches limbs or teleports the gameplay root.
	wrist = hand.origin + (wrist - hand.origin).limit_length(0.30 if action == "mine" else 0.22) * weight
	solve("upper_armR", "forearmR", "handR", wrist, basis)
