extends SceneTree
## Native resize/fullscreen coverage, including canvas bounds and 3D picking.
const Preferences = preload("res://scripts/preferences.gd")
const Save = preload("res://scripts/save_store.gd")
const OUT := "res://captures/display"
var world: Node
var checks := 0
var failures := 0
var fixture := "user://display_test_%d" % Time.get_ticks_usec()

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await create_timer(0.4).timeout
	for frame in range(8):
		world.hud.refresh(0)
		await process_frame

func verify_frame(label: String) -> void:
	var logical := root.get_visible_rect()
	var transform := root.get_final_transform()
	var physical := transform * logical
	expect(physical.position.length() < 2 and physical.size.distance_to(Vector2(root.size)) < 2, label + ": canvas reaches all window edges without bars")
	expect(absf(transform.x.length() - transform.y.length()) < 0.001, label + ": uniform scaling preserves proportions")
	for control in [world.hud.bottom, world.hud.quest_box, world.hud.minimap]:
		expect(logical.encloses(control.get_global_rect()), label + ": HUD stays inside viewport")
	expect(world.hud.bottom.offset_bottom >= -8, label + ": bottom HUD panel stays close to viewport edge")
	var point: Vector3 = world.board.point(world.board.cell_at(world.hero.position) + Vector2i(2, 0))
	var screen: Vector2 = world.camera.unproject_position(point)
	expect(world.ground_at(screen).distance_to(point) < 0.15, label + ": terrain picking remains aligned")
	RenderingServer.force_draw(false)
	var picture := root.get_texture().get_image()
	expect(picture.save_png(OUT.path_join(label + ".png")) == OK, label + ": native screenshot saved")
	world.hud.preferences_panel.open()
	await settle()
	expect(logical.encloses(world.hud.preferences_panel.panel.get_global_rect()), label + ": settings panel fits")
	world.hud.preferences_panel.close()
	print("DISPLAY FRAME ", label, " physical=", root.size, " logical=", logical.size, " transform=", transform)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Preferences.file_path = fixture.path_join("preferences.cfg")
	Save.directory = fixture
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = true
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	await settle()
	expect(world.preferences.values.fullscreen and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Fresh normal startup enters native fullscreen")
	expect(root.get_visible_rect().encloses(world.hud.start_panel.get_global_rect()), "Fullscreen start menu fits")
	world.start_session(1500.0, "standard")
	world.camera_size = 24
	world.camera_rig.target_pitch = deg_to_rad(38)
	world.update_camera(0)
	await settle()
	await physics_frame
	await verify_frame("fullscreen")
	world.preferences.values.fullscreen = false
	world.preferences.apply(world)
	await settle()
	for dimensions in [Vector2i(1280, 800), Vector2i(1280, 720), Vector2i(1280, 550), Vector2i(1000, 800)]:
		DisplayServer.window_set_size(dimensions)
		await settle()
		await verify_frame("window-%dx%d" % [dimensions.x, dimensions.y])
	expect(world.preferences.save_file().is_empty(), "Windowed preference persists")
	world.free()
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = true
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	await settle()
	expect(not world.preferences.values.fullscreen and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Restart respects explicit saved windowed choice")
	world.free()
	var folder := DirAccess.open(fixture)
	for file in folder.get_files(): folder.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	print("DISPLAY INPUT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
