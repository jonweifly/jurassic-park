extends SceneTree
const Terrain = preload("res://scripts/terrain_data.gd")
const Board = preload("res://scripts/board.gd")
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var layout := Terrain.new()
	var board := Board.new()
	board.layout = layout
	for y in range(128):
		for x in range(128):
			if not layout.walk[y*128+x]: board.block_terrain(Vector2i(x,y))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain.json"))
	var drowned_plots := 0
	var drowned_corners := 0
	var unsafe_walk := 0
	var wet_build := 0
	var shallow := 0
	for z in range(-32,33,2):
		for x in range(-32,33,2):
			var cell := board.cell_at(Vector3(x+1,0,z+1))
			var i := cell.y*128+cell.x
			var depth := layout.water_level_at(x+1,z+1)-layout.height_at(x+1,z+1)
			if source.build[i] and depth > .08: drowned_plots += 1
			if source.build[i]:
				for offset in [Vector2(0,0),Vector2(2,0),Vector2(0,2),Vector2(2,2)]:
					if layout.submerged_at(x+offset.x,z+offset.y): drowned_corners += 1
			if layout.build[i] and depth > .0: wet_build += 1
			if layout.walk[i] and depth > .42: unsafe_walk += 1
			if layout.wading_at(x+1,z+1): shallow += 1
	expect(drowned_plots == 0,"Existing building plots must remain dry: %d" % drowned_plots)
	expect(drowned_corners == 0,"Existing building foundations must remain dry: %d" % drowned_corners)
	expect(wet_build == 0 and unsafe_walk == 0,"New build and walk masks must respect depth")
	expect(shallow >= 6,"Lake must have a useful navigable shallow shelf")
	for p in [Vector3(-17,0,-13),Vector3(-17,0,15),Vector3(17,0,17)]:
		expect(not layout.submerged_at(p.x,p.z),"Former moat is now dry meadow")
		expect(not board.route(board.point(Vector2i(65,62)),p).is_empty(),"Meadow reconnects opening to the mainland")
	expect(layout.height_at(3,-3) < 2.2,"Opening no longer sits on a six metre pedestal")
	expect(layout.submerged_at(17,-17) and not layout.wading_at(17,-17),"Lake retains a deep blocked basin")
	var crossing := board.route(Vector3(9,0,-7),Vector3(29,0,-7))
	var crossed_water := false
	for p in crossing:
		if layout.wading_at(p.x,p.z): crossed_water = true
	expect(not crossing.is_empty() and crossed_water,"Southern shelf must form an actual route through water")
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500,"standard")
	world.hero.position = Vector3(11,layout.height_at(11,-7),-7)
	world.hero.route = world.board.route(world.hero.position,Vector3(29,0,-7),false,world.hero.body_radius)
	var entered := false
	var slowed := false
	for i in range(600):
		world.hero.advance(1.0/60)
		if layout.wading_at(world.hero.position.x,world.hero.position.z):
			entered = true
			if world.hero.current_speed <= world.hero.speed*.71: slowed = true
	expect(entered and slowed,"Live survivor follows the shallow route and slows down")
	expect(world.hero.position.distance_to(Vector3(29,layout.height_at(29,-7),-7)) < 2.1,"Survivor exits the water onto the opposite bank")
	# Use a former walkable pond edge as an old saved actor position.
	var saved := Save.snapshot(world)
	saved.erase("terrain_revision")
	saved.hero.position = Vector3(19,6,-17)
	saved.hero.route = PackedVector3Array([Vector3(3,6,-3)])
	saved.order = "move"
	saved.order_target = Vector3(3,6,-3)
	world.free()
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	expect(Save.validate(saved).is_empty(),"Old terrain saves remain readable")
	Save.apply(world,saved)
	expect(world.board.body_open(world.hero.position,world.hero.body_radius),"Legacy actor is placed on a clear bank")
	expect(absf(world.hero.position.y-layout.height_at(world.hero.position.x,world.hero.position.z)) < .001,"Legacy actor no longer floats at the old plateau height")
	expect(not world.hero.route.is_empty() and absf(world.order_target.y-layout.height_at(3,-3)) < .001,"Legacy destination and route adapt to new terrain")
	expect(Save.snapshot(world).terrain_revision == Save.TERRAIN_REVISION,"Resaved game records the new terrain revision")
	world.free()
	print("OPENING: ",checks," checks, ",failures," failures; shallow cells=",shallow)
	quit(0 if failures == 0 else 1)
