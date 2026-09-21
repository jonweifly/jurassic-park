extends SceneTree
const Preferences = preload("res://scripts/preferences.gd")
const Save = preload("res://scripts/save_store.gd")
var world: Node
var folder := "res://captures/preferences"
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func shot(title: String, control: Control) -> void:
	for frame in range(4):
		world.hud.refresh(0)
		await process_frame
	RenderingServer.force_draw(false)
	var viewport := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var bounds := control.get_global_rect()
	if not viewport.encloses(bounds):
		failures += 1
		push_error("Panel outside viewport: " + title + " " + str(bounds))
	var error := root.get_texture().get_image().save_png(folder.path_join(title + ".png"))
	print("SETTINGS SCREENSHOT ", title, " result=", error, " panel=", bounds)

func run() -> void:
	Save.directory = "user://preferences_capture_fixture"
	Preferences.file_path = "user://preferences_capture_fixture/preferences.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	await shot("start-menu", world.hud.start_panel)
	world.hud.preferences_panel.open()
	await shot("settings-graphics", world.hud.preferences_panel.panel)
	world.hud.preferences_panel.tabs.current_tab = 1
	await shot("settings-camera", world.hud.preferences_panel.panel)
	world.hud.preferences_panel.tabs.current_tab = 2
	await shot("settings-keys", world.hud.preferences_panel.panel)
	var scroll: ScrollContainer = world.hud.preferences_panel.key_buttons.build_7.get_parent().get_parent()
	scroll.ensure_control_visible(world.hud.preferences_panel.key_buttons.build_7)
	await shot("settings-keys-bottom", world.hud.preferences_panel.panel)
	world.hud.preferences_panel.close()
	world.start_session(1500.0, "standard")
	world.hud.guide_panel.open()
	await shot("guide-first-camp", world.hud.guide_panel.panel)
	world.hud.guide_panel.pages.current_tab = 1
	await shot("guide-controls", world.hud.guide_panel.panel)
	world.hud.guide_panel.pages.current_tab = 2
	await shot("guide-knowledge", world.hud.guide_panel.panel)
	world.hud.guide_panel.close()
	world.paused = true
	await shot("pause-menu", world.hud.pause_panel)
	# Check another actual window size through the engine's canvas transform.
	DisplayServer.window_set_size(Vector2i(1440, 900))
	world.hud.preferences_panel.open()
	world.hud.preferences_panel.tabs.current_tab = 0
	await shot("settings-1440", world.hud.preferences_panel.panel)
	world.free()
	quit(0 if failures == 0 else 1)
