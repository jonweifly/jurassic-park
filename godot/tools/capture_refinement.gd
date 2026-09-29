extends SceneTree
## Side-view inspection uses the production pawn and animation/IK path.
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
const OUT := "res://captures/refinement"

class FlatGround extends RefCounted:
	func height_at(_x: float, _z: float) -> float: return 0.0

func _initialize() -> void: call_deferred("run")

func shot(name: String) -> void:
	for frame in range(3): await process_frame
	RenderingServer.force_draw(false)
	print("REFINEMENT CAPTURE ", name, " ", root.get_texture().get_image().save_png(OUT.path_join(name + ".png")))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.content_scale_size = Vector2i(640, 480)
	DisplayServer.window_set_size(Vector2i(640, 480))
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("273831")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c0c6bc")
	environment.environment.ambient_light_energy = 0.7
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.shadow_enabled = true
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("72816a")
	material.roughness = 1.0
	plane.material = material
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position = Vector3(8, 2.4, 2.5)
	camera.look_at(Vector3(0, 1.05, 0))
	camera.make_current()
	for action in ["walk", "carry"]:
		var pawn: Node3D = load("res://scenes/models/survivor.tscn").instantiate()
		stage.add_child(pawn)
		pawn.navigation = load("res://scripts/board.gd").new()
		pawn.navigation.layout = FlatGround.new()
		pawn.carrying = action == "carry"
		pawn.cargo_kind = "wood"
		pawn.selection.hide()
		for frame in range(120):
			pawn.route = PackedVector3Array([pawn.position + Vector3(0, 0, 8)])
			pawn.advance(1.0 / 60)
			# Follow the moving pawn without changing its locomotion speed.
			pawn.position = Vector3.ZERO
			if frame >= 60 and frame % 2 == 0: await shot("%s-%02d" % [action, (frame - 60) / 2])
		pawn.free()
	stage.free()
	root.content_scale_size = Vector2i(1440, 900)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	Save.directory = "user://refinement_capture_fixture"
	Preferences.file_path = Save.directory.path_join("preferences.cfg")
	var world: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500, "standard")
	world.spawn_clocks.clear()
	world.hud.preferences_panel.open()
	world.hud.preferences_panel.tabs.current_tab = 3
	world.hud.refresh(0)
	await shot("audio-settings")
	world.free()
	quit()
