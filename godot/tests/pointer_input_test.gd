extends SceneTree
## Native viewport event propagation, actual terrain picking and GUI consumption.
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func click(p: Vector2, button: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = p
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = p
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)

func run() -> void:
	load("res://scripts/save_store.gd").directory = "user://pointer_event_fixture"
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500.0, "standard")
	world.camera_rig.target_pitch = deg_to_rad(38)
	world.camera_size = 24
	world.update_camera(0)
	world.hud.refresh(0)
	await process_frame
	await physics_frame
	# Window creation can deliver a focus-out pause before synthetic input begins.
	world.paused = false
	world.hud.refresh(0)
	var point: Vector3 = world.board.point(world.board.cell_at(world.hero.position) + Vector2i(2, 0))
	var screen: Vector2 = world.camera.unproject_position(point)
	expect(not world.hud.covers(screen) and world.board.is_open(world.board.cell_at(point)), "Native click fixture is open terrain outside the HUD")
	expect(world.ground_at(screen).distance_to(point) < 0.15, "Low-angle terrain ray matches the projected destination")
	click(screen, MOUSE_BUTTON_RIGHT)
	await process_frame
	expect(world.order == "move" and not world.hero.route.is_empty(), "Viewport mouse event dispatches the move order")
	expect(world.pointer_feedback.pulse_left > 0 and world.pointer_feedback.pulse_kind == "move", "Actual mouse command triggers animation feedback")
	var before: Vector3 = world.camera.position
	for i in range(10):
		world._physics_process(0.1)
		world.update_camera(0.1)
	expect(world.camera.position.distance_to(before) > 1, "Camera follows after the click without further events")
	# Tool actions use left click while right click remains movement-only.
	var tree_cell := Vector2i.ZERO
	for cell in world.trees:
		var candidate_point: Vector3 = world.board.point(cell)
		var candidate_screen: Vector2 = world.camera.unproject_position(candidate_point)
		if world.vision.explored.has(cell) and not world.hud.covers(candidate_screen) and not world.board.route(world.hero.position, candidate_point, true).is_empty():
			tree_cell = cell
			break
	var tree_point: Vector3 = world.board.point(tree_cell)
	var tree_screen: Vector2 = world.camera.unproject_position(tree_point)
	click(tree_screen, MOUSE_BUTTON_LEFT)
	await process_frame
	expect(world.order == "wood", "Left click starts the tree tool action")
	world.stop_order()
	click(tree_screen, MOUSE_BUTTON_RIGHT)
	await process_frame
	expect(world.order == "move", "Right click on a tree only moves the survivor")
	# A remaining core modal consumes the click and pauses the simulation.
	world.hud.refresh(0)
	expect(not world.hud.journal_button.visible, "Archived journal is absent from the focused HUD")
	click(world.hud.tech_button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	await process_frame
	expect(world.hud.tech_panel.visible and world.paused, "GUI technology click is consumed and opens its modal")
	var position: Vector3 = world.hero.position
	click(screen, MOUSE_BUTTON_RIGHT)
	world._physics_process(1)
	expect(world.hero.position == position, "Right click behind a modal cannot move the hero")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await process_frame
	expect(not world.hud.tech_panel.visible and not world.paused, "Escape closes technology through the native event chain")
	world.free()
	print("POINTER INPUT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
