extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	current_scene = world
	world.sound.set_process(false)
	world.start_session(1500, "hard")
	world.prepare_demo()
	world.session.technologies.tower_engineering = true
	world.session.wood = 1000
	world.session.gold = 1000
	world.weather.preview_kind = 0
	for i in range(6): await process_frame
	world.select_build("tower")
	world.hover_cell = Vector2i(66, 64)
	var p: Vector2 = world.camera.unproject_position(world.board.point(world.hover_cell))
	Input.warp_mouse(p)
	var motion := InputEventMouseMotion.new()
	motion.position = p
	root.push_input(motion, true)
	world.update_build_preview()
	for i in range(6): await process_frame
	var feedback: Control
	for child in world.hud.root.get_children():
		if child.get_script() == world.DefenseFeedback: feedback = child
	feedback._process(0)
	print("PROBE build_mode=", world.build_mode)
	print("PROBE started=", world.started, " paused=", world.paused)
	print("PROBE hover=", world.hover_cell, " inside=", world.board.inside(world.hover_cell))
	var mouse: Vector2 = feedback.get_viewport().get_mouse_position()
	print("PROBE unproject=", p, " viewport_mouse=", mouse)
	print("PROBE covers=", world.hud.covers(mouse))
	print("PROBE quest_box=", world.hud.quest_box.get_global_rect(), " has=", world.hud.quest_box.get_global_rect().has_point(mouse))
	print("PROBE bottom=", world.hud.bottom.get_global_rect(), " has=", world.hud.bottom.get_global_rect().has_point(mouse))
	print("PROBE visible=", feedback.range_node.visible, " key=", feedback.range_key)
	world.free()
	quit(0)
