extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	Save.directory = "user://reload_test_%d" % Time.get_ticks_usec()
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.set_physics_process(false)
	world.start_session(1500.0, "standard")
	world.session.wood = 37
	world.session.gold = 23
	world.session.elapsed = 333
	world.order = "move"
	world.order_target = world.board.point(Vector2i(65, 63))
	world.hero.route = world.board.route(world.hero.position, world.order_target)
	world.camera_size = 22
	world.camera_rig.target_yaw = 1.8
	world.save_game()
	expect(Save.latest().has("data"), "UI save command creates a readable save")
	world.hud.request_load()
	world.hud.refresh(0)
	expect(world.hud.load_panel.visible and world.paused and not world.hud.pause_panel.visible, "Slot browser is modal and pauses the active session")
	expect(not world.hud.load_buttons.manual.disabled, "Valid manual slot is selectable")
	world.hud.close_load()
	world.session.wood = 99
	Save.write(world, true)
	world.session.wood = 4
	world.load_game("manual")
	for i in range(4): await process_frame
	world = current_scene
	expect(is_instance_valid(world) and world.started and world.paused, "Scene reload consumes pending save and pauses")
	world.set_physics_process(false)
	expect(world.session.wood == 37 and world.session.gold == 23, "Scene reload discards unsaved mutations")
	expect(world.order == "move" and not world.hero.route.is_empty(), "Saved route and active order survive real scene reload")
	expect(world.camera_size == 22 and world.camera_rig.target_yaw == 1.8, "Camera restores across scene lifecycle")
	expect(Save.pending.is_empty(), "Pending snapshot is consumed exactly once")
	world.hud.refresh(0)
	expect(world.hud.pause_panel.visible and not world.hud.start_panel.visible, "Loaded game shows paused continue UI rather than new-game menu")
	world.toggle_pause()
	world._physics_process(0.1)
	expect(world.session.elapsed > 333, "Continued scene resumes simulation after explicit unpause")
	var folder := DirAccess.open(Save.directory)
	for file in folder.get_files(): folder.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.directory))
	print("SAVE RELOAD: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
