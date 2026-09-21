extends SceneTree
## Native before/after comfort capture for weather presentation.
## Gameplay systems stay untouched; only render materials and particle presentation are swapped.

const OUT := "res://captures/weather-refinement"
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
const BEFORE_FOLIAGE := "res://tools/fixtures/weather-before/foliage.gdshader"
const BEFORE_FOG := "res://tools/fixtures/weather-before/foliage_fog.gdshader"
const BEFORE_RAIN := "res://tools/fixtures/weather-before/rain.gdshader"

var world: Node
var old_foliage_shader: Shader
var old_fog_shader: Shader
var old_rain_shader: Shader

func _initialize() -> void:
	call_deferred("run")

func save_frame(stage: String, index: int) -> void:
	RenderingServer.force_draw(false)
	var path := OUT.path_join("%s-%02d.png" % [stage,index])
	root.get_texture().get_image().save_png(path)

func settle() -> void:
	world.paused = false
	world.hud.refresh(0)
	world.update_camera(0)
	await process_frame
	await process_frame

func install_before_materials() -> void:
	old_foliage_shader = load(BEFORE_FOLIAGE)
	old_fog_shader = load(BEFORE_FOG)
	old_rain_shader = load(BEFORE_RAIN)
	for material in world.scenery.foliage_cache.values():
		material.shader = old_foliage_shader
	world.scenery.leaf_fog.shader = old_fog_shader
	world.weather.rain_material.shader = old_rain_shader
	var old_mesh := BoxMesh.new()
	old_mesh.size = Vector3(0.018,0.75,0.018)
	old_mesh.material = world.weather.rain_material
	world.weather.drops.mesh = old_mesh
	world.weather.drops.initial_velocity_min = 20.0
	world.weather.drops.initial_velocity_max = 25.0
	world.weather.drops.scale_amount_min = 1.0
	world.weather.drops.scale_amount_max = 1.0

func install_after_materials() -> void:
	for material in world.scenery.foliage_cache.values():
		material.shader = load("res://shaders/foliage.gdshader")
	world.scenery.leaf_fog.shader = load("res://shaders/foliage_fog.gdshader")
	world.weather.rain_material.shader = load("res://shaders/rain.gdshader")
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.018,0.24)
	mesh.material = world.weather.rain_material
	world.weather.drops.mesh = mesh
	world.weather.drops.initial_velocity_min = 18.0
	world.weather.drops.initial_velocity_max = 23.0
	world.weather.drops.scale_amount_min = 0.65
	world.weather.drops.scale_amount_max = 1.15

func set_weather(kind: int, clock: float) -> void:
	world.weather.preview_kind = kind
	world.weather.clock = clock
	world.weather.update()
	world.weather.clock = clock
	world.scenery.update_view(0)
	world.update_lighting()
	world.update_camera(0)
	if world.weather.drops:
		world.weather.drops.restart()

func capture_stage(prefix: String, kind: int, before: bool) -> void:
	set_weather(kind, 47.0)
	await settle()
	for i in range(40):
		# Keep the world simulation frozen while advancing only presentation time.
		world.weather.clock = 47.0 + float(i) * 0.1
		world.scenery.update_view(0)
		world.weather.rain_material.set_shader_parameter("rain_drift",world.weather.direction*world.weather.wind*.35)
		world.paused = false
		await create_timer(0.1).timeout
		save_frame(prefix + ("-before" if before else "-after"),i)

func run() -> void:
	Save.directory = "user://weather_refinement_fixture"
	Preferences.file_path = "user://weather_refinement_fixture/preferences.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	world.camera_size = 25
	world.camera_rig.target_pitch = deg_to_rad(43)
	world.camera_rig.center(true)
	world.update_camera(0)
	world.vision.update()
	# Same camera and weather presets for the before/after captures.
	install_before_materials()
	await capture_stage("gale",1,true)
	await capture_stage("rain",2,true)
	await capture_stage("storm",3,true)
	install_after_materials()
	await capture_stage("gale",1,false)
	await capture_stage("rain",2,false)
	await capture_stage("storm",3,false)
	# Check the thin drops from side-on views and at both zoom limits.
	for i in range(4):
		world.camera_rig.target_yaw = float(i)*PI/2
		world.camera_rig.target_pitch = deg_to_rad(38 if i < 2 else 70)
		world.camera_size = 18 if i < 2 else 68
		world.preferences.values.quality = 0 if i == 3 else 2
		world.update_camera(0)
		world.weather.update()
		await settle()
		await create_timer(0.3).timeout
		save_frame("storm-angle",i)
	print("WEATHER REFINEMENT CAPTURED ",OUT)
	world.queue_free()
	await process_frame
	quit()
