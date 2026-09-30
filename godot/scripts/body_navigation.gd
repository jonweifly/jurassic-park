extends RefCounted
## One-meter fallback finds usable corridor centers omitted by the two-meter grid.
var owner_ref: WeakRef
var board: RefCounted:
	get: return owner_ref.get_ref()
var caches := {}
func _init(owner: RefCounted) -> void: owner_ref = weakref(owner)
func route(from: Vector3, to: Vector3, adjacent: bool, radius: float) -> PackedVector3Array:
	var key := snappedf(radius,.01)
	if not caches.has(key) or caches[key].revision != board.revision:
		var grid := AStarGrid2D.new()
		grid.region = Rect2i(0,0,257,257)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.update()
		var blocked: Dictionary = board.terrain.duplicate()
		blocked.merge(board.structures)
		for cell in blocked:
			var center := Vector2(cell*2+Vector2i.ONE)
			for x in range(-3,4):
				for y in range(-3,4):
					var c := Vector2i(center)+Vector2i(x,y)
					if not grid.region.has_point(c): continue
					var gap := Vector2(maxf(0,absf(x)-1),maxf(0,absf(y)-1)).length()
					if gap < radius: grid.set_point_solid(c,true)
		for i in range(257):
			for c in [Vector2i(i,0),Vector2i(i,256),Vector2i(0,i),Vector2i(256,i)]: grid.set_point_solid(c,true)
		caches[key] = {"revision":board.revision,"grid":grid,"labels":PackedInt32Array(),"next":1}
		caches[key].labels.resize(257*257)
	var entry: Dictionary = caches[key]
	var grid: AStarGrid2D = entry.grid
	var start := Vector2i(roundi(from.x)+128,roundi(from.z)+128)
	if not grid.region.has_point(start) or grid.is_point_solid(start): return PackedVector3Array()
	var labels: PackedInt32Array = entry.labels
	var index := start.y*257+start.x
	if labels[index] == 0:
		var component: int = entry.next
		entry.next += 1
		var queue: Array[Vector2i] = [start]
		labels[index] = component
		var cursor := 0
		while cursor < queue.size():
			var cell := queue[cursor]
			cursor += 1
			for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var c: Vector2i = cell+offset
				if not grid.region.has_point(c) or grid.is_point_solid(c): continue
				var n := c.y*257+c.x
				if labels[n] != 0: continue
				labels[n] = component
				queue.append(c)
		entry.labels = labels
	var target := Vector2i(roundi(to.x)+128,roundi(to.z)+128)
	var candidates: Array[Vector2i] = []
	for x in range(-3 if adjacent else 0,4 if adjacent else 1):
		for y in range(-3 if adjacent else 0,4 if adjacent else 1):
			var c := target+Vector2i(x,y)
			if not grid.region.has_point(c) or grid.is_point_solid(c) or labels[c.y*257+c.x] != labels[index]: continue
			if adjacent and Vector2(c-target).length() > 2.9: continue
			candidates.append(c)
	candidates.sort_custom(func(a,b): return a.distance_squared_to(start)<b.distance_squared_to(start))
	for candidate in candidates:
		var path := grid.get_id_path(start,candidate)
		var result := PackedVector3Array()
		var previous := from
		var valid := true
		for cell in path:
			var p := Vector3(cell.x-128,0,cell.y-128)
			if board.layout: p.y = board.layout.height_at(p.x,p.z)
			if not board.body_segment_open(previous,p,radius):
				valid = false
				break
			if previous.distance_to(p) > .05: result.append(p)
			previous = p
		if valid: return result
	return PackedVector3Array()
