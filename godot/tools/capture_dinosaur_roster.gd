extends SceneTree
const Catalog = preload("res://scripts/dinosaur_catalog.gd")
var folder := "res://captures/dinosaur-roster"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1600, 1000)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("25352f")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("cbd9c4")
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	stage.add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70, 70)
	floor.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("596052")
	material.roughness = 0.95
	floor.material_override = material
	stage.add_child(floor)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	camera.position = Vector3(4, 15, 24)
	camera.look_at(Vector3(0, 1, -1))
	camera.current = true
	var kinds := ["small_raptor", "raptor", "young_trex", "trex", "spitter", "elite_raptor", "alpha_trex"]
	var positions := [Vector3(-8,0,5), Vector3(-3.6,0,5), Vector3(1.3,0,5), Vector3(7,0,5), Vector3(-7,0,-4), Vector3(-1.5,0,-4), Vector3(5.5,0,-4)]
	for i in range(kinds.size()):
		var spec := Catalog.spec(kinds[i])
		var d: Node3D = load("res://scenes/models/%s.tscn" % spec.model).instantiate()
		d.is_dinosaur = true
		d.scale = Vector3.ONE * spec.scale
		stage.add_child(d)
		d.position = positions[i]
		d.visual.model.rotation.y = -0.45
		d.visual.play("idle", 0.3)
		var title := Label3D.new()
		title.text = spec.name
		title.font_size = 40
		title.pixel_size = 0.012
		title.position = positions[i] + Vector3(0, 0.2, 2.5)
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		title.no_depth_test = true
		stage.add_child(title)
	var ui := CanvasLayer.new()
	stage.add_child(ui)
	var heading := Label.new()
	heading.text = "侏罗纪生存 · 恐龙图鉴\n独立骨骼模型 / 鳞片材质 / 精英与首领"
	heading.position = Vector2(32, 24)
	heading.add_theme_font_size_override("font_size", 26)
	ui.add_child(heading)
	for i in range(12): await process_frame
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.get_texture().get_image().save_png(folder.path_join("roster.png"))
	stage.free()
	await capture_encounter()
	quit()

func capture_encounter() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500, "hard")
	world.session.wood = 1000
	world.session.gold = 1000
	world.session.elapsed = 1200
	world.session.technologies.defense = true
	world.spawn_clocks.clear()
	world.weather.preview_kind = 0
	for x in range(55, 74):
		for y in range(76, 89): world.clear_tree(Vector2i(x, y))
	for entry in [["tent", Vector2i(60,81)], ["generator", Vector2i(59,79)], ["tower", Vector2i(64,81)], ["tower", Vector2i(65,79)], ["tower", Vector2i(62,83)], ["shelter", Vector2i(64,83)], ["fire", Vector2i(61,79)]]:
		var b: Dictionary = world.session.build(entry[0], entry[1])
		b.remaining = 0.0
		world.board.block_building(b.cell, b.id)
		world.create_building_visual(b)
	world.hero.position = world.board.point(Vector2i(61,81))
	world.vision.update()
	var attackers := []
	for entry in [["alpha_trex", Vector2i(64,85), 6], ["spitter", Vector2i(69,80), 3], ["elite_raptor", Vector2i(61,85), 5]]:
		var d: Node3D = world.spawn_dinosaur(world.board.point(entry[1]), entry[0])
		if not d: continue
		load("res://scripts/hard_difficulty.gd").strengthen(d, 0.7)
		var b: Dictionary = world.session.building(entry[2])
		world.dino_ai.provoke(d, "building", b.id, world.board.point(b.cell))
		world.dino_ai.attack_if_close(d)
		world.dino_ai.resolve_strike(d, 0.2)
		attackers.append(d)
	world.vision.update()
	world.update_effects(0.2)
	world.camera_rig.following = false
	world.camera_focus = world.board.point(Vector2i(64,82))
	world.camera_size = 29
	world.camera_rig.target_yaw = 0.15
	world.camera_rig.target_pitch = deg_to_rad(48)
	world.update_lighting()
	world.update_camera(0)
	world.hud.refresh(0)
	for i in range(12): await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(folder.path_join("encounter.png"))
	print("ENCOUNTER CAPTURE actors=", attackers.size())
	world.free()
