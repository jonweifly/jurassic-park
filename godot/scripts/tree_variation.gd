extends RefCounted
## Replace only visual children; source tree node, wood amount, cell and collision stay intact.
const FAMILIES := ["canopy_tree","split_tree","palm_tree","wind_pine"]
var counts := {}
var cinematic_enabled := false
func _init(world: Node, use_cinematic: bool = false) -> void:
	cinematic_enabled = use_cinematic and "--original-environment" not in OS.get_cmdline_user_args()
	if "--original-environment" in OS.get_cmdline_user_args(): return
	var scenes := {}
	for family in FAMILIES: scenes[family] = load("res://assets/models/%s.glb" % family)
	if cinematic_enabled: scenes["cinematic_tree"] = load("res://assets/cinematic/gameplay/rainforest_tree.glb")
	for cell in world.trees:
		var tree: Node3D = world.trees[cell].node
		var region: String = world.Regions.at(tree.position)
		var value: int = posmod(cell.x*1973+cell.y*9277+cell.x*cell.y*17,101)
		var family := ""
		if region == "ice": continue
		if region == "mountain": family = "wind_pine" if value < 48 else ""
		elif region == "swamp": family = "palm_tree" if value < 30 else ("split_tree" if value < 62 else "")
		else: family = "canopy_tree" if value < 34 else ("split_tree" if value < 64 else ("palm_tree" if value < 77 else ""))
		if cinematic_enabled and region != "mountain" and family != "palm_tree": family = "cinematic_tree"
		if family.is_empty(): continue
		var holders: Array[Node] = [tree] if tree.has_node("Model") else tree.get_children()
		for holder in holders:
			var old := holder.get_node_or_null("Model")
			if not old: continue
			old.free()
			var model: Node3D = scenes[family].instantiate()
			model.name = "Model"
			var tall := 0.88+float(value%17)*0.012
			model.scale = Vector3(0.90+float(value%7)*.022,tall,0.93+float(value%9)*.015)
			model.rotation.y = float(value+holder.get_index()*13)*2.399
			holder.add_child(model)
			world.vision.shade(model)
			tree.set_meta("visual_family",family)
			counts[family] = counts.get(family,0)+1
