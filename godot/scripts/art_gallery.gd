extends Node3D
## Runtime asset review scene. No dependency on gameplay state or save files.
const ASSETS := ["survivor","raptor","trex","broadleaf","tent","tree","snow_tree","fern","rock","generator","tower","lab","gate","shelter","fire","fossil"]
var model: Node3D
var camera: Camera3D
var actions: OptionButton
var yaw := 0.45
var zoom := 5.5
var dragging := false
var active_action := "idle"
var time := 0.0
func _ready() -> void:
 var env := WorldEnvironment.new()
 env.environment = Environment.new()
 env.environment.background_mode = Environment.BG_COLOR
 env.environment.background_color = Color("1b2b2d")
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color("b1ccd1")
 env.environment.ambient_light_energy = .35
 add_child(env)
 var sun := DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-48,-38,0)
 sun.light_color = Color("ffe2b9")
 sun.light_energy = .85
 sun.shadow_enabled = true
 sun.shadow_bias = .08
 sun.shadow_normal_bias = .35
 sun.directional_shadow_max_distance = 35
 add_child(sun)
 var floor := MeshInstance3D.new()
 var mesh := PlaneMesh.new()
 mesh.size = Vector2(200,200)
 var mat := StandardMaterial3D.new()
 mat.albedo_color = Color("35453d")
 mat.roughness = 1
 mesh.material = mat
 floor.mesh = mesh
 floor.position.y = -.025
 add_child(floor)
 camera = Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 add_child(camera)
 var ui := CanvasLayer.new()
 add_child(ui)
 var panel := HBoxContainer.new()
 panel.position = Vector2(24,24)
 panel.add_theme_constant_override("separation",14)
 ui.add_child(panel)
 var list := OptionButton.new()
 for title in ASSETS: list.add_item(title)
 panel.add_child(list)
 list.item_selected.connect(select_asset)
 actions = OptionButton.new()
 panel.add_child(actions)
 actions.item_selected.connect(func(index):
  active_action = actions.get_item_text(index)
  time = 0
  if model.has_node("Visual"): model.visual.player.play(active_action,0.08))
 var help := Label.new()
 help.text = "拖动旋转 · 滚轮缩放 · 选择动作预览"
 panel.add_child(help)
 select_asset(0)
func select_asset(index: int) -> void:
 if model: model.free()
 model = load("res://scenes/models/%s.tscn" % ASSETS[index]).instantiate()
 add_child(model)
 actions.clear()
 if model.has_node("Visual"):
  model.health_label.hide()
  model.selection.hide()
  for clip in model.visual.player.get_animation_list(): actions.add_item(clip)
  actions.select(actions.get_item_count()-1)
  active_action = "idle"
  for i in range(actions.item_count):
   if actions.get_item_text(i) == active_action: actions.select(i)
  model.visual.player.play("idle",0)
 zoom = 6.3 if "tree" in ASSETS[index] or ASSETS[index] == "broadleaf" else 4.3
 time = 0
func _process(dt: float) -> void:
 if not model: return
 time += dt
 model.rotation.y = yaw
 if model.has_node("Visual"):
  var player: AnimationPlayer = model.visual.player
  if not player.is_playing(): player.play(active_action,0.1)
  player.advance(dt)
  model.visual.show_equipment(active_action,active_action in ["carry","carry_idle"],"wood")
 camera.position = Vector3(4,3.0,7)
 camera.look_at(Vector3(0,1.3,0))
 camera.size = lerpf(camera.size,zoom,1-exp(-8*dt))
func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
  if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom = maxf(2,zoom*.9)
  if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = minf(12,zoom*1.1)
 if event is InputEventMouseMotion and dragging: yaw += event.relative.x*.009
