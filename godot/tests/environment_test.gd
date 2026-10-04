extends SceneTree
const Weather = preload("res://scripts/weather.gd")
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func color_brightness(color: Color) -> float:
	return color.r + color.g + color.b

func color_close(a: Color, b: Color, epsilon: float = 0.0001) -> bool:
	return absf(a.r-b.r) < epsilon and absf(a.g-b.g) < epsilon and absf(a.b-b.b) < epsilon
func fixture() -> Node:
	Save.directory = "user://environment_fixture"
	Preferences.file_path = "user://environment_fixture/preferences.cfg"
	var world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	return world
func run() -> void:
	for time in [0,154.99,155.0,244.99,245.0,389.99,390.0,489.99,490.0,589.99,590.0,745.0,1180.0]:
		var a := Weather.sample(time)
		var b := Weather.sample(time+0.01)
		for key in ["wind","rain","cloud","wetness"]:
			expect(a[key]>=0 and a[key]<=1 and absf(a[key]-b[key])<0.002,"Weather boundary continuous: %s at %s" % [key,time])
	expect(Weather.sample(50).rain == 0 and Weather.sample(200).wind > .6,"Breeze and gale are distinct dry conditions")
	expect(Weather.sample(300).rain > .5 and Weather.sample(440).rain > .9,"Rain and thunderstorm reach distinct intensities")
	expect(Weather.sample(620).wetness > .3 and Weather.sample(700).wetness == 0,"Wet ground dries gradually after rain ends")
	var world := fixture()
	var rng_state: int = world.rng.state
	var revision: int = world.board.revision
	var sight: Dictionary = world.vision.visible_cells.duplicate()
	var stocks: Dictionary = Save.snapshot(world).trees
	var families: Dictionary = world.scenery.variation.counts
	# Sky presentation is derived from the saved day phase and weather preset.
	# Clear and storm palettes must both become darker at night, and repeated
	# lighting updates must recompute from constants instead of accumulating.
	world.weather.preview_kind = 0
	world.session.elapsed = 0.0
	world.update_lighting()
	var clear_day_top: Color = world.sky_material.sky_top_color
	var clear_day_horizon: Color = world.sky_material.sky_horizon_color
	var clear_day_sun: float = world.sun.light_energy
	world.update_lighting()
	expect(color_close(clear_day_top,world.sky_material.sky_top_color) and color_close(clear_day_horizon,world.sky_material.sky_horizon_color) and is_equal_approx(clear_day_sun,world.sun.light_energy),"Repeated clear daylight updates do not accumulate sky or light changes")
	world.session.elapsed = world.Catalog.DAY_SECONDS * 0.5
	world.update_lighting()
	var clear_night_top: Color = world.sky_material.sky_top_color
	expect(color_brightness(clear_night_top) < color_brightness(clear_day_top),"Clear night sky is darker than clear daylight")
	world.weather.preview_kind = 3
	world.session.elapsed = 0.0
	world.update_lighting()
	var storm_day_top: Color = world.sky_material.sky_top_color
	var storm_day_horizon: Color = world.sky_material.sky_horizon_color
	var storm_day_fog: float = world.environment.fog_density
	var storm_day_height_density: float = world.environment.fog_height_density
	world.update_lighting()
	expect(color_close(storm_day_top,world.sky_material.sky_top_color) and color_close(storm_day_horizon,world.sky_material.sky_horizon_color) and is_equal_approx(storm_day_fog,world.environment.fog_density),"Repeated storm updates do not accumulate sky or fog changes")
	world.session.elapsed = world.Catalog.DAY_SECONDS * 0.5
	world.update_lighting()
	var storm_night_top: Color = world.sky_material.sky_top_color
	expect(color_brightness(storm_night_top) < color_brightness(storm_day_top),"Storm night sky is darker than storm daylight")
	var fog_epsilon := 0.00001
	var fog_ok: bool = world.environment.fog_density >= 0.0007-fog_epsilon and world.environment.fog_density <= 0.0027+fog_epsilon
	fog_ok = fog_ok and world.environment.fog_height >= 1.0-fog_epsilon and world.environment.fog_height <= 3.5+fog_epsilon
	fog_ok = fog_ok and world.environment.fog_height_density >= 0.010-fog_epsilon and world.environment.fog_height_density <= 0.042+fog_epsilon
	fog_ok = fog_ok and world.environment.fog_sky_affect >= 0.18-fog_epsilon and world.environment.fog_sky_affect <= 0.38+fog_epsilon
	expect(fog_ok,"Rain fog values stay within the intended readable range: density=%f height=%f height_density=%f sky_affect=%f" % [world.environment.fog_density,world.environment.fog_height,world.environment.fog_height_density,world.environment.fog_sky_affect])
	expect(storm_day_height_density > 0.010,"Storm weather raises low height haze above clear weather")
	world.weather.preview_kind = -1
	for family in world.scenery.variation.FAMILIES:
		expect(families.get(family,0)>10,"Independent tree family is present in playable map: "+family)
		var high: Node3D = load("res://assets/models/%s.glb" % family).instantiate()
		var low: Node3D = load("res://assets/models/%s_lod.glb" % family).instantiate()
		var high_vertices := 0
		var low_vertices := 0
		for mesh in high.find_children("*","MeshInstance3D",true,false): high_vertices += mesh.mesh.surface_get_array_len(0)
		for mesh in low.find_children("*","MeshInstance3D",true,false): low_vertices += mesh.mesh.surface_get_array_len(0)
		expect(high_vertices > 500 and low_vertices < high_vertices*.85,"Tree has independent detailed geometry and reduced LOD: "+family)
		high.free()
		low.free()
	var family_cells := []
	for cell in world.trees:
		var tree: Node3D = world.trees[cell].node
		if tree.has_meta("visual_family"): family_cells.append(cell)
		if world.Regions.at(tree.position) == "ice": expect(not tree.has_meta("visual_family"),"Snow trees stay in their original biome")
	for time in [0,200,300,440,620,1100]:
		world.session.elapsed = time
		world.weather.update()
		world.update_lighting()
		world.update_camera(0)
		expect(world.scenery.wind_materials.all(func(m):return is_equal_approx(m.get_shader_parameter("weather_clock"),float(time))),"Foliage and fog overlays use the same saved simulation clock")
		if world.weather.rain > .5:
			expect(world.scenery.foliage_cache.values().all(func(m):return is_equal_approx(float(m.get_shader_parameter("wetness")),world.weather.wetness)),"Rain drives wet canopy material response")
		expect(world.rng.state == rng_state and world.board.revision == revision,"Weather never consumes combat RNG or changes navigation")
		expect(world.vision.visible_cells == sight and Save.snapshot(world).trees == stocks,"Weather preserves enemy visibility and resource stocks")
	world.paused = true
	var time: float = world.weather.clock
	world._physics_process(2.0)
	world.weather.update()
	expect(world.weather.clock == time,"Pause freezes wind and weather schedule")
	var saved := Save.snapshot(world)
	var restored := fixture()
	Save.apply(restored,saved)
	expect(restored.weather.kind == world.weather.kind and is_equal_approx(restored.weather.rain,world.weather.rain),"Save/load restores weather from saved game time")
	expect(restored.scenery.variation.counts == families,"Tree variety stays deterministic after reload")
	expect(restored.rng.state == world.rng.state,"Loading visual variety retains combat randomness")
	restored.free()
	# Harvesting a replaced cluster removes exactly its own instances and cell.
	var cell: Vector2i = family_cells[0]
	var parts: int = world.scenery.forest.cells[cell].size()
	var live: int = world.scenery.forest.live_parts()
	world.clear_tree(cell)
	expect(not world.trees.has(cell) and not world.scenery.forest.cells.has(cell),"Harvest clears the new tree's original resource and render cells")
	expect(world.scenery.forest.live_parts() == live-parts,"Harvest preserves neighboring tree batches")
	# Per-species calls never reveal hidden dinosaurs and repeated view updates do not chorus.
	world.session.elapsed = 100
	world.paused = false
	world.camera_focus = world.hero.position
	world.vision.update()
	var audio = world.sound.dinosaur_audio
	for species in ["small_raptor","raptor","young_trex","trex"]:
		var d: Node3D = world.spawn_dinosaur(world.hero.position,species)
		d.visible = true
		audio.gap = 0
		expect(audio.cue(d) and audio.last_key.begins_with(species+"_call_"),"Encounter selects distinct species call: "+species)
		expect(not audio.cue(d,true),"Attack cannot repeat the same actor's call immediately")
		world.dinosaurs.erase(d)
		d.free()
	var d: Node3D = world.spawn_dinosaur(world.hero.position,"trex")
	world.vision.visible_cells.clear()
	audio.gap = 0
	expect(not audio.cue(d),"No dinosaur audio leaks through unexplored/hidden cells")
	world.vision.update()
	d.visible = true
	audio.heard.clear()
	audio.update(.1)
	var count: int = audio.cue_count
	audio.update(.1)
	expect(audio.cue_count == count,"Continuous visibility does not retrigger encounter calls each frame")
	var second: Node3D = world.spawn_dinosaur(world.hero.position,"trex")
	second.visible = true
	expect(not audio.cue(second,true),"Another heavy attack cannot overlap an ongoing long roar")
	world.free()
	print("ENVIRONMENT: ",checks," checks, ",failures," failures; tree_variants=",families)
	quit(0 if failures == 0 else 1)
