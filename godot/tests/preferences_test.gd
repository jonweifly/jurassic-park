extends SceneTree
const Preferences = preload("res://scripts/preferences.gd")
const Save = preload("res://scripts/save_store.gd")
var world: Node
var checks := 0
var failures := 0
var fixture := "user://preferences_test_%d" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func test_files() -> void:
	var prefs := Preferences.new()
	prefs.load_file()
	expect(prefs.values == Preferences.DEFAULTS and prefs.bindings == Preferences.default_bindings(), "Missing file uses complete defaults")
	prefs.values.quality = 0
	prefs.values.pan_speed = 1.65
	prefs.bindings.guide = KEY_G
	expect(prefs.save_file().is_empty(), "Local preferences write successfully")
	var loaded := Preferences.new()
	loaded.load_file()
	expect(loaded.values == prefs.values and loaded.bindings == prefs.bindings, "New instance reloads all values and bindings")
	var config := ConfigFile.new()
	config.set_value("preferences", "values", {"quality": "high", "fullscreen": 1, "fps": 999, "zoom_speed": INF, "pan_speed": -4, "rotation_speed": 9})
	var bad := prefs.bindings.duplicate()
	bad.guide = KEY_F5
	config.set_value("preferences", "bindings", bad)
	config.save(Preferences.file_path)
	loaded.load_file()
	expect(loaded.values.quality == 2 and loaded.values.fullscreen == Preferences.DEFAULTS.fullscreen and loaded.values.fps == 0 and loaded.values.zoom_speed == 1, "Invalid types and nonfinite values fall back safely")
	expect(loaded.values.pan_speed == 0.5 and loaded.values.rotation_speed == 2, "Sensitivity is bounded")
	expect(loaded.bindings == Preferences.default_bindings() and not loaded.diagnostic.is_empty(), "Duplicate stored bindings restore coherent defaults")
	config.set_value("preferences", "bindings", {"guide": KEY_G})
	config.save(Preferences.file_path)
	loaded.load_file()
	expect(Preferences.valid_bindings(loaded.bindings), "Incomplete stored key map cannot disable commands")
	expect(not Preferences.valid_key(KEY_ESCAPE) and not Preferences.valid_key(KEY_LEFT), "Escape and fixed navigation remain reserved")
	var modified := key(KEY_G)
	modified.ctrl_pressed = true
	expect(not prefs.matches(modified, "guide"), "Modified system shortcuts do not trigger gameplay")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Preferences.file_path))

func test_panels() -> void:
	# Exercise windowed-to-fullscreen confirmation independently of startup defaults.
	world.preferences.values.fullscreen = false
	var p = world.hud.preferences_panel
	world.paused = false
	var elapsed: float = world.session.elapsed
	var hp: float = world.hero.health
	p.open()
	world._physics_process(10)
	expect(world.paused and world.session.elapsed == elapsed and world.hero.health == hp, "Settings freeze timer and health")
	p.draft.quality = 0
	p.close()
	expect(not world.paused and world.preferences.values.quality == 2, "Closing discards unapplied draft and restores running state")
	world.paused = true
	p.open()
	p.close()
	expect(world.paused, "Opening from pause returns to pause")
	world.paused = false
	p.open()
	p.listen("guide")
	p.handle(key(KEY_F5))
	expect(p.listening == "guide" and p.draft_keys.guide == KEY_F1 and p.message.text.contains("冲突"), "Conflicting binding remains in capture without mutation")
	p.handle(key(KEY_ESCAPE))
	expect(p.panel.visible and p.listening.is_empty(), "Escape cancels key capture before closing modal")
	p.listen("guide")
	p.handle(key(KEY_G))
	p.draft.quality = 0
	p.draft.route_dots = false
	var rng_state: int = world.rng.state
	var terrain: Dictionary = world.board.terrain.duplicate()
	p.apply_draft()
	expect(world.preferences.bindings.guide == KEY_G and FileAccess.file_exists(Preferences.file_path), "Applying commits rebound key and local file")
	expect(not world.sun.shadow_enabled and root.msaa_3d == Viewport.MSAA_DISABLED, "Low quality applies real render switches")
	expect(not world.get_node("Island/GroundCover").visible, "Low quality hides only cosmetic ground cover")
	expect(world.rng.state == rng_state and world.board.terrain == terrain, "Graphics settings preserve RNG and navigation terrain")
	expect(world.hud.controls_hint.text.contains("G 手册"), "HUD hints reflect applied binding")
	p.reset_draft()
	expect(world.preferences.bindings.guide == KEY_G and p.draft_keys.guide == KEY_F1, "Restore-defaults stays draft until applied")
	p.close()
	world._unhandled_input(key(KEY_F1))
	expect(not world.hud.guide_panel.panel.visible, "Previous guide key is inactive after rebinding")
	world._unhandled_input(key(KEY_G))
	expect(world.hud.guide_panel.panel.visible and world.paused, "New guide key opens modal")
	world.hud.guide_panel.close()
	p.open()
	p.draft.fullscreen = true
	p.apply_draft()
	expect(p.preview and world.preferences.values.fullscreen, "Display change enters confirmation preview")
	var saved := Preferences.new()
	saved.load_file()
	expect(not saved.values.fullscreen, "Unconfirmed display preview is never persisted")
	p.preview_deadline = Time.get_ticks_msec() - 1
	p.update()
	expect(not p.preview and not world.preferences.values.fullscreen and world.paused, "Monotonic deadline rolls back even while game is paused")
	p.draft.fullscreen = true
	p.apply_draft()
	p.close()
	expect(not world.preferences.values.fullscreen and not world.paused, "Closing a pending display change restores baseline and pause state")
	p.open()
	p.draft.fullscreen = true
	p.apply_draft()
	p.confirm_preview()
	saved.load_file()
	expect(saved.values.fullscreen and not p.preview, "Explicit display confirmation commits preview")
	p.draft.fullscreen = false
	p.apply_draft()
	p.confirm_preview()
	var good_path := Preferences.file_path
	Preferences.file_path = fixture.path_join("absent/settings.cfg")
	p.draft.quality = 1
	p.apply_draft()
	expect(world.preferences.values.quality == 0 and p.message.text.contains("无法保存"), "Write failure rolls back applied presentation and reports error")
	Preferences.file_path = good_path
	p.close()
	world.hud.expedition_panel.open()
	world.hud.request_load()
	expect(not world.hud.expedition_panel.panel.visible and world.hud.load_panel.visible, "Load browser replaces journal instead of stacking modals")
	p.open()
	expect(not world.hud.load_panel.visible and p.panel.visible, "Settings replaces load browser")
	world.hud.guide_panel.open()
	expect(not p.panel.visible and world.hud.guide_panel.panel.visible, "Guide replaces settings")
	world.hud.open_tech()
	expect(not world.hud.guide_panel.panel.visible and world.hud.tech_panel.visible, "Tech replaces guide")
	world.hud.close_tech()
	expect(not world.paused, "Modal replacement chain preserves original running state")

func complete(kind: String, cell: Vector2i) -> Dictionary:
	var b: Dictionary = world.session.build(kind, cell)
	if not b.is_empty():
		b.remaining = 0.0
		world.board.block_building(cell, b.id)
		world.create_building_visual(b)
	return b

func test_guide() -> void:
	var panel = world.hud.guide_panel
	var guide = panel.guide
	expect(guide.current().kind == "tent", "Fresh game suggests free tent")
	var stock := Vector2i(world.session.wood, world.session.gold)
	panel.open()
	panel.execute()
	expect(world.build_mode == "tent" and not world.paused and stock == Vector2i(world.session.wood, world.session.gold), "Guide selects placement without granting or charging resources")
	world.build_mode = ""
	var tent := complete("tent", Vector2i(65, 65))
	tent.remaining = 5.0
	expect(guide.current().action == "resume" and guide.current().id == tent.id, "Unfinished tent suggests the paid construction site")
	tent.remaining = 0.0
	world.session.wood = 0
	panel.open()
	expect(panel.step.kind == "fire" and panel.step.text.contains("还缺 5 木") and panel.action_button.disabled, "Guide displays real deficit and disables unaffordable action")
	var elapsed: float = world.session.elapsed
	world._physics_process(15)
	expect(world.session.elapsed == elapsed, "Reading guide cannot consume survival time")
	panel.close()
	world.worker.cargo = 1
	world.order = "waiting_dropoff"
	expect(guide.current().title.contains("返送"), "Carried resources with blocked drop-off take precedence")
	world.worker.cargo = 0
	world.order = "idle"
	world.session.wood = 500
	world.session.gold = 500
	complete("fire", Vector2i(66, 65))
	expect(guide.current().kind == "fossil" and guide.current().text.contains("不会自动产金"), "Gold guidance explains active collection and delivery")
	complete("fossil", Vector2i(67, 65))
	expect(guide.current().kind == "generator", "Completed fossil advances to power")
	complete("generator", Vector2i(68, 65))
	expect(guide.current().kind == "tower", "Completed generator advances to defense")
	complete("tower", Vector2i(69, 65))
	expect(guide.current().kind == "lab", "Completed defense advances to base building")
	var lab := complete("lab", Vector2i(70, 65))
	expect(guide.current().action == "upgrade" and guide.current().id == lab.id, "Guide identifies exact building for laboratory upgrade")
	panel.open()
	panel.execute()
	expect(lab.kind == "laboratory" and lab.remaining > 0 and not world.paused, "Guide upgrade uses normal gameplay command")
	expect(guide.current().title.contains("正在升级"), "In-progress upgrade is not offered again")
	lab.remaining = 0
	expect(guide.current().action == "tech", "Completed lab unlocks contextual technology link")
	world.session.phase = "evacuate"
	world.preferences.bindings.heal = KEY_B
	expect(guide.current().action == "evacuate" and guide.current().text.contains("治疗键是 B"), "Evacuation marker and rebound heal key are distinguished")
	world.session.phase = "lost"
	expect(guide.current().action.is_empty(), "Ended game does not suggest active commands")
	world.session.phase = "playing"
	world.preferences.bindings.heal = KEY_H
	var snap := Save.snapshot(world)
	world.preferences.values.zoom_speed = 1.7
	Save.apply(world, snap)
	expect(world.preferences.values.zoom_speed == 1.7, "Loading a run preserves independent current preferences")
	world.hud.guide_panel.open()
	expect(world.hud.guide_panel.step.action == "tech", "Guide derives restored progress without a separate tutorial save")
	world.hud.guide_panel.close()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	Preferences.file_path = fixture.path_join("preferences.cfg")
	Save.directory = fixture
	test_files()
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500.0, "standard")
	world.spawn_clocks.clear()
	test_panels()
	test_guide()
	world.free()
	# Exercise the normal client startup path against isolated preferences and saves.
	var saved := Preferences.new()
	saved.values.quality = 1
	saved.bindings.guide = KEY_G
	saved.save_file()
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = true
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	expect(world.preferences.bindings.guide == KEY_G and root.msaa_3d == Viewport.MSAA_2X, "Normal client startup reloads preferences and applies medium graphics")
	expect(world.hud.controls_hint.text.contains("G 手册"), "Startup HUD uses persisted shortcuts")
	world.preferences.values.quality = 2
	world.preferences.apply(world, false)
	expect(root.msaa_3d == Viewport.MSAA_4X and world.sun.shadow_enabled, "High quality restores original 4x antialiasing and shadows")
	world.free()
	var folder := DirAccess.open(fixture)
	for file in folder.get_files(): folder.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	print("PREFERENCES AND GUIDE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
