extends SceneTree
var world: Node
const OUT := "res://captures/field-engineering"
func _initialize() -> void: call_deferred("run")
func shot(title: String) -> void:
	for i in range(8):
		world.hud.refresh(0)
		await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OUT.path_join(title+".png"))
func run() -> void:
	preload("res://scripts/preferences.gd").file_path = "user://field_capture/preferences.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,800))
	await shot("01-menu")
	world.hud.difficulty_select.show_popup()
	await shot("02-choice")
	world.hud.difficulty_select.get_popup().hide()
	world.start_session(1500,"standard")
	world.hud.confirm_discard("拆除电门？返还 6 木材 / 6 黄金。\n拆除后将恢复通路。",func(): pass)
	await shot("03-confirmation")
	world.hud.confirmation.hide()
	world.paused = false
	world.camera_focus = world.extraction
	world.camera_rig.following = false
	world.camera_rig.focus = world.extraction
	world.camera_size = 22
	world.hero.position = world.extraction
	world.session.phase = "evacuate"
	world.vision.update()
	world.update_camera(0)
	world.extraction_feedback.update()
	await shot("04-landing")
	world.session.phase = "playing"
	world.prepare_demo()
	world.hud.outfit_panel.open()
	await shot("05-workshop")
	world.hud.outfit_panel.close()
	world.paused = false
	world.camera_focus = world.hero.position
	world.camera_rig.focus = world.hero.position
	world.camera_size = 14
	world.update_camera(0)
	world.outfitting.actor().chainsaw = 1
	world.outfitting.apply_equipment(world.hero)
	world.hero.work_pose("chop",world.hero.position+Vector3(1,0,0),.4,.05)
	world.outfitting.data().robots.append({"position":world.hero.position+Vector3(2,0,0),"workshop":1,"clock":0.0})
	world.robots.sync_visuals()
	await shot("06-saw-robot")
	world.free()
	quit()
