extends SceneTree
const Maps = preload("res://scripts/map_catalog.gd")

func _initialize() -> void:
	call_deferred("run")

func shot(file: String) -> void:
	for i in range(6): await process_frame
	RenderingServer.force_draw(false)
	var error := root.get_texture().get_image().save_png("res://data/map_candidates/" + file)
	print("ORGANIC CAPTURE ", file, " result=", error)
	if error != OK: quit(1)

func run() -> void:
	Maps.selected_id = "organic-island-v3"
	var prefix := "organic_island_v3"
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_candidates/" + prefix + ".json"))
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.hud.hide()
	world.sound.set_process(false)
	world.vision.image.fill(Color.WHITE)
	world.vision.texture.update(world.vision.image)
	world.environment.fog_enabled = false
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 275
	world.camera.far = 700
	world.camera.position = Vector3(0, 340, 0)
	world.camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	world.scenery.forest.update_lod(Vector3.ZERO, 300)
	await shot(prefix + "_overview.png")
	for entry in [{"site": "north_inner_grove", "file": "_forest.png"}, {"site": "west_rock_hollow", "file": "_rock_hollow.png"}]:
		for site in design.camp_sites:
			if site.id != entry.site: continue
			var focus: Vector3 = world.board.point(world.board.cell_at(Vector3(float(site.world[0]), 0, float(site.world[1]))))
			world.hero.position = focus
			world.camera.size = 55
			world.camera.position = focus + Vector3(0, 62, 32)
			world.camera.look_at(focus)
			world.scenery.forest.update_lod(focus, 60)
			await shot(prefix + str(entry.file))
	var river_focus := Vector3(16, 0, 12)
	world.camera.size = 48
	world.camera.position = river_focus + Vector3(0, 62, 32)
	world.camera.look_at(river_focus)
	world.scenery.forest.update_lod(river_focus, 60)
	await shot(prefix + "_river.png")
	world.free()
	quit()
