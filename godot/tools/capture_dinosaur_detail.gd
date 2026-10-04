extends SceneTree
const KINDS := ["raptor", "trex", "spitter", "alpha_trex"]
var folder := "res://captures/visual-refinement"

func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for kind in KINDS:
		var stage := Node3D.new()
		root.add_child(stage)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("34413b")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color("d4ded2")
		environment.environment.ambient_light_energy = .6
		stage.add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, -25, 0)
		sun.light_energy = 1.8
		stage.add_child(sun)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-25, 140, 0)
		fill.light_color = Color("a2bacb")
		fill.light_energy = .6
		stage.add_child(fill)
		var pawn: Node3D = load("res://scenes/models/%s.tscn" % kind).instantiate()
		pawn.is_dinosaur = true
		stage.add_child(pawn)
		var camera := Camera3D.new()
		stage.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.4 if kind in ["trex", "alpha_trex"] else 1.7
		camera.position = Vector3(4.0, 2.8, 4.0)
		camera.look_at(Vector3(0, 1.55, 1.2))
		camera.current = true
		for action in ["idle", "attack"]:
			var player: AnimationPlayer = pawn.visual.player
			player.play(pawn.visual.clips.get(action, action), 0)
			player.seek(.30 if action == "attack" else 0, true)
			player.advance(0)
			for frame in range(6): await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(folder.path_join("dinosaur-" + kind + "-" + action + ".png"))
		stage.free()
	quit()
