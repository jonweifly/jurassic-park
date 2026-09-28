extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func assign_owner(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		if child.scene_file_path.is_empty(): assign_owner(child,owner_node)
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Build this scene using the native renderer: headless mode discards MultiMesh buffers.")
		quit(1)
		return
	var builder = load("res://scripts/cinematic_set.gd").new()
	var set: Node3D = builder.build()
	assign_owner(set,set)
	var scene := PackedScene.new()
	var result := scene.pack(set)
	if result != OK:
		push_error("Cannot pack cinematic set: " + str(result))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/cinematic"))
	result = ResourceSaver.save(scene,"res://scenes/cinematic/rainforest_set.tscn")
	print("CINEMATIC SET SAVED ",result)
	set.free()
	quit(0 if result == OK else 1)
