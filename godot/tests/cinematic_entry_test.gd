extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func settle() -> void:
	for i in range(12): await process_frame
func click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,true)
func shot(file: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var folder := "res://captures/cinematic-sample"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.get_texture().get_image().save_png(folder.path_join(file))
func run() -> void:
	root.size = Vector2i(1440,900)
	check(change_scene_to_file("res://scenes/main.tscn") == OK,"Main scene must load")
	await settle()
	var game: Node = current_scene
	var entry: Button = game.hud.start_panel.find_child("CinematicSampleEntry",true,false)
	check(entry != null and entry.is_visible_in_tree(),"Preview entry must be visible in the main menu")
	if not entry: quit(1); return
	check(root.get_visible_rect().encloses(entry.get_global_rect()),"Preview entry must fit inside the viewport")
	check(not game.started,"Entry must be accessible before a survival session starts")
	await shot("08-menu-entry.png")
	click(entry)
	await settle()
	check(current_scene.scene_file_path == "res://scenes/cinematic_sample.tscn","Clicking entry must actually open the sample")
	if current_scene.scene_file_path != "res://scenes/cinematic_sample.tscn": quit(1); return
	check(current_scene.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,"Menu entry must start with gameplay projection")
	await shot("09-menu-opened-topdown.png")
	var back: Button = current_scene.hud.canvas.get_node("ReturnToMenu")
	click(back)
	await settle()
	check(current_scene.scene_file_path == "res://scenes/main.tscn","Return button must reopen the main menu")
	if current_scene.scene_file_path == "res://scenes/main.tscn":
		check(not current_scene.started,"Returning must not silently start a game")
		check(current_scene.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,"Gameplay projection must remain orthographic")
		check(not auto_accept_quit,"Gameplay's save-on-exit handling must be restored")
	print("CINEMATIC ENTRY: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
