extends SceneTree
const Save = preload("res://scripts/save_store.gd")
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

func hover(p: Vector3) -> String:
	world.pointer_feedback.update_hover(Vector2(600, 330), p)
	return world.pointer_feedback.cursor_kind

func open_cell() -> Vector2i:
	var origin: Vector2i = world.board.cell_at(world.hero.position)
	for r in range(2, 12):
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				var c := origin + Vector2i(x, y)
				if world.board.can_build(c) and not world.board.route(world.hero.position, world.board.point(c), true).is_empty(): return c
	return Vector2i(-1, -1)

func building(kind: String, remaining: float = 0.0) -> Dictionary:
	var cell := open_cell()
	var b: Dictionary = world.session.build(kind, cell)
	b.remaining = remaining
	world.board.block_building(cell, b.id)
	world.create_building_visual(b)
	return b

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500.0, "standard")
	world.spawn_clocks.clear()
	expect(world.camera_rig.following, "New sessions follow without requiring an extra click")
	world.camera_rig.target_pitch = deg_to_rad(38)
	world.camera_size = 21
	world.update_camera(0)
	var target := Vector3.ZERO
	for x in range(8, 16):
		var cell: Vector2i = world.board.cell_at(world.hero.position) + Vector2i(x, 0)
		if world.board.is_open(cell) and not world.board.route(world.hero.position, world.board.point(cell)).is_empty():
			target = world.board.point(cell)
			break
	expect(target != Vector3.ZERO, "Camera fixture has a real terrain route")
	var hero_before: Vector3 = world.hero.position
	var camera_before: Vector3 = world.camera.position
	world.command(target)
	expect(world.order == "move" and world.pointer_feedback.pulse_kind == "move", "Move click starts a destination pulse")
	for i in range(30):
		world._physics_process(0.1)
		world.update_camera(0.1)
	expect(world.hero.position.distance_to(hero_before) > 5 and world.camera.position.distance_to(camera_before) > 5, "A single command moves hero and camera continuously without further mouse events")
	expect(world.camera_focus.distance_to(world.hero.position) < 0.01 and world.camera_rig.focus.distance_to(world.hero.position) < 1, "Low-angle follow remains smoothly close to the moving hero")
	world.camera_rig.pan(Vector2.RIGHT, 0.2)
	expect(not world.camera_rig.following, "Manual pan permits intentional free camera")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	world.camera_rig.handle(space)
	expect(world.camera_rig.following, "Space resumes persistent follow rather than a one-time center")
	world.camera_rig.center(false)
	world.camera_size = 25
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	world.camera_rig.handle(wheel)
	expect(world.camera_rig.following, "Entering close zoom restores following")
	world.camera_rig.center(false)
	world.camera_rig.target_pitch = deg_to_rad(52)
	world.camera_rig.dragging = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0, -55)
	world.camera_rig.handle(motion)
	expect(world.camera_rig.following, "Entering low angle restores following")
	world.camera_rig.dragging = false
	world.stop_order()
	world.update_camera(0)
	world.vision.update()
	var tree := Vector3.ZERO
	for cell in world.trees:
		var p: Vector3 = world.board.point(cell)
		if p.distance_to(world.hero.position) < 14 and not world.board.route(world.hero.position, p, true).is_empty():
			tree = p
			world.vision.explored[cell] = true
			break
	expect(tree != Vector3.ZERO and hover(tree) == "wood", "Known reachable tree displays the axe")
	world.command(tree)
	expect(world.order == "wood" and world.pointer_feedback.pulse_kind == "wood", "Axe preview and actual gathering command agree")
	world.stop_order()
	expect(world.pointer_feedback.pulse_left == 0 and world.hero.route.is_empty(), "Stop clears the previous target pulse and route")
	world.vision.explored.erase(world.board.cell_at(tree))
	expect(world.context_at(tree).kind == "move", "Unknown forest does not disclose a harvesting target")
	world.session.wood = 300
	world.session.gold = 300
	var tent := building("tent")
	building("fire")
	var field := building("fossil")
	expect(hover(world.board.point(field.cell)) == "gold", "Fossil field displays the pickaxe")
	world.command(world.board.point(field.cell))
	expect(world.order == "gold", "Pickaxe dispatches actual mining")
	world.worker.cargo = 1
	world.worker.cargo_kind = "wood"
	expect(hover(world.board.point(tent.cell)) == "return", "Loaded survivor sees a return icon at the tent")
	world.command(world.board.point(tent.cell))
	expect(world.order == "return", "Return icon dispatches delivery")
	world.worker.cargo = 0
	tent.hp -= 10
	expect(hover(world.board.point(tent.cell)) == "repair", "Damaged tent displays a repair tool")
	world.command(world.board.point(tent.cell))
	expect(world.order == "repair", "Repair preview dispatches repairs")
	var site := building("generator", 2.0)
	expect(hover(world.board.point(site.cell)) == "build", "Unfinished construction displays a hammer")
	world.command(world.board.point(site.cell))
	expect(world.order == "build", "Hammer preview dispatches construction")
	site.remaining = 0.0
	var gate := building("gate")
	var prior: String = world.order
	expect(hover(world.board.point(gate.cell)) == "gate", "Gate has its own interaction icon")
	world.command(world.board.point(gate.cell))
	expect(world.order == prior and gate.gate_timer > 0, "Gate click preserves the existing worker command")
	world.stop_order()
	world.vision.update()
	var dinosaur: Node3D = world.spawn_dinosaur(world.hero.position, "raptor")
	dinosaur.visible = true
	expect(hover(dinosaur.position) == "attack", "Visible live dinosaur displays a combat reticle")
	world.command(dinosaur.position)
	expect(world.order == "attack" and world.hero.target_id == dinosaur.get_instance_id(), "Combat reticle and attack target agree")
	dinosaur.visible = false
	expect(world.context_at(dinosaur.position).kind != "attack", "Unseen dinosaur cannot leak through cursor feedback")
	world.stop_order()
	var cache: Dictionary = world.session.adventure.sites.cache
	cache.status = "known"
	expect(hover(world.board.point(cache.cell)) == "inspect", "Known landmark displays an investigation icon")
	world.command(world.board.point(cache.cell))
	expect(world.hud.expedition_panel.panel.visible and world.paused, "Investigation cursor opens the correct modal")
	world.pointer_feedback.refresh(0.1)
	expect(not world.pointer_feedback.active and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Modal restores normal UI cursor")
	world.hud.expedition_panel.close()
	# Surround an empty destination with obstacles: feedback must agree with failed route.
	var isolated := open_cell()
	for x in range(-1, 2):
		for y in range(-1, 2):
			if x != 0 or y != 0: world.board.block_terrain(isolated + Vector2i(x, y))
	var unreachable: Vector3 = world.board.point(isolated)
	expect(hover(unreachable) == "blocked", "Unreachable destination shows blocked feedback")
	world.command(unreachable)
	expect(world.order == "idle" and world.pointer_feedback.pulse_kind == "blocked", "Rejected move pulses red and leaves no route")
	world.build_mode = "tent"
	expect(hover(world.board.point(tent.cell)) == "blocked", "Occupied construction cell displays invalid placement")
	world.build_mode = ""
	world.hud.refresh(0)
	expect(world.hud.covers(world.hud.quest_box.get_global_rect().get_center()), "Quest controls suppress world pointer interactions")
	world.pointer_feedback.owns_cursor = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	world.pointer_feedback._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Focus loss releases the hidden OS cursor")
	var snapshot := Save.snapshot(world)
	expect(Save.validate(snapshot).is_empty() and snapshot.camera.following, "Follow preference remains compatible with the existing save schema")
	world.free()
	print("MOVEMENT FEEDBACK: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
