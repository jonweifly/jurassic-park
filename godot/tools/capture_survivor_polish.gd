extends SceneTree
## Native rendered walkthrough; fixture state never touches player saves.
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
const OUT := "res://captures/survivor-polish"
var world: Node
var failures := 0
var report := {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func step(dt: float = 1.0 / 30.0) -> void:
	world._physics_process(dt)
	world.update_camera(dt)
	world.hud.refresh(dt)
	world.narrative.update(dt)
	world.extraction_feedback.update()

func shot(title: String) -> void:
	for frame in range(3): await process_frame
	RenderingServer.force_draw(false)
	var picture := root.get_texture().get_image()
	check(picture != null and not picture.is_empty(), "Rendered image exists: " + title)
	if picture == null or picture.is_empty(): return
	check(picture.save_png(OUT.path_join(title + ".png")) == OK, "Screenshot saved: " + title)
	var low := 1.0
	var high := 0.0
	for y in range(picture.get_height() / 4, picture.get_height() * 3 / 4, 20):
		for x in range(picture.get_width() / 4, picture.get_width() * 3 / 4, 20):
			var color := picture.get_pixel(x, y)
			var value := (color.r + color.g + color.b) / 3.0
			low = minf(low, value)
			high = maxf(high, value)
	check(high - low > 0.08, "Playfield is visibly rendered: " + title)
	report[title] = {"position": str(world.hero.position), "action": world.hero.animation_state, "cargo": world.worker.cargo, "phase": world.session.phase, "boarding": world.session.boarding_progress, "subtitle": world.hud.subtitle_label.text, "pixel_range": high - low}
	print("SURVIVOR CAPTURE ", title)

func inspect_camera(target: Vector3, size: float = 5.5) -> void:
	var focus: Vector3 = world.hero.position + Vector3.UP * 0.9
	var direction: Vector3 = (target - world.hero.position).normalized()
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = size
	world.camera.position = focus + Vector3(direction.z * 5, 3, -direction.x * 5) - direction * 2
	world.camera.look_at(focus)
	world.scenery.update_view(0)

func free_cell() -> Vector2i:
	var origin: Vector2i = world.board.cell_at(world.hero.position)
	for radius in range(3, 16):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var cell := origin + Vector2i(x, y)
				if world.board.can_build(cell) and not world.board.route(world.hero.position, world.board.point(cell), true).is_empty(): return cell
	return Vector2i(-1, -1)

func facility(kind: String) -> Dictionary:
	var cell := free_cell()
	check(cell.x >= 0, "Reachable facility fixture: " + kind)
	var building: Dictionary = world.session.build(kind, cell)
	check(not building.is_empty(), "Facility prerequisites met: " + kind)
	if building.is_empty(): return building
	building.remaining = 0.0
	world.board.block_building(cell, building.id)
	world.create_building_visual(building)
	return building

func work_walkthrough(kind: String, target: Vector3) -> void:
	world.vision.explored[world.board.cell_at(target)] = true
	world.command(target)
	check(world.order == kind, "Real pointer command dispatches " + kind)
	var action := "chop" if kind == "wood" else "mine"
	var saw_windup := false
	var gathered := false
	for frame in range(1800):
		step()
		if frame == 18:
			await shot(kind + "-approach")
		if world.hero.animation_state == action and world.worker.clock >= 0.60 and not saw_windup:
			saw_windup = true
			world.hud.hide()
			inspect_camera(target)
			await shot(action + "-windup")
			world.hud.show()
		if world.worker.cargo > 0:
			gathered = true
			world.hud.hide()
			inspect_camera(target)
			await shot(action + "-contact")
			world.hud.show()
			break
	check(gathered and saw_windup, "Real movement reaches work and produces cargo: " + kind)
	check(world.worker.recovery > 0.0 and world.hero.animation_state == action, "Contact retains the recovery pose: " + kind)
	var cargo: int = world.worker.cargo
	for frame in range(5): step()
	check(world.worker.cargo == cargo, "Recovery does not duplicate cargo: " + kind)
	world.stop_order()
	world.worker.cargo = 0
	world.hero.carrying = false
	world.hero.advance(0.3)

func run() -> void:
	Save.directory = "user://survivor_polish_capture_fixture"
	Preferences.file_path = Save.directory.path_join("preferences.cfg")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	world.start_session(1500, "standard")
	world.spawn_clocks.clear()
	world.session.finale_wave = true
	world.camera_rig.target_pitch = deg_to_rad(38)
	world.camera_size = 36
	world.update_camera(0)
	var zoom := InputEventMouseButton.new()
	zoom.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom.pressed = true
	for click in range(12): world.camera_rig.handle(zoom)
	world.update_camera(0)
	check(world.camera_size == 18.0, "Actual wheel input reaches maximum gameplay zoom")
	step(0.0)
	await shot("map-max-zoom")
	var cells: Array = world.trees.keys()
	cells.sort_custom(func(a, b): return world.board.point(a).distance_squared_to(world.hero.position) < world.board.point(b).distance_squared_to(world.hero.position))
	var tree := Vector3.INF
	for cell in cells:
		var target: Vector3 = world.board.point(cell)
		if not world.worker.wood_route(target).is_empty():
			tree = target
			break
	check(tree != Vector3.INF, "Current map has a reachable working tree")
	if tree != Vector3.INF: await work_walkthrough("wood", tree)
	# Completed prerequisites isolate animation checks from the economy balancing loop.
	world.session.wood = 1000
	world.session.gold = 1000
	facility("tent")
	facility("fire")
	var fossil := facility("fossil")
	if not fossil.is_empty(): await work_walkthrough("gold", world.board.point(fossil.cell))
	world.camera_size = 18
	world.update_camera(0)
	step(0.0)
	await shot("map-after-work")
	world.session.elapsed = world.session.duration - 0.01
	world.hud.clear_subtitle()
	step(0.02)
	await shot("rescue-arrival")
	world.go_to_extraction()
	var on_pad := false
	for frame in range(3600):
		step()
		if world.session.boarding_progress > 0.0:
			on_pad = true
			break
	check(on_pad, "Real extraction order walks the survivor onto the H pad")
	for frame in range(180): step()
	await shot("rescue-boarding")
	for frame in range(240):
		step()
		if world.session.phase == "won": break
	check(world.session.phase == "won", "Survivor completes the real twelve-second boarding rule")
	await shot("rescue-success")
	DisplayServer.window_set_size(Vector2i(1024, 768))
	world.hud.show_subtitle("无线电 · 救援机组：这里是回收一号，撤离点已就绪。前往 H 停机坪。", 5.5, true)
	world.hud.refresh(0)
	await shot("subtitle-compact")
	var plate: Rect2 = world.hud.subtitle_plate.get_global_rect()
	check(not plate.intersects(world.hud.bottom.get_global_rect()) and not plate.intersects(world.hud.tip.get_global_rect()), "Wrapped subtitles do not overlap controls or notifications")
	report["failures"] = failures
	var file := FileAccess.open(OUT.path_join("verification.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	world.free()
	print("SURVIVOR WALKTHROUGH: ", failures, " failures")
	quit(0 if failures == 0 else 1)
