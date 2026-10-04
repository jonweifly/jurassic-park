extends Node3D
## Standalone art sample. Does not load or write game preferences/save data.
const Hud = preload("res://scripts/cinematic_hud.gd")
const SkinShader = preload("res://shaders/cinematic_skin.gdshader")
var night := false
var powered := true
var gate_open := false
var gate_amount := 0.0
var audio_on := false
var paused := false
var view_index := 0
var clock := 0.0
var camera: Camera3D
var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var lights: Array[Light3D] = []
var rain: CPUParticles3D
var hud: CanvasLayer
var gate_left: Node3D
var gate_right: Node3D
var animator: AnimationPlayer
var target_focus := Vector3(0,1.5,-3.5)
var focus := Vector3(0,1.5,-3.5)
var yaw := .59
var pitch := .30
var distance := 32.0
var target_yaw := .59
var target_pitch := .30
var target_distance := 32.0
var dragging := false
var wet_materials: Array[ShaderMaterial] = []
var lamp_materials: Array[StandardMaterial3D] = []
var rain_audio: AudioStreamPlayer
var wind_audio: AudioStreamPlayer
var engine_audio: AudioStreamPlayer3D
var last_capture := ""
var previous_fps := 0
var previous_msaa: int = 0
var previous_auto_quit := true
var previous_title := ""

func _ready() -> void:
	name = "CinematicSample"
	previous_fps = Engine.max_fps
	previous_msaa = get_viewport().msaa_3d
	previous_auto_quit = get_tree().auto_accept_quit
	previous_title = get_window().title
	get_tree().auto_accept_quit = true
	DisplayServer.window_set_title("失落岛屿 · 场景样板")
	Engine.max_fps = 60
	get_viewport().msaa_3d = Viewport.MSAA_4X
	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.fov = 49
	camera.near = .15
	camera.far = 180
	camera.current = true
	add_child(camera)
	setup_environment()
	setup_subjects()
	setup_lights()
	setup_rain()
	setup_audio()
	collect_materials($RainforestSet)
	hud = Hud.new(self)
	add_child(hud)
	set_view(0,true)
	apply_weather()
	for arg in OS.get_cmdline_user_args():
		if arg == "--night": night = true; apply_weather()
		if arg == "--close": set_view(1,true)
		if arg == "--overview": set_view(0,true)
	print("CINEMATIC READY | 1/2/3 views | N weather | G gate | P power")
	get_window().focus_exited.connect(func(): dragging = false)

func _exit_tree() -> void:
	Engine.max_fps = previous_fps
	get_viewport().msaa_3d = previous_msaa
	get_tree().auto_accept_quit = previous_auto_quit
	get_window().title = previous_title

func return_to_menu() -> void:
	var result := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if result != OK: hud.notify("返回菜单失败：" + str(result))

func setup_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "SampleEnvironment"
	env = Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("405a64")
	sky_mat.sky_horizon_color = Color("a7b5ad")
	sky_mat.ground_bottom_color = Color("202d25")
	sky_mat.ground_horizon_color = Color("8b9d91")
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = .95
	env.fog_enabled = true
	env.fog_sky_affect = .3
	env.fog_height = 1.0
	env.fog_height_density = .065
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "CanopyKeyLight"
	sun.rotation_degrees = Vector3(-34,-47,0)
	sun.shadow_enabled = true
	sun.shadow_bias = .04
	sun.shadow_normal_bias = .8
	sun.directional_shadow_max_distance = 100
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.name = "SoftSkyFill"
	fill.rotation_degrees = Vector3(-48,128,0)
	fill.shadow_enabled = false
	add_child(fill)

func setup_subjects() -> void:
	var gate: Node3D = $RainforestSet/Structures/SecurityGate
	gate_left = gate.find_child("GateLeft",true,false)
	gate_right = gate.find_child("GateRight",true,false)
	var rex: Node3D = load("res://assets/cinematic/cinematic_rex.glb").instantiate()
	rex.name = "Tyrannosaur"
	add_child(rex)
	rex.position = Vector3(6.2,.06,-9.5)
	rex.rotation.y = -.62
	var skin := ShaderMaterial.new()
	skin.resource_name = "SampleRexSkin"
	skin.shader = SkinShader
	wet_materials.append(skin)
	for part: MeshInstance3D in rex.find_children("*","MeshInstance3D",true,false):
		for s in range(part.mesh.get_surface_count()):
			var original: Material = part.get_active_material(s)
			if original and ("Skin" in original.resource_name or "Belly" in original.resource_name): part.set_surface_override_material(s,skin)
	var players := rex.find_children("*","AnimationPlayer",true,false)
	if not players.is_empty():
		animator = players[0]
		animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip in animator.get_animation_list():
			if "observe" in clip:
				animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				animator.play(clip)
				animator.advance(0)
	# Native labels are editable signage within the 3D set.
	world_label("SECTOR 07",Vector3(0,4.30,-1.6),.0075,Color("d5c99f"),46)
	world_label("DANGER   /   HIGH VOLTAGE",Vector3(1.67,1.75,-1.79),.0032,Color("e0c28a"),36)
	world_label("FIELD OPERATIONS",Vector3(-10.50,2.50,1.17),.0052,Color("d0c6a8"),34,.20)
	world_label("DIESEL  /  07",Vector3(-5.46,1.48,5.82),.0030,Color("dad4b2"),34,-.18)

func world_label(text: String, at: Vector3, pixel: float, color: Color, font_size: int, yaw_angle: float = 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.pixel_size = pixel
	l.font_size = font_size
	l.modulate = color
	l.outline_size = 0
	l.no_depth_test = false
	l.shaded = true
	l.rotation.y = yaw_angle
	add_child(l)

func spot(label: String, at: Vector3, toward: Vector3, color: Color, energy: float, radius: float, angle: float) -> void:
	var light := SpotLight3D.new()
	light.name = label
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.spot_range = radius
	light.spot_angle = angle
	light.spot_attenuation = .7
	light.shadow_enabled = true
	light.shadow_bias = .03
	light.shadow_normal_bias = .45
	add_child(light)
	light.look_at(toward)
	light.set_meta("sample_energy",energy)
	lights.append(light)

func setup_lights() -> void:
	spot("EntryFloodlight",Vector3(-2.8,4.05,-1.6),Vector3(-1,0,5),Color("ffd39a"),4.3,18,48)
	spot("PaddockFloodlight",Vector3(3,4.14,-2.25),Vector3(6,1.8,-9),Color("dfd6b4"),5.3,23,46)
	spot("GeneratorWorklight",Vector3(-6,3.35,5.8),Vector3(-6,.4,5),Color("ffca87"),3.0,10,66)
	spot("StationPorchlight",Vector3(-11.0,2.65,1.58),Vector3(-10.5,0,4),Color("ffcd90"),2.7,10,58)

func setup_rain() -> void:
	rain = CPUParticles3D.new()
	rain.name = "TropicalRain"
	rain.amount = 1250
	rain.lifetime = 1.65
	rain.preprocess = 1.5
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(25,1,25)
	rain.position = Vector3(0,14,-1)
	rain.direction = Vector3(-.18,-1,.07)
	rain.spread = 2.0
	rain.initial_velocity_min = 13
	rain.initial_velocity_max = 17
	rain.gravity = Vector3(0,-2.4,0)
	var line := BoxMesh.new()
	line.size = Vector3(.009,.38,.009)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(.56,.66,.69,.18)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material = m
	rain.mesh = line
	add_child(rain)

func setup_audio() -> void:
	rain_audio = AudioStreamPlayer.new()
	rain_audio.stream = load("res://assets/audio/rain.wav")
	rain_audio.volume_db = -21
	add_child(rain_audio)
	rain_audio.finished.connect(func(): if audio_on and night and not paused: rain_audio.play())
	wind_audio = AudioStreamPlayer.new()
	wind_audio.stream = load("res://assets/audio/wind_breeze.wav")
	wind_audio.volume_db = -27
	add_child(wind_audio)
	wind_audio.finished.connect(func(): if audio_on and not paused: wind_audio.play())
	engine_audio = AudioStreamPlayer3D.new()
	engine_audio.stream = load("res://assets/audio/generator.wav")
	engine_audio.position = Vector3(-6,1,5)
	engine_audio.unit_size = 9
	engine_audio.volume_db = -22
	add_child(engine_audio)
	engine_audio.finished.connect(func(): if audio_on and powered and not paused: engine_audio.play())

func collect_materials(node: Node) -> void:
	if node is GeometryInstance3D:
		if node.material_override is ShaderMaterial and not wet_materials.has(node.material_override): wet_materials.append(node.material_override)
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(i)
			if material is StandardMaterial3D and "Lamp" in material.resource_name:
				var local := material.duplicate() as StandardMaterial3D
				node.set_surface_override_material(i,local)
				lamp_materials.append(local)
	for child in node.get_children(): collect_materials(child)

func apply_weather() -> void:
	env.ambient_light_color = Color("718f9f") if night else Color("b8c8c1")
	env.ambient_light_energy = .25 if night else .32
	env.fog_light_color = Color("1a3541") if night else Color("748f89")
	env.fog_density = .008 if night else .0035
	env.fog_height_density = 0.0
	sun.light_color = Color("8dabc7") if night else Color("ffdec0")
	sun.light_energy = .28 if night else .92
	fill.light_color = Color("769caa") if night else Color("a1baca")
	fill.light_energy = .10 if night else .14
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	sky_mat.sky_top_color = Color("10202e") if night else Color("4f6b77")
	sky_mat.sky_horizon_color = Color("304d57") if night else Color("a7b7ab")
	sky_mat.ground_horizon_color = Color("253d40") if night else Color("8b9d91")
	rain.visible = night
	rain.emitting = night and not paused
	for m in wet_materials:
		m.set_shader_parameter("wetness",.92 if night else .48)
		if m.shader == load("res://shaders/cinematic_foliage.gdshader"): m.set_shader_parameter("wind_strength",.20 if night else .09)
	apply_power()
	if hud: hud.refresh()
	update_audio()

func apply_power() -> void:
	for light in lights:
		light.visible = powered
		light.light_energy = float(light.get_meta("sample_energy"))*(1.0 if night else .34)
	for m in lamp_materials:
		m.emission_enabled = powered
		m.emission_energy_multiplier = 2.0 if powered else 0.0
	if hud: hud.refresh()
	update_audio()

func toggle_gate() -> void:
	if not powered:
		hud.notify("电源已切断，请先恢复供电")
		return
	gate_open = not gate_open
	hud.refresh()

func toggle_power() -> void:
	powered = not powered
	apply_power()
	hud.notify("围栏与照明已恢复" if powered else "照明熄灭，电门停止移动")

func toggle_weather() -> void:
	night = not night
	apply_weather()

func toggle_audio() -> void:
	audio_on = not audio_on
	update_audio()
	hud.refresh()

func update_audio() -> void:
	if not rain_audio: return
	for pair in [[rain_audio,audio_on and night and not paused],[wind_audio,audio_on and not paused],[engine_audio,audio_on and powered and not paused]]:
		if pair[1] and not pair[0].playing: pair[0].play()
		elif not pair[1]: pair[0].stop()

func set_view(index: int, snap: bool = false) -> void:
	view_index = index
	var views := [
		[Vector3(-2.0,0,-2.0),PI/4,deg_to_rad(52),36.0],
		[Vector3(6.6,2.0,-10.0),1.48,.14,12.0],
		[Vector3(-1.0,1.8,-3.5),.45,.23,30.0]
	]
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if index == 0 else Camera3D.PROJECTION_PERSPECTIVE
	var v: Array = views[index]
	target_focus = v[0]
	target_yaw = v[1]
	target_pitch = v[2]
	target_distance = v[3]
	if snap:
		focus = target_focus
		yaw = target_yaw
		pitch = target_pitch
		distance = target_distance
		update_camera(0)
	if hud: hud.refresh()

func update_camera(dt: float) -> void:
	var blend := 1.0 if dt <= 0 else 1.0-exp(-6.0*dt)
	focus = focus.lerp(target_focus,blend)
	yaw = lerp_angle(yaw,target_yaw,blend)
	pitch = lerpf(pitch,target_pitch,blend)
	distance = lerpf(distance,target_distance,blend)
	var boom := 68.0 if view_index == 0 else distance
	if view_index == 0: camera.size = distance
	camera.position = focus+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*boom
	camera.position.y = maxf(1.15,camera.position.y)
	camera.look_at(focus)

func _process(dt: float) -> void:
	if not paused:
		clock += dt
		if animator: animator.advance(dt)
		if powered: gate_amount = move_toward(gate_amount,1.0 if gate_open else 0.0,dt*.27)
		if gate_left: gate_left.position.x = -3.16*gate_amount
		if gate_right: gate_right.position.x = 3.16*gate_amount
		if DisplayServer.window_is_focused():
			var move := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
			var r := Vector3(cos(yaw),0,-sin(yaw))
			var f := Vector3(sin(yaw),0,cos(yaw))
			target_focus += (r*move.x+f*move.y)*dt*distance*.30
			target_focus.x = clampf(target_focus.x,-19,19)
			target_focus.z = clampf(target_focus.z,-21,15)
	update_camera(dt)
	if hud: hud.refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE: dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: target_distance = maxf(7,target_distance*.90)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: target_distance = minf(55,target_distance*1.10)
	if event is InputEventMouseMotion and dragging:
		target_yaw -= event.relative.x*.005
		target_pitch = clampf(target_pitch+event.relative.y*.004,.08,1.20)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: set_view(0)
			KEY_2: set_view(1)
			KEY_3: set_view(2)
			KEY_N: toggle_weather()
			KEY_G: toggle_gate()
			KEY_P: toggle_power()
			KEY_M: toggle_audio()
			KEY_HOME: set_view(0)
			KEY_TAB: hud.visible = not hud.visible
			KEY_ESCAPE:
				paused = not paused
				rain.emitting = night and not paused
				update_audio()
				hud.notify("已暂停 · Esc 继续" if paused else "预览继续")
			KEY_F12: capture()

func capture() -> void:
	await RenderingServer.frame_post_draw
	var folder := "res://captures/cinematic-sample"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := folder.path_join("preview-"+str(Time.get_unix_time_from_system()).replace(".","-")+".png")
	var error := get_viewport().get_texture().get_image().save_png(file)
	if error == OK:
		last_capture = ProjectSettings.globalize_path(file)
		hud.notify("截图已保存到 captures/cinematic-sample")
	else:
		hud.notify("截图保存失败："+str(error))
