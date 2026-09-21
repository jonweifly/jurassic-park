extends SceneTree
const Weather = preload("res://scripts/weather.gd")
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func fixture() -> Node:
	var world = load("res://scenes/main.tscn").instantiate()
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
