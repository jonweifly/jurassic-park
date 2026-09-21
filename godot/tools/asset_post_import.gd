@tool
extends EditorScenePostImport
## One runtime PBR material shared by all authored meshes, native import LODs retained.
func _post_import(scene: Node) -> Object:
 style(scene)
 var animators := scene.find_children("*","AnimationPlayer",true,false)
 for player in animators:
  for clip in player.get_animation_list():
   player.get_animation(clip).loop_mode = Animation.LOOP_NONE if clip in ["death","attack","chop","mine","build"] else Animation.LOOP_LINEAR
 return scene
func style(node: Node) -> void:
 if node is MeshInstance3D:
  for i in range(node.mesh.get_surface_count()):
   var mat: Material = node.mesh.surface_get_material(i)
   if mat and "Expedition" in mat.resource_name:
    node.mesh.surface_set_material(i,load("res://assets/materials/expedition.tres"))
   elif mat is StandardMaterial3D:
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.vertex_color_use_as_albedo = true
 if node is AnimationPlayer: node.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 for child in node.get_children(): style(child)
