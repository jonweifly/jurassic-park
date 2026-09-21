extends SceneTree
## Native viewport key capture must precede focused Control handling and gameplay shortcuts.
const Preferences = preload("res://scripts/preferences.gd")
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0
var world: Node

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func press(code: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		root.push_input(e, true)

func click(control: Control) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = control.get_global_rect().get_center()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		root.push_input(e, true)

func run() -> void:
	var fixture := "user://preferences_input_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	Preferences.file_path = fixture.path_join("preferences.cfg")
	Save.directory = fixture
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.preferences.values.fullscreen = false
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500.0, "standard")
	await process_frame
	await physics_frame
	world.paused = false
	world.hud.refresh(0)
	press(KEY_F10)
	world.hud.refresh(0)
	await process_frame
	var panel = world.hud.preferences_panel
	expect(panel.panel.visible and world.paused, "Native F10 opens settings and pauses")
	panel.tabs.current_tab = 2
	await process_frame
	# Guide is below the scroll fold; expose its actual Button then click it.
	var scroll: ScrollContainer = panel.key_buttons.guide.get_parent().get_parent()
	scroll.ensure_control_visible(panel.key_buttons.guide)
	await process_frame
	click(panel.key_buttons.guide)
	await process_frame
	expect(panel.listening == "guide", "Native key-binding button click starts capture")
	press(KEY_F5)
	expect(panel.listening == "guide" and not FileAccess.file_exists(fixture.path_join("manual.jps")), "Captured conflicting save key cannot create a game save")
	press(KEY_ESCAPE)
	expect(panel.listening.is_empty() and panel.panel.visible and world.paused, "Native Escape cancels capture without unpausing")
	click(panel.key_buttons.guide)
	panel.controls.pan_speed.grab_focus()
	press(KEY_G)
	expect(panel.draft_keys.guide == KEY_G and panel.listening.is_empty(), "Capture runs before focused GUI controls")
	click(panel.apply_button)
	expect(world.preferences.bindings.guide == KEY_G, "Native Apply saves remapped guide key")
	panel.draft.fullscreen = true
	panel.apply_draft()
	for frame in range(8): await process_frame
	expect(panel.preview and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Native fullscreen preview changes the real window")
	panel.preview_deadline = Time.get_ticks_msec() - 1
	panel.update()
	for frame in range(8): await process_frame
	expect(not panel.preview and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Expired display preview restores actual windowed mode")
	press(KEY_ESCAPE)
	world.hud.refresh(0)
	expect(not panel.panel.visible and not world.paused, "Native Escape closes settings and restores play")
	press(KEY_G)
	world.hud.refresh(0)
	expect(world.hud.guide_panel.panel.visible and world.paused, "Remapped key opens guide through native viewport")
	var before: Vector3 = world.hero.position
	world._physics_process(2)
	expect(world.hero.position == before, "Guide is a real simulation pause")
	press(KEY_ESCAPE)
	expect(not world.hud.guide_panel.panel.visible and not world.paused, "Guide Escape restores play")
	world.free()
	var folder := DirAccess.open(fixture)
	for file in folder.get_files(): folder.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	print("PREFERENCES INPUT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
