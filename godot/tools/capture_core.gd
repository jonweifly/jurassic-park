extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var world: Node
var capture_root := "res://captures/core"

func _initialize() -> void:
	call_deferred("run")

func shot(title: String) -> void:
	world.hud.refresh(0)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var result := root.get_texture().get_image().save_png(capture_root.path_join(title + ".png"))
	print("CORE SCREENSHOT ", title, " ", root.size, " result=", result)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root))
	Save.directory = "user://capture_core_preview"
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	await shot("start")
	world.start_session(1500.0, "standard")
	world.prepare_demo()
	world.session.wood = 65
	world.session.gold = 48
	for b in world.session.buildings:
		if b.kind == "lab":
			world.session.research(b.id)
			world.session.work(b.id, 10)
	world.session.technologies.pack_1 = true
	world.session.harvest_level = 1
	world.session.elapsed = 380
	world.hero.health = 118
	world._physics_process(0.033)
	world.vision.update()
	world.update_camera(0)
	await shot("camp")
	world.hud.open_tech()
	await shot("technology")
	world.hud.close_tech()
	world.paused = true
	world.save_status = "手动存档 · 预览界面"
	await shot("pause")
	Save.write(world)
	world.hud.request_load()
	await shot("save-slots")
	world.hud.close_load()
	# Verify that UI stays within a smaller supported viewport as well.
	root.content_scale_size = Vector2i(1280, 800)
	root.size = Vector2i(1280, 800)
	world.paused = false
	world.hud.open_tech()
	await shot("technology-1280")
	world.hud.close_tech()
	world.session.phase = "evacuate"
	world.session.evacuation_elapsed = 60
	world.session.finale_wave = 2
	await shot("evacuation-1280")
	world.free()
	var folder := DirAccess.open(Save.directory)
	if folder:
		for file in folder.get_files(): folder.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.directory))
	quit()
