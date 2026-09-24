extends SceneTree
const Save = preload("res://scripts/save_store.gd")
const OUT := "res://captures/core-focus"
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func click(p: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = p
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = p
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func settle() -> void:
	for i in range(8):
		world.hud.refresh(0)
		await process_frame

func screenshot(name: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	var picture := root.get_texture().get_image()
	expect(picture.save_png(OUT.path_join(name + ".png")) == OK, "Native screenshot: " + name)
	for control in [world.hud.bottom, world.hud.quest_box]:
		expect(root.get_visible_rect().encloses(control.get_global_rect()), "HUD fits " + name)
	for button in world.hud.refit_buttons.values():
		if button.visible: expect(world.hud.bottom.get_global_rect().encloses(button.get_global_rect()), "Refit control fits " + name)

func run() -> void:
	Save.directory = "user://core_focus_input_fixture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	await settle()
	expect(not world.hud.profession_select.is_visible_in_tree() and not world.hud.content_seed_input.is_visible_in_tree(), "Start menu omits profession and event seed")
	await screenshot("start")
	click(world.hud.standard_start_button.get_global_rect().get_center())
	await settle()
	expect(world.started and not world.paused, "Native start button launches focused standard game")
	world.spawn_clocks.clear()
	world.prepare_demo()
	world.camera_size = 29
	world.camera_rig.target_pitch = deg_to_rad(48)
	world.update_camera(0)
	world.vision.update()
	var tower: Dictionary
	var gate: Dictionary
	for b in world.session.buildings:
		if b.kind == "tower": tower = b
		if b.kind == "gate": gate = b
	await physics_frame
	await settle()
	click(world.camera.unproject_position(world.board.point(tower.cell)))
	await settle()
	expect(world.selected_id == tower.id and world.hud.refit_buttons.range.visible and world.hud.refit_buttons.rapid.visible, "Clicking the real tower reveals both refit choices")
	await screenshot("tower-options")
	var stock := Vector2i(world.session.wood, world.session.gold)
	click(world.hud.refit_buttons.rapid.get_global_rect().get_center())
	await settle()
	expect(tower.get("refit") == "rapid" and tower.remaining == 12 and Vector2i(world.session.wood, world.session.gold) == stock - Vector2i(10, 14), "Native refit click charges the displayed price and starts construction")
	expect(not world.hud.refit_buttons.range.visible, "Committed tower no longer offers another branch")
	world.session.tick(12)
	world.update_buildings(0)
	world.damage_building(gate, 100)
	await screenshot("camp-refitted")
	world.selected_id = gate.id
	await settle()
	expect(world.hud.repair_button.visible and world.hud.refit_buttons.brace.visible, "Damaged gate offers repair and reinforcement")
	click(world.hud.repair_button.get_global_rect().get_center())
	await settle()
	expect(world.order == "repair" and world.worker.target_id == gate.id, "Repair button sends worker to gate without toggling it")
	world.stop_order()
	world.selected_id = gate.id
	world.preferences.values.fullscreen = false
	world.preferences.apply(world)
	DisplayServer.window_set_size(Vector2i(1000, 800))
	await create_timer(0.3).timeout
	await screenshot("compact-gate-repair")
	world.free()
	print("CORE FOCUS INPUT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
