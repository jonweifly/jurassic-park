extends SceneTree
const Run = preload("res://scripts/expedition_run.gd")
const Save = preload("res://scripts/save_store.gd")
var world: Node
var folder := "res://captures/variety"
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func shot(title: String, panel: Control) -> void:
	for frame in range(4):
		world.hud.refresh(0)
		await process_frame
	RenderingServer.force_draw(false)
	if not root.get_visible_rect().encloses(panel.get_global_rect()):
		push_error("Panel out of bounds: " + title)
		failures += 1
	var error := root.get_texture().get_image().save_png(folder.path_join(title + ".png"))
	print("VARIETY SCREENSHOT ", title, " result=", error, " bounds=", panel.get_global_rect())

func run() -> void:
	Save.directory = "user://variety_capture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.hud.content_seed_input.text = "1826"
	await shot("start-seed", world.hud.start_panel)
	world.hud.start_selected_session(1500, "standard")
	world.hud.expedition_panel.open()
	var panel = world.hud.expedition_panel
	panel.tabs.current_tab = 2
	await shot("contract-choices", panel.panel)
	panel.accept_contract(0)
	await shot("contract-accepted", panel.panel)
	panel.show_contract_site()
	await shot("route-brief", panel.panel)
	panel.close()
	var p: Vector3 = world.board.point(world.session.adventure.sites.nest.cell)
	var path: PackedVector3Array = world.board.route(world.hero.position, p, true)
	world.hero.position = path[-1]
	world.vision.update()
	world.adventure.refresh_visibility()
	world.camera_rig.center(true)
	world.camera_size = 24
	world.update_camera(0)
	panel.open("nest")
	await shot("sampling-risk", panel.panel)
	# Show a drawn material trade, not a fabricated offer outside its persisted plan.
	panel.close()
	for seed_value in range(1, 100):
		var run_data := Run.create(seed_value)
		if run_data.plan[1].id != "barter": continue
		world.session.adventure.run = run_data
		world.session.adventure.events_done = ["map"]
		world.session.elapsed = run_data.plan[1].at
		world.adventure.update_events()
		break
	panel.open()
	panel.tabs.current_tab = 1
	await shot("radio-choice", panel.panel)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	panel.tabs.current_tab = 2
	await shot("contracts-1440", panel.panel)
	# Logical 1280 UI viewport as well as normal 1440 canvas scaling.
	root.content_scale_size = Vector2i(1280, 800)
	root.size = Vector2i(1280, 800)
	await shot("contracts-1280-canvas", panel.panel)
	world.free()
	quit(0 if failures == 0 else 1)
