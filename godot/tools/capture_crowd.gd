extends SceneTree
## Native visual comparison of a restored overlapping group on the real island.
const Preferences = preload("res://scripts/preferences.gd")
var world: Node
var folder := "res://captures/crowd"
func _initialize() -> void: call_deferred("run")

func shot(name: String) -> void:
	world.update_lighting()
	world.update_camera(0)
	world.vision.update()
	# Hide labels in both views so the comparison shows body geometry clearly.
	for d in world.dinosaurs: d.health_label.hide()
	for i in range(8): await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(folder.path_join(name+".png"))
	print("CROWD CAPTURE ",name," ",error)

func run() -> void:
	Preferences.file_path = "user://crowd_capture_fixture/preferences.cfg"
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	world.preferences.values.fullscreen = false
	world.preferences.values.perspective = true
	world.preferences.values.quality = 2
	world.preferences.apply(world,false)
	DisplayServer.window_set_size(Vector2i(1440,900))
	var center := Vector3.ZERO
	var found := false
	for y in range(50,82):
		for x in range(50,90):
			var p: Vector3 = world.board.point(Vector2i(x,y))
			if not world.board.body_open(p,7.0): continue
			center = p
			found = true
			break
		if found: break
	if not found:
		push_error("No suitable crowd capture area")
		world.free()
		quit(1)
		return
	world.hero.position = center+Vector3(0,0,5)
	var roster := ["raptor","raptor","young_trex","raptor","trex","small_raptor","elite_raptor","spitter","raptor","alpha_trex","raptor","raptor"]
	for i in range(roster.size()):
		var d: Node3D = world.spawn_dinosaur(center+Vector3((i%4-1.5)*.45,0,(i/4-1)*.4),roster[i])
		d.position.y = world.board.layout.height_at(d.position.x,d.position.z)
		d.visual.face(world.hero.position-d.position,1)
		d.play_animation("idle",float(i)*.07)
		d.speed = 0
		d.set_meta("stationary_test",true)
		d.set_meta("ai_sense_clock",999.0)
		d.set_meta("ai_wander_clock",999.0)
	world.camera_rig.center(false)
	world.camera_focus = center+Vector3(0,0,1)
	world.camera_size = 19
	world.camera_rig.target_pitch = deg_to_rad(64)
	world.camera_rig.target_yaw = deg_to_rad(20)
	world.hud.hide()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await shot("01-stacked")
	for frame in range(180): world.update_dinosaurs(1.0/30)
	await shot("02-body-spacing")
	world.free()
	quit()
