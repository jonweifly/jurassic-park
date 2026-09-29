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
	ensure_recoil(node)
	var recoil: Node3D = node.get_node_or_null("Model/Gun/Recoil")
	if recoil:
		var elapsed: float = scenery.clock - node.get_meta("tower_shot_time", -100.0)
		var distance := 0.18 if variant == "heavy" else 0.085
		var kick := pow(maxf(0.0, 1.0 - elapsed / 0.22), 2.0)
		recoil.position.z = -distance * kick
		recoil.rotation.x = (0.045 if variant == "heavy" else 0.025) * kick

static func ensure_recoil(node: Node3D) -> void:
	# The original tower predates the specialist models' articulated weapon roots.
	# Give it the same firing feedback without changing its gun pivot or saved state.
	var gun: Node3D = node.get_node("Model/Gun")
	if gun.has_node("Recoil"): return
	var recoil := Node3D.new()
	recoil.name = "Recoil"
	var parts := gun.get_children()
	gun.add_child(recoil)
	for part in parts:
		gun.remove_child(part)
		recoil.add_child(part)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, .24, .87)
	recoil.add_child(muzzle)

static func fire(node: Node3D, clock: float) -> Vector3:
	ensure_recoil(node)
	var gun: Node3D = node.get_node("Model/Gun")
	var name := "Muzzle"
	if node.get_meta("tower_variant", "") == "rapid":
		var right: bool = not node.get_meta("tower_right_barrel", false)
		node.set_meta("tower_right_barrel", right)
		if right: name = "MuzzleRight"
	var muzzle: Node3D = gun.get_node_or_null("Recoil/" + name)
	node.set_meta("tower_shot_time", clock)
	return muzzle.global_position if muzzle else gun.to_global(Vector3(0, 0.22, 0.60))
