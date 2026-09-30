extends SceneTree
var tag := "after"
var world: Node

func _initialize() -> void: call_deferred("run")

func shot(name: String) -> void:
	world.update_camera(0)
	for i in range(8): await process_frame
	RenderingServer.force_draw(false)
	var path := "res://captures/opening/"+tag+"-"+name+".png"
	print("OPENING CAPTURE ",path," ",root.get_texture().get_image().save_png(path))

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag=arg.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/opening"))
	world=load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled=false
	root.add_child(world)
	world.start_session(1500,"standard")
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.weather.preview_kind=0
	world.weather.update()
	world.update_lighting()
	world.vision.update()
	world.hud.refresh(0)
	world.camera_size=36
	world.camera_rig.center(true)
	await shot("start")
	world.hud.hide()
	world.pointer_feedback.hide()
	world.vision.image.fill(Color.WHITE)
	world.vision.texture.update(world.vision.image)
	world.camera_rig.following=false
	world.camera_focus=Vector3(3,0,-3)
	world.camera_size=55
	await shot("overview")
	world.camera_size=30
	world.camera_rig.target_pitch=deg_to_rad(40)
	world.camera_focus=Vector3(17,0,-13)
	await shot("shore")
	if tag == "after":
		world.hero.position = Vector3(17,world.board.layout.height_at(17,-7),-7)
		world.hero.advance(0)
		world.camera_size = 20
		world.camera_focus = world.hero.position
		await shot("wading")
	world.free()
	quit()
