extends SceneTree
## Native Godot same-scale comparison; gameplay models and shared runtime materials.
var gallery: Node3D
func _initialize() -> void: call_deferred("capture")
func capture() -> void:
	DisplayServer.window_set_size(Vector2i(1440,800))
	root.size=Vector2i(1440,800)
	gallery=Node3D.new()
	root.add_child(gallery)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("17231f")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("a8bcba")
	environment.environment.ambient_light_energy=.65
	gallery.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-25,0)
	sun.light_color=Color("fff1d4")
	sun.light_energy=1.3
	sun.shadow_enabled=true
	gallery.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-25,135,0)
	fill.light_color=Color("a0c6cf")
	fill.light_energy=.45
	gallery.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(200,200)
	floor_mesh.mesh=plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color("17221d")
	mat.roughness=1
	floor_mesh.material_override=mat
	gallery.add_child(floor_mesh)
	var names := ["基础弓箭塔","远射塔 · 远程压制","速射塔 · 双弩清群","重弩塔 · 破甲猎巨"]
	var index := 0
	for variant in ["","range","rapid","heavy"]:
		var path: String = "res://assets/models/tower%s.glb" % ("_"+variant if not variant.is_empty() else "")
		var model: Node3D=load(path).instantiate()
		model.position.x=(index-1.5)*3.8
		model.rotation.y=-.25
		gallery.add_child(model)
		var label := Label3D.new()
		label.text=names[index]
		label.font_size=36
		label.no_depth_test=true
		label.pixel_size=.008
		label.position=Vector3(model.position.x,.15,1.5)
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate=Color("e5d7b5")
		label.outline_modulate=Color("17231f")
		var font:=SystemFont.new()
		font.font_names=PackedStringArray(["PingFang SC","Microsoft YaHei","Noto Sans CJK SC"])
		label.font=font
		gallery.add_child(label)
		index+=1
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=9.5
	camera.position=Vector3(2,9,17)
	gallery.add_child(camera)
	camera.look_at(Vector3(0,1.5,0))
	camera.current=true
	for i in range(12): await process_frame
	RenderingServer.force_draw(false)
	var out := "res://captures/tower-upgrades/00-model-lineup.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var error := root.get_texture().get_image().save_png(out)
	gallery.free()
	print("TOWER LINEUP: ",error)
	quit(error)
