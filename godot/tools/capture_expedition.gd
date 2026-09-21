extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var world: Node
var folder := "res://captures/content"

func _initialize() -> void:
	call_deferred("run")

func shot(title: String) -> void:
	world.hud.refresh(0)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var error := root.get_texture().get_image().save_png(folder.path_join(title + ".png"))
	print("EXPEDITION SCREENSHOT ", title, " result=", error)

func visit(id: String) -> void:
	var target: Vector3 = world.board.point(world.session.adventure.sites[id].cell)
	var path: PackedVector3Array = world.board.route(world.hero.position, target, true)
	if not path.is_empty(): world.hero.position = path[-1]
	world.hero.route.clear()
	world.vision.update()
	world.adventure.refresh_visibility()
	world.camera_rig.following = false
	world.camera_focus = target
	world.camera_size = 21
	world.camera_rig.target_yaw = 0.4
	world.update_camera(0)

func run() -> void:
	Save.directory = "user://capture_expedition_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500.0, "standard")
	world.session.elapsed = 310
	world.session.wood = 45
	world.session.gold = 30
	world.update_lighting()
	visit("cache")
	await shot("survey-camp")
	world.hud.expedition_panel.open("cache")
	await shot("journal")
	world.hud.expedition_panel.close()
	world.session.adventure.events_done = ["map"]
	world.adventure.update_events()
	world.hud.expedition_panel.open()
	await shot("radio")
	world.hud.expedition_panel.close()
	for id in ["clinic", "relay", "nest", "weather", "archive"]:
		visit(id)
		await shot(id)
	root.content_scale_size = Vector2i(1280, 800)
	root.size = Vector2i(1280, 800)
	world.hud.expedition_panel.open("archive")
	await shot("journal-1280")
	world.hud.expedition_panel.close()
	# Telegraph remains local, and uses the actual adult attack code.
	var dinosaur: Node3D = world.spawn_dinosaur(world.hero.position, "trex")
	world.vision.update()
	world.dino_ai.provoke(dinosaur, "hero", -1, world.hero.position)
	world.dino_ai.attack_if_close(dinosaur)
	await shot("heavy-warning")
	world.free()
	quit()
