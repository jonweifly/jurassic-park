extends RefCounted
## Visual-only tower replacement. Cell collision, combat stats and save schema stay in Session.
const SCENES = {
	"": preload("res://assets/models/tower.glb"),
	"range": preload("res://assets/models/tower_range.glb"),
	"rapid": preload("res://assets/models/tower_rapid.glb"),
	"heavy": preload("res://assets/models/tower_heavy.glb"),
}

static func update(scenery: RefCounted, node: Node3D, data: Dictionary) -> void:
	var variant: String = data.get("refit", "") if data.remaining <= 0 else ""
	if not SCENES.has(variant): variant = ""
	if node.get_meta("tower_variant", "") != variant:
		var old: Node3D = node.get_node("Model")
		var yaw: float = old.get_node("Gun").rotation.y
		node.remove_child(old)
		old.free()
		var model: Node3D = SCENES[variant].instantiate()
		model.name = "Model"
		node.add_child(model)
		model.get_node("Gun").rotation.y = yaw
		node.set_meta("tower_variant", variant)
		scenery.polish_building_materials(model, "tower")
		scenery.world.vision.shade(model)
		scenery.obstructions.register(model)
	var recoil: Node3D = node.get_node_or_null("Model/Gun/Recoil")
	if recoil:
		var elapsed: float = scenery.clock - node.get_meta("tower_shot_time", -100.0)
		var distance := 0.18 if variant == "heavy" else 0.085
		recoil.position.z = -distance * pow(maxf(0.0, 1.0 - elapsed / 0.22), 2.0)

static func fire(node: Node3D, clock: float) -> Vector3:
	var gun: Node3D = node.get_node("Model/Gun")
	var name := "Muzzle"
	if node.get_meta("tower_variant", "") == "rapid":
		var right: bool = not node.get_meta("tower_right_barrel", false)
		node.set_meta("tower_right_barrel", right)
		if right: name = "MuzzleRight"
	var muzzle: Node3D = gun.get_node_or_null("Recoil/" + name)
	node.set_meta("tower_shot_time", clock)
	return muzzle.global_position if muzzle else gun.to_global(Vector3(0, 0.22, 0.60))
