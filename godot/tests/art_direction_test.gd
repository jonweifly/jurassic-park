extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func soil_at(cell: Vector2i) -> float:
	var point: Vector3 = world.board.point(cell)
	# Dummy rendering does not support reading back ImageTexture.update().
	return world.scenery.ground_palette.image.get_pixel(int(point.x+128), int(point.z+128)).r

func run() -> void:
	Save.directory = "user://art_direction_test_fixture"
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500, "standard")
	world.spawn_clocks.clear()
	world.session.wood = 1000
	world.session.gold = 1000
	var cell := Vector2i(65,65)
	world.clear_tree(cell)
	world.scenery.ground_palette.update()
	expect(soil_at(cell) == 0, "Empty plot has no camp soil")
	var ids := []
	for kind in ["tent", "generator", "tower", "lab"]:
		var plot := cell + Vector2i(ids.size()*3,0)
		world.clear_tree(plot)
		var b: Dictionary = world.session.build(kind,plot)
		expect(not b.is_empty(), "Fixture can legally build " + kind)
		if b.is_empty():
			world.free()
			quit(1)
			return
		world.board.block_building(plot,b.id)
		world.create_building_visual(b)
		ids.append(b.id)
		var node: Node3D = world.visuals[b.id]
		var dressing: Node3D = node.get_node("CampDressing")
		expect(not dressing.visible, kind + " dressing stays hidden during construction")
		expect(dressing.find_children("*", "CollisionObject3D", true, false).is_empty(), kind + " dressing cannot block navigation or picking")
		expect(not dressing.find_children("*", "MeshInstance3D", true, false).is_empty(), kind + " has actual imported detail meshes")
		b.remaining = 0.0
		world.preferences.values.quality = 2
		world.scenery.update_building(node,b)
		expect(dressing.visible, kind + " completed detail is visible")
	var rng_state: int = world.rng.state
	var revision: int = world.board.revision
	var terrain: Dictionary = world.board.terrain.duplicate(true)
	var stock := Vector2i(world.session.wood,world.session.gold)
	world.scenery.ground_palette.update()
	expect(soil_at(cell) > .9, "Construction makes compacted soil beneath the tent")
	world.paused = true
	world.preferences.values.quality = 0
	world.preferences.apply(world,false)
	expect(not world.visuals[ids[0]].get_node("CampDressing").visible, "Low detail applies immediately while paused")
	expect(not world.visuals[ids[0]].get_node("CampDetail/Joinery").visible and not world.visuals[ids[0]].get_node("CampDetail/LampLight").visible, "Paused low quality also hides close joinery and the local lamp light")
	world.preferences.values.quality = 2
	world.preferences.apply(world,false)
	expect(world.visuals[ids[0]].get_node("CampDressing").visible, "High detail restores immediately while paused")
	expect(world.visuals[ids[0]].get_node("CampDetail/Joinery").visible and world.visuals[ids[0]].get_node("CampDetail/LampLight").visible, "Paused high quality restores close joinery and local lamp light")
	var specialist: Dictionary = world.session.building(ids[2])
	specialist.refit = "heavy"
	world.preferences.apply(world, false)
	expect(not world.visuals[ids[2]].get_node("CampDressing").visible and not world.visuals[ids[2]].get_node("CampDetail/Joinery").visible, "Paused quality changes preserve the specialist tower's replacement silhouette")
	specialist.refit = ""
	world.preferences.apply(world, false)
	var unfinished: Dictionary = world.session.building(ids[1])
	unfinished.remaining = 2.0
	world.preferences.apply(world,false)
	expect(not world.visuals[ids[1]].get_node("CampDressing").visible, "Quality change does not finish construction visually")
	unfinished.remaining = 0.0
	expect(world.rng.state == rng_state and world.board.revision == revision and world.board.terrain == terrain and Vector2i(world.session.wood,world.session.gold) == stock, "Appearance updates preserve gameplay RNG, navigation and resources")
	world.paused = false
	world.demolish_building(ids[0])
	world.scenery.ground_palette.update()
	expect(soil_at(cell) == 0, "Demolition removes obsolete camp soil")
	var forest_before: PackedByteArray = world.scenery.ground_palette.forest_image.get_data()
	var tree_cell: Vector2i = world.trees.keys()[0]
	world.clear_tree(tree_cell)
	world.scenery.ground_palette.update()
	expect(world.scenery.ground_palette.last_trees == world.trees.size() and forest_before != world.scenery.ground_palette.forest_image.get_data(), "Harvesting refreshes the forest floor mask")
	var snap := Save.snapshot(world)
	expect(Save.validate(snap).is_empty(), "Cosmetic additions preserve a valid save")
	var mask: PackedByteArray = world.scenery.ground_palette.image.get_data()
	world.free()
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	Save.apply(world,snap)
	world.scenery.ground_palette.update()
	expect(world.scenery.ground_palette.image.get_data() == mask, "Loading rebuilds identical surface appearance without saving texture state")
	expect(world.visuals[ids[2]].has_node("CampDressing"), "Loaded buildings recreate independent dressing")
	world.free()
	print("ART DIRECTION: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
