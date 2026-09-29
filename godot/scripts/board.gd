extends RefCounted
const Dinosaurs = preload("res://scripts/dinosaur_catalog.gd")
const SIDE := 128
const TerrainData = preload("res://scripts/terrain_data.gd")
var layout: RefCounted
const CELL := 2.0
var grid := AStarGrid2D.new()
var terrain: Dictionary = {}
var structures: Dictionary = {}
var revision: int = 0
var clearance_grids := {}
var reachability := {}

# AStar exhausts the entire connected region for each impossible destination.
# Cache component membership per body radius and board revision, then retain
# the existing AStar scoring for reachable candidates. Four-way components are
# sufficient: diagonal movement never cuts blocked corners on these grids.
func reachable_candidates(search: AStarGrid2D, radius: float, start: Vector2i, candidates: Array[Vector2i]) -> Array[Vector2i]:
	if candidates.is_empty(): return candidates
	var key := snappedf(radius, 0.01) if radius > 1.0 else 0.0
	if not reachability.has(key) or reachability[key].revision != revision:
		var labels := PackedInt32Array()
		labels.resize(SIDE * SIDE)
		reachability[key] = {"revision":revision, "labels":labels, "next":1}
	var entry: Dictionary = reachability[key]
	var labels: PackedInt32Array = entry.labels
	var origins: Array[Vector2i] = [start]
	if search.is_point_solid(start):
		# Restored actors may depart a blocked start, but it must not permanently
		# join the otherwise separate regions on either side of that cell.
		origins.clear()
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var cell: Vector2i = start + offset
			if inside(cell) and not search.is_point_solid(cell): origins.append(cell)
	var components := []
	for origin in origins:
		var index := origin.y * SIDE + origin.x
		if labels[index] == 0:
			var component: int = entry.next
			entry.next += 1
			var pending := PackedVector2Array([Vector2(origin)])
			var cursor := 0
			labels[index] = component
			while cursor < pending.size():
				var cell := Vector2i(pending[cursor])
				cursor += 1
				for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var neighbour: Vector2i = cell + offset
					if not inside(neighbour): continue
					var next_index := neighbour.y * SIDE + neighbour.x
					if labels[next_index] != 0 or search.is_point_solid(neighbour): continue
					labels[next_index] = component
					pending.append(Vector2(neighbour))
		components.append(labels[index])
	entry.labels = labels
	var result: Array[Vector2i] = []
	for cell in candidates:
		if cell == start or labels[cell.y * SIDE + cell.x] in components: result.append(cell)
	return result

func _init() -> void:
	grid.region = Rect2i(0, 0, SIDE, SIDE)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()

func cell_at(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL) + SIDE / 2, floori(p.z / CELL) + SIDE / 2)

func point(c: Vector2i) -> Vector3:
	var p := Vector3((c.x - SIDE / 2) * CELL + CELL / 2, 0, (c.y - SIDE / 2) * CELL + CELL / 2)
	if layout: p.y = layout.height_at(p.x, p.z)
	return p

func inside(c: Vector2i) -> bool:
	return grid.region.has_point(c)

func block_terrain(c: Vector2i, blocked: bool = true) -> void:
	if not inside(c): return
	if blocked: terrain[c] = true
	elif not layout or layout.walk[c.y * SIDE + c.x]: terrain.erase(c)
	grid.set_point_solid(c, terrain.has(c) or structures.has(c))
	revision += 1

func block_building(c: Vector2i, id: int) -> void:
	structures[c] = id
	grid.set_point_solid(c, true)
	revision += 1

func remove_building(c: Vector2i) -> void:
	structures.erase(c)
	grid.set_point_solid(c, terrain.has(c))
	revision += 1

func is_open(c: Vector2i) -> bool:
	return inside(c) and not grid.is_point_solid(c)

func route(from: Vector3, to: Vector3, adjacent: bool = false, radius: float = 0.0) -> PackedVector3Array:
	var start := cell_at(from)
	var target := cell_at(to)
	var result := PackedVector3Array()
	if not inside(start) or not inside(target): return result
	var search: AStarGrid2D = grid_for_radius(radius)
	var candidates: Array[Vector2i] = []
	if is_open(target) and not search.is_point_solid(target) and not adjacent: candidates.append(target)
	else:
		for x in range(-2 if radius > 1 else -1, 3 if radius > 1 else 2):
			for y in range(-2 if radius > 1 else -1, 3 if radius > 1 else 2):
				var c := target + Vector2i(x, y)
				if is_open(c) and not search.is_point_solid(c): candidates.append(c)
	var best: Array[Vector2i] = []
	var best_score := INF
	candidates = reachable_candidates(search, radius, start, candidates)
	# A restored actor may occupy a newly blocked clearance cell: allow departure only.
	var start_solid := search.is_point_solid(start)
	if start_solid: search.set_point_solid(start, false)
	for c in candidates:
		var path := search.get_id_path(start, c)
		if path.is_empty(): continue
		var score := float(path.size()) + Vector2(c - target).length() * 0.1
		if score < best_score:
			best_score = score
			best = path
	if start_solid: search.set_point_solid(start, true)
	for i in range(1, best.size()): result.append(point(best[i]))
	# A pawn can be inside the destination cell but still en route to its center.
	# Preserve that final segment when a moving pawn replans an adjacent-cell route.
	if best.size() == 1 and from.distance_to(point(best[0])) > 0.05:
		result.append(point(best[0]))
	if radius > 1 and adjacent and not best.is_empty():
		# Finish within the existing bite range while keeping the whole body outside walls.
		var end := result[-1] if not result.is_empty() else from
		var target_point := point(target)
		var delta := target_point - end
		delta.y = 0
		if delta.length() > 2.8:
			var approach := end + delta.normalized() * (delta.length() - 2.8)
			if body_segment_open(end, approach, radius):
				if layout: approach.y = layout.height_at(approach.x, approach.z)
				result.append(approach)
	return result

func load_layout() -> void:
	layout = TerrainData.new()
	for y in range(SIDE):
		for x in range(SIDE):
			if not layout.walk[y * SIDE + x]: block_terrain(Vector2i(x, y))

func can_build(c: Vector2i) -> bool:
	return is_open(c) and (not layout or layout.build[c.y * SIDE + c.x])

static func species_radius(species: String) -> float:
	return Dinosaurs.spec(species).radius

func body_clearance(at: Vector3, radius: float) -> float:
	var low := cell_at(at - Vector3(radius, 0, radius))
	var high := cell_at(at + Vector3(radius, 0, radius))
	var nearest := radius
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			var c := Vector2i(x, y)
			if is_open(c): continue
			var center := Vector2((c.x - SIDE / 2) * CELL + CELL / 2, (c.y - SIDE / 2) * CELL + CELL / 2)
			var distance := (Vector2(at.x, at.z) - center).abs() - Vector2.ONE * CELL / 2
			nearest = minf(nearest, Vector2(maxf(0, distance.x), maxf(0, distance.y)).length())
	return nearest

func body_open(at: Vector3, radius: float) -> bool:
	return is_open(cell_at(at)) and body_clearance(at, radius) >= radius - 0.001

func body_segment_open(from: Vector3, to: Vector3, radius: float) -> bool:
	var clearance := body_clearance(from, radius)
	var steps := maxi(1, ceili(from.distance_to(to) / 0.15))
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / steps)
		var next := body_clearance(p, radius)
		if not is_open(cell_at(p)) or next + 0.001 < minf(radius, clearance): return false
		# Existing penetrations may escape, but cannot get deeper or cross an obstacle.
		clearance = maxf(clearance, next)
	return true

func grid_for_radius(radius: float) -> AStarGrid2D:
	if radius <= 1.0: return grid
	var key := snappedf(radius, 0.01)
	if clearance_grids.has(key) and clearance_grids[key].revision == revision: return clearance_grids[key].grid
	var search := AStarGrid2D.new()
	search.region = grid.region
	search.cell_size = grid.cell_size
	search.diagonal_mode = grid.diagonal_mode
	search.default_compute_heuristic = grid.default_compute_heuristic
	search.default_estimate_heuristic = grid.default_estimate_heuristic
	search.update()
	# Inflate only cells neighbouring obstacles, not all 16k terrain height samples.
	var blocked := terrain.duplicate()
	blocked.merge(structures)
	for cell in blocked:
		for x in range(-1, 2):
			for y in range(-1, 2):
				var c: Vector2i = cell + Vector2i(x, y)
				if not inside(c): continue
				var gap := Vector2(maxf(0, absf(x * CELL) - CELL / 2), maxf(0, absf(y * CELL) - CELL / 2)).length()
				if gap < radius: search.set_point_solid(c, true)
	for i in range(SIDE):
		for c in [Vector2i(i, 0), Vector2i(i, SIDE - 1), Vector2i(0, i), Vector2i(SIDE - 1, i)]: search.set_point_solid(c, true)
	clearance_grids[key] = {"grid": search, "revision": revision}
	return search
