extends SceneTree
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
var world: Node
var folder := "res://captures/environment"
func _initialize() -> void: call_deferred("run")
func shot(title: String) -> void:
	for frame in range(5):
		world.paused = false
		world.hud.refresh(0)
		await process_frame
	RenderingServer.force_draw(false)
	print("ENVIRONMENT SCREENSHOT ",title," result=",root.get_texture().get_image().save_png(folder.path_join(title+".png")))
func run() -> void:
	Save.directory = "user://environment_capture_fixture"
	Preferences.file_path = "user://environment_capture_fixture/preferences.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	world.camera_size = 25
	world.camera_rig.target_pitch = deg_to_rad(43)
	world.update_camera(0)
	world.vision.update()
	var old := "--original-environment" in OS.get_cmdline_user_args()
	if old:
		var ground: ShaderMaterial = world.scenery.ground
		ground.shader = load("res://shaders/ground_previous.gdshader")
		world.weather.preview_kind = 0
		world.update_lighting()
		world.environment.fog_density = 0.0014
		await shot("camp-before")
	else:
		world.weather.preview_kind = 0
		world.update_lighting()
		world.update_camera(0)
		await shot("camp-after")
		# Static catalogue of the four independent silhouettes, not new obstacles.
		world.hud.hide()
		var entries := []
		var base: Vector3 = world.hero.position
		for i in range(4):
			var n: Node3D = load("res://assets/models/%s.glb" % world.scenery.variation.FAMILIES[i]).instantiate()
			world.add_child(n)
			n.position = base+Vector3((i-1.5)*4,0,0)
			n.position.y = world.board.layout.height_at(n.position.x,n.position.z)
			world.scenery.style_leaves(n)
			entries.append(n)
		world.hero.hide()
		world.camera.position = base+Vector3(0,8,19)
		world.camera.look_at(base+Vector3.UP*1.5)
		world.camera.size = 20
		await shot("tree-models")
		for n in entries: n.free()
		world.hero.show()
		world.hud.show()
		world.update_camera(0)
		for k in [1,2,3]:
			world.weather.preview_kind = k
			world.update_lighting()
			world.update_camera(0)
			world.weather.drops.restart()
			for i in range(45): await process_frame
			await shot(["breeze","gale","rain","storm"][k])
		# Show terrain rules in the same local view, without clearing real obstacles.
		world.weather.preview_kind = 0
		world.update_lighting()
		var found := false
		for y in range(38,72):
			if found: break
			for x in range(45,88):
				var cell := Vector2i(x,y)
				if world.board.is_open(cell) and not world.board.can_build(cell) and not world.board.route(world.hero.position,world.board.point(cell)).is_empty():
					world.hero.position = world.board.point(cell)
					found = true
					break
		world.camera_size = 22
		world.camera_rig.center(true)
		world.vision.update()
		world.update_camera(0)
		await shot("slope-surface")
		world.build_mode = "tent"
		world.update_camera(0)
		await shot("slope-buildability")
	world.free()
	quit()
