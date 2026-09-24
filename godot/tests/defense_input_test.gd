extends "res://tests/core_focus_input_test.gd"

func screenshot(name: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	var folder := "res://captures/defense-tactics"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	expect(root.get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK, "Capture " + name)
	var rect: Rect2 = world.hud.bottom.get_global_rect()
	expect(root.get_visible_rect().encloses(rect) and rect.size.y <= 210, "Compact HUD contained: " + name)
	for control in [world.hud.priority_button, world.hud.focus_button, world.hud.clear_focus_button] + world.hud.refit_buttons.values():
		if control.is_visible_in_tree(): expect(rect.encloses(control.get_global_rect()), "Tactical control fits: " + name)

func run() -> void:
	Save.directory = "user://defense_input_fixture"
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500, "hard")
	world.prepare_demo()
	world.session.wood = 1000
	world.session.gold = 1000
	world.weather.preview_kind = 0
	world.camera_size = 25
	world.update_camera(0)
	world.vision.update()
	await physics_frame
	await settle()
	var tower: Dictionary
	for b in world.session.buildings:
		if b.kind == "tower": tower = b
	world.selected_id = tower.id
	await screenshot("tower-choices")
	world.hud.priority_button.select(1)
	world.hud.priority_button.item_selected.emit(1)
	expect(tower.priority == "large", "Priority control changes selected tower")
	click(world.hud.refit_buttons.heavy.get_global_rect().get_center())
	await settle()
	expect(tower.get("refit") == "heavy" and tower.remaining == 18.0, "Native heavy refit click starts paid upgrade")
	world.session.tick(18)
	world.update_buildings(0)
	world.clear_tree(Vector2i(66,64))
	var target: Node3D = world.spawn_dinosaur(world.board.point(Vector2i(66,64)), "elite_raptor")
	expect(target != null, "Focus fixture has an open dinosaur cell")
	if target == null:
		world.free()
		quit(1)
		return
	world.vision.update()
	target.visible = true
	var hero_order: String = world.order
	click(world.hud.focus_button.get_global_rect().get_center())
	await settle()
	expect(world.defense.marking, "Native focus button enters selection mode")
	click(world.camera.unproject_position(target.position))
	await settle()
	expect(world.defense.focus_uid == target.get_meta("save_id") and not world.defense.marking and world.order == hero_order, "World click marks enemy without changing survivor order")
	await screenshot("heavy-focus")
	click(world.hud.clear_focus_button.get_global_rect().get_center())
	await settle()
	expect(world.defense.focus_uid == -1, "Native clear removes focus")
	click(world.hud.focus_button.get_global_rect().get_center())
	var cancel := InputEventMouseButton.new()
	cancel.position = world.camera.unproject_position(target.position)
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	root.push_input(cancel, true)
	cancel = cancel.duplicate()
	cancel.pressed = false
	root.push_input(cancel, true)
	expect(not world.defense.marking and world.order == hero_order, "Right cancel does not issue a survivor order")
	world.select_build("tower")
	world.hover_cell = Vector2i(66,64)
	var p: Vector2 = world.camera.unproject_position(world.board.point(world.hover_cell))
	Input.warp_mouse(p)
	var motion := InputEventMouseMotion.new()
	motion.position = p
	root.push_input(motion, true)
	world.update_build_preview()
	await settle()
	var feedback: Control
	for child in world.hud.root.get_children():
		if child.get_script() == world.DefenseFeedback: feedback = child
	feedback._process(0)
	expect(feedback.range_node.visible and feedback.range_key.contains(str(world.hover_cell)), "Building mode previews hovered tower range")
	await screenshot("build-range")
	world.hover_cell = Vector2i(67,64)
	feedback._process(0)
	expect(feedback.range_key.contains(str(world.hover_cell)), "Range follows changed build cell")
	world.build_mode = ""
	world.selected_id = -1
	feedback._process(0)
	expect(not feedback.range_node.visible, "Cancel removes building range")
	world.preferences.values.fullscreen = false
	world.preferences.apply(world)
	DisplayServer.window_set_size(Vector2i(1000,800))
	await create_timer(0.3).timeout
	world.selected_id = tower.id
	await screenshot("compact-heavy")
	# A fresh tower shows all three upgrade buttons even in the smaller window.
	tower.erase("refit")
	await screenshot("compact-choices")
	world.free()
	print("DEFENSE INPUT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
