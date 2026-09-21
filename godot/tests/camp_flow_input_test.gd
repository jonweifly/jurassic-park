extends SceneTree
const Save = preload("res://scripts/save_store.gd")
const OUT := "res://captures/camp-flow"
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
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = p
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
func shot(name: String) -> void:
	world.hud.refresh(0)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OUT.path_join(name+".png"))
func run() -> void:
	Save.directory = "user://camp_flow_input_fixture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	var origin: Vector2i = world.board.cell_at(world.hero.position)
	var center := Vector2i(-1,-1)
	for y in range(origin.y-5,origin.y+6):
		for x in range(origin.x-5,origin.x+6):
			var valid := true
			for a in range(-1,2):
				for b in range(-1,2):
					if not world.board.can_build(Vector2i(x+a,y+b)): valid = false
			if valid:
				center = Vector2i(x,y)
				break
		if center.x >= 0: break
	expect(center.x >= 0,"Actual map has an open courtyard fixture")
	if center.x < 0:
		world.free()
		quit(1)
		return
	world.hero.position = world.board.point(center)
	var candidate := center + Vector2i.RIGHT
	for x in range(-1,2):
		for y in range(-1,2):
			var cell := center + Vector2i(x,y)
			if cell in [center,candidate]: continue
			var b: Dictionary = world.session.build("tent",cell)
			b.remaining = 0.0
			world.board.block_building(cell,b.id)
			world.create_building_visual(b)
	world.session.wood = 10
	world.session.gold = 10
	world.camera_size = 22
	world.camera_rig.center(true)
	world.update_camera(0)
	world.vision.update()
	world.build_mode = "fire"
	world.hud.refresh(0)
	await process_frame
	await physics_frame
	world.paused = false
	world.hover_cell = candidate
	world.hud.refresh(0)
	var screen: Vector2 = world.camera.unproject_position(world.board.point(candidate))
	expect(not world.hud.covers(screen) and world.placement_error(candidate).is_empty(),"Candidate can actually be clicked and afforded")
	world.build_access = load("res://scripts/build_access.gd").new(world)
	var begin := Time.get_ticks_usec()
	var warning: String = world.placement_warning(candidate)
	var fresh_ms := float(Time.get_ticks_usec()-begin)/1000
	expect(not warning.is_empty(),"Courtyard last exit warns before clicking")
	world.pointer_feedback.update_hover(screen,world.board.point(candidate))
	expect(world.pointer_feedback.cursor_text.contains("注意"),"Small contextual pointer explains risk")
	begin = Time.get_ticks_usec()
	for i in range(100): world.placement_warning(candidate)
	var cached_ms := float(Time.get_ticks_usec()-begin)/1000
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	root.push_input(motion,true)
	world.update_build_preview()
	expect(world.ghost.visible and world.ghost.material_override.albedo_color.r > world.ghost.material_override.albedo_color.g, "Runtime preview renders the warning in amber")
	await shot("last-exit-warning")
	var count: int = world.session.buildings.size()
	click(screen)
	await process_frame
	expect(world.hud.confirmation.visible and world.paused and world.session.wood == 10 and world.session.buildings.size() == count,"Risky ground click opens confirmation before payment or placement")
	await shot("confirm-placement")
	click(Vector2(world.hud.confirmation.position)+world.hud.confirmation.get_cancel_button().get_global_rect().get_center())
	await process_frame
	expect(not world.paused and not world.hud.confirmation.visible and world.board.is_open(candidate) and world.session.wood == 10,"Cancel leaves the exit and stock unchanged")
	world.hud.refresh(0)
	click(screen)
	await process_frame
	await process_frame
	click(Vector2(world.hud.confirmation.position)+world.hud.confirmation.get_ok_button().get_global_rect().get_center())
	await process_frame
	expect(world.session.buildings.size() == count+1 and world.session.wood == 5 and not world.board.is_open(candidate),"Intentional closure is allowed and charged once")
	world.paused = false
	world.ghost.hide()
	world.demolish_building(world.selected_id)
	expect(world.board.is_open(candidate),"Existing demolition immediately recovers an intentionally sealed exit")
	world.build_mode = ""
	world.pointer_feedback.update_hover(screen,world.board.point(candidate))
	expect(world.pointer_feedback.cursor_text.is_empty(),"Normal movement still has no right-click-move popup")
	FileAccess.open(OUT.path_join("preview-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"fresh_query_ms":fresh_ms,"cached_100_queries_ms":cached_ms},"\t"))
	await shot("exit-reopened")
	world.free()
	print("CAMP FLOW INPUT: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
