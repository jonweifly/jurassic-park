extends "res://tests/core_focus_input_test.gd"
const Dinosaurs = preload("res://scripts/dinosaur_catalog.gd")

func press(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)

func screenshot(name: String) -> void:
	await settle()
	var stats: RefCounted = world.hud.kill_stats
	var rect: Rect2 = stats.panel.get_global_rect()
	expect(root.get_visible_rect().encloses(rect), "Stats panel fits viewport: " + name)
	expect(rect.encloses(stats.close_button.get_global_rect()), "Close button remains accessible: " + name)
	for count in stats.counts.values(): expect(rect.encloses(count.get_global_rect()), "Species row fits: " + name)
	if stats.legacy_count.visible: expect(stats.list_view.get_global_rect().encloses(stats.legacy_count.get_global_rect()), "Legacy totals are visible without scrolling: " + name)
	RenderingServer.force_draw(false)
	var folder := "res://captures/kill-stats"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	expect(root.get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK, "Native capture: " + name)

func run() -> void:
	Save.directory = "user://kill_stats_input_fixture"
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	await settle()
	expect(world.hud.kill_stats_button.disabled, "Statistics are unavailable before a run")
	world.start_session(1500, "standard")
	await settle()
	var stats: RefCounted = world.hud.kill_stats
	var bottom_height: float = world.hud.bottom.get_global_rect().size.y
	click(world.hud.kill_stats_button.get_global_rect().get_center())
	await settle()
	expect(stats.panel.visible and world.paused and not world.hud.pause_panel.visible, "Native HUD entry opens one paused modal")
	expect(stats.counts.size() == 7 and stats.counts.values().all(func(label): return label.text == "0"), "Every species displays zero at the start")
	expect(not stats.legacy_name.visible and stats.total_label.text == "累计击杀  0", "Fresh run has no unexplained legacy counts")
	var elapsed: float = world.session.elapsed
	world._physics_process(1.0)
	expect(world.session.elapsed == elapsed, "Viewing statistics freezes the game")
	var order: String = world.order
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.position = Vector2(10, 300)
	right.pressed = true
	root.push_input(right, true)
	right = right.duplicate()
	right.pressed = false
	root.push_input(right, true)
	expect(world.order == order, "Clicks outside stats do not issue game orders")
	press(KEY_ESCAPE)
	await settle()
	expect(not stats.panel.visible and not world.paused, "Escape closes stats and resumes an active run")
	# Legacy totals remain explicit while newly recorded species populate the list.
	world.session.kills = 5
	var index := 1
	for species in Dinosaurs.SPECIES:
		for i in range(index): world.session.record_kill(species)
		index += 1
	click(world.hud.kill_stats_button.get_global_rect().get_center())
	await settle()
	expect(stats.total_label.text == "累计击杀  33" and stats.legacy_count.text == "5" and stats.legacy_name.visible, "Legacy plus new totals display correctly")
	expect(stats.counts.alpha_trex.text == "7" and stats.counts.small_raptor.text == "1", "Counts correspond to the correct species names")
	await screenshot("species-breakdown")
	click(stats.close_button.get_global_rect().get_center())
	await settle()
	expect(not world.paused, "Native close button restores running state")
	world.toggle_pause()
	await settle()
	click(world.hud.pause_stats_button.get_global_rect().get_center())
	await settle()
	expect(stats.panel.visible and not world.hud.pause_panel.visible, "Pause menu opens statistics")
	press(KEY_ESCAPE)
	await settle()
	expect(world.paused and world.hud.pause_panel.visible, "Closing stats from pause keeps the game paused")
	for phase in ["won", "lost"]:
		world.session.phase = phase
		world.paused = false
		await settle()
		click(world.hud.pause_stats_button.get_global_rect().get_center())
		await settle()
		expect(stats.panel.visible, "End screen opens statistics: " + phase)
		press(KEY_ESCAPE)
		await settle()
		expect(world.hud.pause_panel.visible and world.session.phase == phase, "Returns to unchanged end screen: " + phase)
	world.session.phase = "playing"
	world.paused = false
	world.hud.kill_stats.open()
	world.hud.open_tech()
	expect(not stats.panel.visible and world.hud.tech_panel.visible and world.paused, "Switching panels cannot stack stats with technology")
	world.hud.close_tech()
	expect(not world.paused, "Panel switch preserves original pause state")
	world.preferences.values.fullscreen = false
	world.preferences.apply(world)
	for size in [Vector2i(1280,800), Vector2i(1000,550)]:
		DisplayServer.window_set_size(size)
		await create_timer(0.3).timeout
		await settle()
		expect(world.hud.bottom.get_global_rect().size.y <= 210 and is_equal_approx(world.hud.bottom.get_global_rect().size.y, bottom_height), "Stats entry does not grow bottom panel")
		expect(world.hud.bottom.get_global_rect().encloses(world.hud.kill_stats_button.get_global_rect()), "Stats entry fits bottom panel")
		click(world.hud.kill_stats_button.get_global_rect().get_center())
		await screenshot("window-%dx%d" % [size.x, size.y])
		press(KEY_ESCAPE)
		await settle()
	world.free()
	print("KILL STATS INPUT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
