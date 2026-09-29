extends SceneTree
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
const OUT := "res://captures/outfitting"
var world: Node
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func click(control: Control) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
func key(code: int) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event,true)
func settle() -> void:
	for frame in range(8):
		world.hud.refresh(0)
		await process_frame
func shot(name: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	expect(root.get_texture().get_image().save_png(OUT.path_join(name + ".png")) == OK, "Native screenshot: " + name)
func run() -> void:
	Save.directory = "user://outfitting_input_fixture"
	Preferences.file_path = Save.directory.path_join("preferences.cfg")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	world.prepare_demo()
	world.session.wood = 100
	world.session.gold = 100
	world.camera_size = 25
	world.update_camera(0)
	for b in world.session.buildings:
		if b.kind == "lab": world.selected_id = b.id
	await settle()
	expect(world.hud.workshop_button.visible, "Selecting a foundation reveals both upgrade branches")
	await shot("01-upgrade-choice")
	click(world.hud.workshop_button)
	await settle()
	var workshop: Dictionary = world.selected_building()
	expect(workshop.get("kind", "") == "workshop", "Native upgrade button starts actual workshop upgrade")
	if workshop.get("kind", "") != "workshop": world.free(); quit(1); return
	world.session.tick(15)
	world.update_buildings(0)
	await settle()
	click(world.hud.outfit_button)
	await settle()
	var panel: RefCounted = world.hud.outfit_panel
	expect(panel.panel.visible and world.paused and not world.hud.pause_panel.visible, "Equipment panel is modal and pauses gameplay")
	expect(root.get_visible_rect().encloses(panel.panel.get_global_rect()), "Equipment panel fits native window")
	await shot("02-workshop")
	var previous: int = world.session.gold
	click(panel.buttons.boots)
	await settle()
	expect(not panel.panel.visible and not world.paused and world.session.gold == previous - 10, "Native craft click resumes and starts paid production")
	world.outfitting.update(18)
	key(KEY_L)
	await settle()
	click(panel.collect_button)
	await settle()
	expect(world.order == "field" and not world.paused, "Native collect click issues travel order")
	for frame in range(600):
		world.hero.advance(.05)
		world.update_order(.05)
		world.outfitting.tick_actor(.05)
		if world.order != "field": break
	expect(world.outfitting.actor().boots == 1, "Actual movement to workshop equips selected item")
	world.hero.health = 80
	world.outfitting.actor().kits = 1
	await settle()
	click(world.hud.kit_button)
	expect(world.hero.health == 130 and world.outfitting.actor().kits == 0, "HUD quick medkit works without opening a menu")
	key(KEY_L)
	await settle()
	panel.tabs.current_tab = 1
	await shot("03-field-routes")
	click(panel.site_buttons.supplies)
	await settle()
	expect(world.order == "field" and world.outfitting.actor().site == "supplies", "Native field route button starts real exploration")
	key(KEY_X)
	expect(world.order == "idle" and world.outfitting.actor().task.is_empty(), "Stop shortcut cancels field action")
	world.damage_building(workshop, 10)
	await settle()
	click(world.hud.camp_view_button)
	expect(not world.camera_rig.following and world.camera_focus == world.board.point(workshop.cell), "Camp alert button looks at damaged building")
	key(KEY_SPACE)
	expect(world.camera_rig.following, "Space returns to player follow after checking camp")
	world.preferences.values.fullscreen = false
	world.preferences.apply(world)
	for dimensions in [Vector2i(1000,800), Vector2i(1280,550)]:
		DisplayServer.window_set_size(dimensions)
		await create_timer(.3).timeout
		await settle()
		expect(root.get_visible_rect().encloses(world.hud.bottom.get_global_rect()), "Expanded commands fit viewport " + str(dimensions))
		key(KEY_L)
		await settle()
		for tab in range(2):
			panel.tabs.current_tab = tab
			await settle()
			expect(root.get_visible_rect().encloses(panel.panel.get_global_rect()), "Equipment tab fits compact viewport")
			if tab == 1:
				for button in panel.site_buttons.values(): expect(panel.tabs.get_global_rect().encloses(button.get_global_rect()), "All exploration buttons are inside tab")
		await shot("compact-%dx%d" % [dimensions.x,dimensions.y])
		key(KEY_ESCAPE)
	world.selected_id = -1
	DisplayServer.window_set_size(Vector2i(1280,800))
	await create_timer(.3).timeout
	await shot("04-camp")
	# Close view also inspects distinct workshop geometry and bone-attached equipment.
	world.outfitting.actor().vest = 1
	world.outfitting.actor().rifle = 1
	world.outfitting.apply_equipment(world.hero)
	world.hud.hide()
	world.camera_focus = world.board.point(workshop.cell)
	world.camera_rig.following = false
	world.camera_size = 12
	world.update_camera(0)
	await shot("05-workshop-model")
	world.free()
	print("OUTFITTING INPUT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
