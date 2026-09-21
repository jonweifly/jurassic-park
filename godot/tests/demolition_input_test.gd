extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var world: Node
var checks := 0
var failures := 0
const OUT := "res://captures/demolition-extraction"
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func click(p: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = p
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = p
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
func screenshot(name: String) -> void:
	world.hud.refresh(0)
	world.extraction_feedback.update()
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OUT.path_join(name+".png"))
func run() -> void:
	Save.directory = "user://demolition_input_fixture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	world.prepare_demo()
	world.camera_size = 25
	world.update_camera(0)
	world.vision.update()
	await process_frame
	await physics_frame
	world.paused = false
	var b: Dictionary = world.session.buildings[2]
	world.selected_id = b.id
	world.hud.refresh(0)
	await process_frame
	await screenshot("building-selected")
	var resources := Vector2i(world.session.wood,world.session.gold)
	click(world.hud.demolish_button.get_global_rect().get_center())
	await process_frame
	expect(world.hud.confirmation.visible and world.paused, "Native HUD demolition click opens paused confirmation")
	expect(world.hud.confirmation.dialog_text.contains("5 木材 / 5 黄金") and world.hud.confirmation.dialog_text.contains("供电"), "Confirmation states exact refund and lost power")
	await screenshot("demolition-confirmation")
	await process_frame
	var cancel: Button = world.hud.confirmation.get_cancel_button()
	click(Vector2(world.hud.confirmation.position) + cancel.get_global_rect().get_center())
	await process_frame
	expect(not world.paused and not world.hud.confirmation.visible and b.hp > 0 and Vector2i(world.session.wood,world.session.gold) == resources, "Cancel resumes without changing building or resources")
	world.hud.refresh(0)
	click(world.hud.demolish_button.get_global_rect().get_center())
	await process_frame
	await process_frame
	var ok: Button = world.hud.confirmation.get_ok_button()
	click(Vector2(world.hud.confirmation.position) + ok.get_global_rect().get_center())
	await process_frame
	expect(b.hp <= 0 and not world.board.structures.has(b.cell), "Confirm removes selected building and collision")
	expect(Vector2i(world.session.wood,world.session.gold) == resources + Vector2i(5,5), "Native confirm refunds exactly once")
	world.paused = false
	await screenshot("building-demolished")
	world.session.phase = "evacuate"
	world.session.finale_wave = 3
	world.session.boarding_progress = 6
	world.hud.notification_time = 0
	world.hero.position = world.extraction
	world.camera_rig.center(true)
	world.camera_size = 20
	world.update_camera(0)
	world.vision.update()
	await screenshot("boarding-progress")
	expect(world.hud.boarding_bar.visible and world.hud.objective.text.contains("正在登机"), "Native evacuation HUD displays real progress")
	world.hero.position += Vector3(4,0,0)
	await screenshot("boarding-interrupted")
	expect(world.hud.objective.text.contains("回退"), "Native HUD clearly reports interrupted boarding")
	world.free()
	print("DEMOLITION INPUT: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
