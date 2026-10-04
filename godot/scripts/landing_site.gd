extends RefCounted
## Choose a complete flat clearing; checking only the center allowed pads in banks.
static func choose(world: Node, origin: Vector3) -> Vector3:
	var board: RefCounted = world.board
	var preferred := Vector3(1,0,-31)
	var candidates: Array[Vector2i] = []
	for y in range(30,61):
		for x in range(40,90): candidates.append(Vector2i(x,y))
	candidates.sort_custom(func(a,b): return board.point(a).distance_squared_to(preferred) < board.point(b).distance_squared_to(preferred))
	# Map-authored clearings take priority; legacy maps retain their search area.
	var authored: Array[Vector2i] = []
	for site in board.layout.extraction_sites:
		var coords: Array = site.world
		authored.append(board.cell_at(Vector3(float(coords[0]), 0, float(coords[1]))))
	candidates = authored + candidates
	for cell in candidates:
		if not board.inside(cell): continue
		var p: Vector3 = board.point(cell)
		var clear := true
		for x in range(-3,4):
			for y in range(-3,4):
				var nearby := cell+Vector2i(x,y)
				if not board.inside(nearby) or not board.layout.walk[nearby.y*128+nearby.x] or (not board.is_open(nearby) and not world.trees.has(nearby)): clear = false
		if not clear: continue
		var low := p.y
		var high := p.y
		for x in range(-5,6):
			for z in range(-5,6):
				var height: float = board.layout.height_at(p.x+x,p.z+z)
				low = minf(low,height)
				high = maxf(high,height)
		if high-low > 1.2: continue
		var reachable := false
		for offset in [Vector2i(-4,0),Vector2i(4,0),Vector2i(0,-4),Vector2i(0,4)]:
			if not board.route(origin,board.point(cell+offset),false,.3).is_empty(): reachable = true
		if not reachable: continue
		for tree in world.trees.keys():
			if Vector2(tree-cell).length() <= 4: world.clear_tree(tree)
		return p
	push_error("No flat reachable landing clearing found")
	return board.point(Vector2i(64,48))
