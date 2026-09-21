extends SceneTree
func _initialize() -> void:
 for title in ["survivor","raptor","tent","gate","tower"]:
  var model = load("res://assets/models/%s.glb" % title).instantiate()
  print("ASSET ",title)
  walk(model,"")
  model.free()
 quit()
func walk(node: Node, prefix: String) -> void:
 print(prefix,node.name," ",node.get_class())
 if node is MeshInstance3D: print(" BOUNDS ",node.mesh.get_aabb()," SKIN ",node.skin)
 if node is AnimationPlayer: print(" CLIPS ",node.get_animation_list())
 if node is Skeleton3D:
  for i in range(node.get_bone_count()): print(" BONE ",i," ",node.get_bone_name(i))
 for child in node.get_children(): walk(child,prefix+"  ")
