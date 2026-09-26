extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	load("res://scripts/save_store.gd").directory = "user://ground_surfaces_fixture"
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500,"standard")
	var ground: ShaderMaterial = world.scenery.ground
	expect(ground != null and ground.shader != null,"Live terrain has the surface shader")
	for kind in ["turf","soil","litter","rock"]:
		var texture: Texture2D = ground.get_shader_parameter(kind+"_surface")
		expect(texture != null and texture.get_size()==Vector2(1024,1024),kind+" texture is imported and bound to terrain")
		var source := texture.get_image()
		expect(not source.is_empty() and source.get_format()==Image.FORMAT_RGBA8,kind+" carries colour and relief")
		expect(source.has_mipmaps(),kind+" is filtered at distance instead of aliasing")
		var heights := {}
		var colours := {}
		for y in range(0,1024,32):
			for x in range(0,1024,32):
				var pixel := source.get_pixel(x,y)
				heights[pixel.a8] = true
				colours[pixel.to_html(false)] = true
		expect(heights.size()>20 and colours.size()>100,kind+" retains surface variation and relief data")
	var rng_state: int = world.rng.state
	var revision: int = world.board.revision
	for quality in [0,1,2]:
		world.preferences.values.quality = quality
		world.preferences.apply(world,false)
		for weather in [0,2]:
			world.weather.preview_kind = weather
			world.weather.update()
			world.scenery.update_view(0)
			expect(is_equal_approx(float(ground.get_shader_parameter("wetness")),world.weather.wetness),"Actual weather drives ground wetness at each quality")
	expect(world.rng.state==rng_state and world.board.revision==revision,"Surface and quality changes preserve navigation and gameplay RNG")
	world.free()
	print("GROUND SURFACES: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
