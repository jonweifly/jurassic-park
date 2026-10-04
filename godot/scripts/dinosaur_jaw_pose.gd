extends SkeletonModifier3D
## The authored mandible bone points forward. Its exported local-X bite track
## pitches into the snout; mirror that pitch for a downward anatomical opening.
## SkeletonModifier3D restores the animation pose after rendering, so the change
## cannot accumulate or alter saved animation / gameplay timing.
var jaw_index := -1

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if not skeleton: return
	if jaw_index < 0: jaw_index = skeleton.find_bone("jaw")
	if jaw_index < 0: return
	var rest_rotation := skeleton.get_bone_rest(jaw_index).basis.get_rotation_quaternion()
	var rotation := rest_rotation.inverse() * skeleton.get_bone_pose_rotation(jaw_index)
	var corrected := Quaternion(-rotation.x, rotation.y, rotation.z, rotation.w)
	skeleton.set_bone_pose_rotation(jaw_index, rest_rotation * corrected)
