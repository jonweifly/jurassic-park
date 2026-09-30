extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var board = preload("res://scripts/board.gd").new()
	board.block_terrain(Vector2i(64,64))
	var pawn = preload("res://scenes/models/survivor.tscn").instantiate()
	root.add_child(pawn)
	pawn.navigation = board
	pawn.body_radius = .82
	# Traffic pushes a traveller off the grid center, next replan cuts a tree corner.
	pawn.position = Vector3(-.83,0,.1)
	var goal := Vector3(5,0,-3)
	pawn.route = board.route(pawn.position,goal,false,pawn.body_radius)
	check(not pawn.route.is_empty(),"Detour exists around the tree")
	for frame in range(180):
		if pawn.route.is_empty(): pawn.route = board.route(pawn.position,goal,false,pawn.body_radius)
		pawn.advance(1.0/30)
	check(pawn.position.distance_to(goal) < .2,"Off-center body must recover around tree instead of repeating blocked route")
	pawn.visual.model.rotation.y = 0
	pawn.visual.face(Vector3(0,0,-1),1.0/30)
	check(absf(angle_difference(0,pawn.visual.model.rotation.y)) <= deg_to_rad(12.01),"Facing change must be bounded, even after traffic reverses direction")
	var blocked_starts := 0
	for x in [-.85,-.5,-.32]:
		for z in [-1.8,-1.0,-.2,.2,1.0,1.8,2.2]:
			var from := Vector3(x,0,z)
			if not board.body_open(from,.30): continue
			for to in [Vector3(3,0,-3),Vector3(5,0,3)]:
				var path: PackedVector3Array = board.route(from,to,false,.30)
				if not path.is_empty() and not board.body_segment_open(from,path[0],.30): blocked_starts += 1
	check(blocked_starts == 0,"Replanned routes must have a traversable first segment; blocked="+str(blocked_starts))
	var heavy_path: PackedVector3Array = board.route(Vector3(-3,0,1),Vector3(1,0,-3),false,1.12)
	var previous := Vector3(-3,0,1)
	for waypoint in heavy_path:
		check(board.body_segment_open(previous,waypoint,1.12),"Large dinosaur route must fit between tree corners")
		previous = waypoint
	var corridor := preload("res://scripts/board.gd").new()
	for x in range(128):
		for y in range(128):
			if y not in [64,65]: corridor.block_terrain(Vector2i(x,y))
	check(corridor.body_open(Vector3(-8,0,2),1.12),"Four-meter corridor physically fits a large dinosaur")
	check(not corridor.route(Vector3(-8,0,2),Vector3(8,0,2),false,1.12).is_empty(),"Large dinosaur must navigate a physically wide enough corridor between grid centers")
	pawn.free()
	print("ROUTE RECOVERY failures=",failures)
	quit(1 if failures else 0)
