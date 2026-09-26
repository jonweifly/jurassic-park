extends "res://tests/core_focus_input_test.gd"
var holding_shift := false

func click(p: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position=p
	motion.shift_pressed=holding_shift
	root.push_input(motion,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=p
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		event.shift_pressed=holding_shift
		root.push_input(event,true)

func key(code: int, down: bool) -> void:
	if code==KEY_SHIFT: holding_shift=down
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func candidate() -> Vector2i:
	var origin: Vector2i = world.board.cell_at(world.hero.position)
	for y in range(origin.y-4, origin.y+5):
		for x in range(origin.x-4, origin.x+5):
			var c := Vector2i(x,y)
			var screen: Vector2 = world.camera.unproject_position(world.board.point(c))
			if not root.get_visible_rect().has_point(screen) or world.hud.covers(screen): continue
			if world.placement_error(c).is_empty() and world.placement_warning(c).is_empty(): return c
	return Vector2i(-1,-1)

func screenshot(name: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	var folder := "res://captures/barrier-rotation"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	expect(root.get_texture().get_image().save_png(folder.path_join(name+".png")) == OK, "Capture " + name)
	expect(world.hud.bottom.get_global_rect().encloses(world.hud.rotate_build_button.get_global_rect()), "Rotate command fits compact HUD")

func run() -> void:
	Save.directory = "user://barrier_rotation_input_fixture"
	load("res://scripts/preferences.gd").file_path = "user://barrier_rotation_input_fixture/preferences.cfg"
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500,"standard")
	world.prepare_demo()
	world.session.wood = 1000
	world.session.gold = 1000
	world.camera_size = 24
	world.update_camera(0)
	world.vision.update()
	await physics_frame
	await settle()
	# Supply enough real power for repeated fence and gate placements.
	world.select_build("generator")
	for i in range(2):
		var generator_plot := candidate()
		expect(generator_plot.x >= 0,"Generator has a legal plot")
		if generator_plot.x < 0: break
		var generator: Dictionary = world.session.build("generator",generator_plot)
		generator.remaining = 0.0
		world.board.block_building(generator_plot,generator.id)
		world.create_building_visual(generator)
	world.build_mode = ""
	await settle()
	var height: float = world.hud.bottom.size.y
	for kind in ["shelter","gate"]:
		click(world.hud.build_buttons[kind].get_global_rect().get_center())
		await settle()
		expect(world.build_mode == kind and world.hud.rotate_build_button.visible, "Native build selection offers rotation")
		var plot := candidate()
		expect(plot.x >= 0,"Reachable visible building plot exists")
		if plot.x < 0: break
		world.hover_cell = plot
		world.update_build_preview()
		await screenshot(kind+"-horizontal")
		var stock := Vector2i(world.session.wood,world.session.gold)
		click(world.hud.rotate_build_button.get_global_rect().get_center())
		await settle()
		expect(is_equal_approx(world.build_rotation,PI*.5),"Native rotation button turns preview")
		key(KEY_R,true)
		key(KEY_R,false)
		await settle()
		expect(is_equal_approx(world.build_rotation,PI),"Keyboard rotation works after HUD button click")
		expect(Vector2i(world.session.wood,world.session.gold)==stock,"Both preview controls are free")
		key(KEY_R,true)
		key(KEY_R,false)
		await settle()
		expect(world.barrier_preview.basis.is_equal_approx(Basis(Vector3.UP,PI*1.5)),"Visible model follows native input")
		await screenshot(kind+"-vertical")
		key(KEY_SHIFT,true)
		await process_frame
		for i in range(2):
			plot = candidate()
			expect(plot.x >= 0,"Continuous build has a legal plot")
			if plot.x < 0: break
			var count: int = world.session.buildings.size()
			click(world.camera.unproject_position(world.board.point(plot)))
			await settle()
			expect(world.session.buildings.size()==count+1,"Native ground click places exactly one barrier")
			var b: Dictionary = world.session.buildings.back()
			expect(b.kind==kind and is_equal_approx(b.get("rotation",-1),PI*1.5),"Placed barrier uses chosen direction")
			expect(world.visuals[b.id].basis.is_equal_approx(Basis(Vector3.UP,PI*1.5)),"Construction model matches preview")
			expect(world.build_mode==kind and is_equal_approx(world.build_rotation,PI*1.5),"Shift continuous build keeps direction")
		key(KEY_SHIFT,false)
		key(KEY_ESCAPE,true)
		key(KEY_ESCAPE,false)
		world.update_build_preview()
		await settle()
		expect(world.build_mode.is_empty() and not world.barrier_preview.visible and not world.hud.rotate_build_button.visible,"Cancel removes preview and rotation command")
		expect(world.hud.bottom.size.y<=height,"Rotation never increases bottom HUD height")
	world.free()
	print("BARRIER ROTATION INPUT: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
