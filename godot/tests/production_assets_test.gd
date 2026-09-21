extends SceneTree
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 for title in ["survivor","raptor","trex"]:
  var pawn: Node3D = load("res://scenes/models/%s.tscn" % title).instantiate()
  root.add_child(pawn)
  var skeleton: Skeleton3D = pawn.get_node("Model/Rig/Skeleton3D")
  var meshes := skeleton.find_children("*","MeshInstance3D",true,false).filter(func(mesh): return mesh.skin != null)
  expect(skeleton.get_bone_count() >= (16 if title == "survivor" else 20),title+" must use an articulated skeleton")
  expect(meshes.size() == 1 and meshes[0].skin != null,title+" must use a weighted surface mesh")
  expect(meshes[0].mesh.surface_get_material(0) == load("res://assets/materials/expedition.tres"),title+" must reuse the production PBR material")
  var player: AnimationPlayer = pawn.visual.player
  for clip in (["idle","walk","attack","death","chop","mine","build","carry","carry_idle"] if title == "survivor" else ["idle","walk","attack","death"]):
   expect(player.has_animation(clip),title+" missing action "+clip)
  expect(player.get_animation("walk").loop_mode == Animation.LOOP_LINEAR,title+" locomotion must loop")
  expect(player.get_animation("death").loop_mode == Animation.LOOP_NONE,title+" death must stop at its final pose")
  player.play("walk",0)
  player.seek(.10,true)
  var first := skeleton.get_bone_global_pose(skeleton.find_bone("footR"))
  player.seek(.50,true)
  expect(first.origin.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone("footR")).origin) > .12,title+" walk must deform the actual foot bone")
  var surface_planted := true
  var planted := true
  var joined := true
  for frame in range(25):
   player.seek(float(frame)/30,true)
   if frame % 6 == 0:
    var floor_y := deformed_floor(meshes[0],skeleton)
    surface_planted = surface_planted and floor_y > -.025 and floor_y < .035
   var lowest := INF
   for side in ["L","R"]:
    var ankle := skeleton.get_bone_global_pose(skeleton.find_bone("foot"+side)).origin
    lowest = minf(lowest,ankle.y)
    var shin := skeleton.get_bone_global_pose(skeleton.find_bone("shin"+side))
    var rest := skeleton.get_bone_rest(skeleton.find_bone("foot"+side)).origin
    joined = joined and (shin*rest).distance_to(ankle) < .035
   planted = planted and absf(lowest - (0.146 if title == "survivor" else 0.336)) < .035
  expect(surface_planted,title+" deformed skin must physically contact the ground throughout locomotion")
  expect(planted,title+" must retain a support foot throughout the complete locomotion cycle")
  expect(joined,title+" feet must remain connected to lower legs through every locomotion frame")
  if title == "survivor":
   pawn.work_pose("chop",Vector3(0,0,2),.85,.1)
   await process_frame
   await process_frame
   var raised: Vector3 = pawn.visual.axe.global_position
   pawn.work_pose("chop",Vector3(0,0,2),1.1,.1)
   await process_frame
   await process_frame
   expect(raised.distance_to(pawn.visual.axe.global_position) > .25,"Tool socket must follow the rendered hand across contact, not just change a pose value")
   expect(pawn.visual.axe.global_position.y > .5 and pawn.visual.axe.global_position.y < 2.5,"Work tool must remain attached at human hand height")
   expect(pawn.visual.axe.find_children("*","MeshInstance3D",true,false).size() > 0,"Independent axe GLB must be connected")
   pawn.carrying = true
   pawn.cargo_kind = "wood"
   pawn.advance(.2)
   await process_frame
   await process_frame
   expect(pawn.visual.bundle.visible and pawn.visual.bundle.global_position.y > .7,"Cargo must follow the chest skeleton socket")
  else:
   player.play("attack",0)
   player.seek(.32,true)
   var jaw := skeleton.get_bone_pose_rotation(skeleton.find_bone("jaw"))
   player.play("idle",0)
   player.seek(0,true)
   expect(jaw.angle_to(skeleton.get_bone_pose_rotation(skeleton.find_bone("jaw"))) > .3,title+" bite must articulate the mandible")
  pawn.free()
 var world = load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 world.set_process(false)
 world.set_physics_process(false)
 world.sound.set_process(false)
 var forest: RefCounted = world.scenery.forest
 expect(forest.batches.all(func(b): return b.low != null and b.low != b.high),"Every tree batch must have a distinct authored LOD")
 forest.update_lod(world.hero.position,68)
 expect(forest.batches.all(func(b): return b.multi.mesh == b.low),"Wide view must switch to authored lower geometry")
 forest.update_lod(world.hero.position,18)
 expect(forest.batches.any(func(b): return b.multi.mesh == b.high),"Close view must restore detailed branches and leaves")
 var hidden_ok := true
 for batch in forest.batches:
  if batch.multi.visible_instance_count == 0: hidden_ok = hidden_ok and not batch.node.visible
 expect(hidden_ok,"LOD updates must not resurrect empty harvested batches")
 expect(world.get_node("Island/GroundCover").find_children("*Ferns*","MultiMeshInstance3D",true,false).size() > 0,"Authored ferns must be present on the playable map")
 world.queue_free()
 await process_frame
 print("PRODUCTION ASSETS: ",checks," checks, ",failures," failures")
 quit(0 if failures == 0 else 1)

func deformed_floor(mesh: MeshInstance3D, skeleton: Skeleton3D) -> float:
 var arrays := mesh.mesh.surface_get_arrays(0)
 var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
 var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
 var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
 var stride: int = weights.size() / vertices.size()
 var transforms: Array[Transform3D] = []
 for i in range(mesh.skin.get_bind_count()):
  var bone := skeleton.find_bone(mesh.skin.get_bind_name(i))
  transforms.append(skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(i))
 var lowest := INF
 for i in range(vertices.size()):
  var point := Vector3.ZERO
  for j in range(stride): point += (transforms[joints[i*stride+j]]*vertices[i])*weights[i*stride+j]
  lowest = minf(lowest,point.y)
 return lowest
