extends SceneTree
var stage: Node3D
var camera: Camera3D
var actors: Array[Node3D] = []
func _initialize() -> void: call_deferred("run")
func add_asset(title: String, at: Vector3, yaw: float = 0) -> Node3D:
 var path := "res://scenes/models/%s.tscn" % title
 var n: Node3D = load(path).instantiate()
 stage.add_child(n)
 n.position = at
 n.rotation.y = yaw
 if title in ["survivor","raptor","trex"]:
  n.health_label.hide()
  n.selection.hide()
  n.visual.play("idle",0.1)
  actors.append(n)
 return n
func shot(title: String, at: Vector3, target: Vector3, size: float) -> void:
 camera.position = at
 camera.look_at(target)
 camera.size = size
 for i in range(4): await process_frame
 RenderingServer.force_draw(false)
 root.get_texture().get_image().save_png("res://captures/delivery/%s.png" % title)
 print("CAPTURE ",title)
func run() -> void:
 root.size = Vector2i(1440,1000)
 stage = Node3D.new()
 root.add_child(stage)
 var env := WorldEnvironment.new()
 env.environment = Environment.new()
 env.environment.background_mode = Environment.BG_COLOR
 env.environment.background_color = Color("263c40")
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color("b1ccd1")
 env.environment.ambient_light_energy = 0.32
 env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 stage.add_child(env)
 var sun := DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-48,-38,0)
 sun.light_color = Color("ffdfac")
 sun.light_energy = 0.8
 sun.shadow_enabled = true
 sun.directional_shadow_max_distance = 35
 sun.shadow_bias = .08
 sun.shadow_normal_bias = .35
 stage.add_child(sun)
 var fill := DirectionalLight3D.new()
 fill.rotation_degrees = Vector3(-25,140,0)
 fill.light_color = Color("a2b7ca")
 fill.light_energy = 0.16
 stage.add_child(fill)
 var floor := MeshInstance3D.new()
 var plane := PlaneMesh.new()
 plane.size = Vector2(200,200)
 var mat := StandardMaterial3D.new()
 mat.albedo_color = Color("4b5746")
 mat.roughness = 1
 plane.material = mat
 floor.mesh = plane
 floor.position.y = -0.016
 stage.add_child(floor)
 camera = Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 stage.add_child(camera)
 var human := add_asset("survivor",Vector3.ZERO)
 if "--motion" in OS.get_cmdline_user_args():
  root.size = Vector2i(900,720)
  for clip in ["walk","chop","carry"]:
   human.visual.show_equipment(clip,clip == "carry","wood")
   human.visual.player.play(clip,0)
   for frame in range(27):
    human.visual.player.seek(float(frame)/27*human.visual.player.get_animation(clip).length,true)
    await shot("motion-%s-%02d" % [clip,frame],Vector3(3,2.3,5),Vector3(0,1.25,0),3.5)
  human.hide()
  var actor := add_asset("raptor",Vector3.ZERO)
  actor.visual.player.play("walk",0)
  for frame in range(24):
   actor.visual.player.seek(float(frame)/24*.8,true)
   await shot("motion-raptor-%02d" % frame,Vector3(5,2.8,6),Vector3(0,1,-.45),4.7)
  stage.queue_free()
  await process_frame
  quit()
  return
 await shot("survivor",Vector3(3,2.3,5),Vector3(0,1,0),2.75)
 human.visual.show_equipment("chop",false,"")
 human.visual.seek_work("chop",0.85,0.1)
 await shot("chop-windup",Vector3(3,2.3,5),Vector3(0,1.25,0),3.5)
 human.visual.seek_work("chop",1.10,0.1)
 await shot("chop-impact",Vector3(3,2.3,5),Vector3(0,1.25,0),3.5)
 human.hide()
 var raptor := add_asset("raptor",Vector3.ZERO)
 await shot("raptor",Vector3(5,2.8,6),Vector3(0,1,-.45),4.7)
 raptor.visual.play("attack",.32)
 await shot("raptor-attack",Vector3(5,2.8,6),Vector3(0,1,-.45),4.7)
 raptor.hide()
 var rex := add_asset("trex",Vector3.ZERO)
 await shot("trex",Vector3(5,2.8,6),Vector3(0,1,-.45),4.7)
 rex.hide()
 var tree := add_asset("broadleaf",Vector3.ZERO)
 await shot("broadleaf",Vector3(7,5,8),Vector3(0,2.2,0),6.2)
 tree.hide()
 var tent := add_asset("tent",Vector3.ZERO)
 await shot("tent",Vector3(3,2.5,4),Vector3(0,.8,0),3.2)
 tent.hide()
 # Independent inspection scene, using the exact runtime assets and materials.
 human.show()
 human.position = Vector3(0,0,1.6)
 human.visual.play("idle",.1)
 human.visual.show_equipment("idle",false,"")
 tree.show()
 tree.position = Vector3(-3,0,-2.8)
 tent.show()
 tent.position = Vector3(-1.7,0,0)
 add_asset("lab",Vector3(1,0,-2.0))
 add_asset("generator",Vector3(3.1,0,-.4),-.35)
 add_asset("tower",Vector3(3,0,-3.1))
 add_asset("fire",Vector3(.1,0,3.1))
 add_asset("gate",Vector3(3,0,2),PI/2)
 add_asset("shelter",Vector3(3,0,3.8),PI/2)
 add_asset("rock",Vector3(-3,0,2.7))
 add_asset("fossil",Vector3(4.6,0,1))
 for i in range(8):
  var a := i*TAU/8
  add_asset("fern",Vector3(cos(a)*4.8,0,sin(a)*4.8),a)
 add_asset("broadleaf",Vector3(-4,0,1))
 add_asset("tree",Vector3(4,0,-5))
 raptor.show()
 raptor.position = Vector3(-3.1,0,5)
 raptor.rotation.y = 1.6
 raptor.visual.play("idle",0.1)
 await shot("camp-gallery",Vector3(10,10,14),Vector3(0,1,0),13.5)
 sun.light_energy = .23
 fill.light_energy = .17
 env.environment.ambient_light_energy = .25
 await shot("camp-gallery-night",Vector3(10,10,14),Vector3(0,1,0),13.5)
 stage.queue_free()
 await process_frame
 quit()
