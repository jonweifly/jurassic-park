extends RefCounted
## Read-only topology preview; never temporarily blocks the live navigation grid.
const SIDE := 128
const STEPS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var world: Node
var cache_key := ""
var topology_revision := -1
var baseline := PackedByteArray()
var open := PackedByteArray()
var previews := {}
var evaluations := 0

func _init(owner: Node) -> void:
	world = owner

func index(cell: Vector2i) -> int:
	return cell.y * SIDE + cell.x

func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < SIDE and cell.y >= 0 and cell.y < SIDE

func flood(start: Vector2i, blocked: Vector2i) -> PackedByteArray:
	var visited := PackedByteArray()
	visited.resize(SIDE * SIDE)
	if not inside(start) or start == blocked or open[index(start)] == 0: return visited
	var queue: Array[Vector2i] = [start]
	visited[index(start)] = 1
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for step in STEPS:
			var next: Vector2i = cell + step
			if not inside(next) or next == blocked: continue
			var id := index(next)
			if open[id] == 0 or visited[id] == 1: continue
			visited[id] = 1
			queue.append(next)
	return visited

func tent_access(cells: PackedByteArray, tent: Vector2i) -> bool:
	# Cardinal neighbours are valid work approaches and avoid corner cutting.
	for step in STEPS:
		var cell: Vector2i = tent + step
		if inside(cell) and cells[index(cell)] == 1: return true
	return false

func locally_connected(cell: Vector2i) -> bool:
	var neighbours: Array[Vector2i] = []
	for step in STEPS:
		var next: Vector2i = cell + step
		if inside(next) and world.board.is_open(next): neighbours.append(next)
	if neighbours.size() < 2: return true
	var reached := {neighbours[0]: true}
	var queue: Array[Vector2i] = [neighbours[0]]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for step in STEPS:
			var next: Vector2i = current + step
			if next == cell or maxi(absi(next.x-cell.x),absi(next.y-cell.y)) > 2: continue
			if not inside(next) or not world.board.is_open(next) or reached.has(next): continue
			reached[next] = true
			queue.append(next)
	for neighbour in neighbours:
		if not reached.has(neighbour): return false
	return true

func update_topology() -> void:
	if topology_revision == world.board.revision: return
	topology_revision = world.board.revision
	cache_key = ""
	previews.clear()
	open.resize(SIDE * SIDE)
	for y in range(SIDE):
		for x in range(SIDE): open[y * SIDE + x] = 1 if world.board.is_open(Vector2i(x,y)) else 0

func warning(cell: Vector2i) -> String:
	if not world.board.inside(cell) or not world.board.is_open(cell): return ""
	var near_tent := false
	for b in world.session.buildings:
		if b.hp > 0 and b.kind == "tent" and b.remaining <= 0 and absi(b.cell.x-cell.x)+absi(b.cell.y-cell.y) == 1:
			near_tent = true
			break
	# Almost every open-area placement exits here without a whole-map flood.
	if not near_tent and locally_connected(cell): return ""
	update_topology()
	var hero_cell: Vector2i = world.board.cell_at(world.hero.position)
	var key := "%d:%s" % [world.board.revision, hero_cell]
	if key != cache_key:
		cache_key = key
		previews.clear()
		baseline = flood(hero_cell,Vector2i(-1,-1))
	var reachable_neighbours := 0
	for step in STEPS:
		var next: Vector2i = cell + step
		if inside(next) and baseline[index(next)] == 1: reachable_neighbours += 1
	if not near_tent and reachable_neighbours < 2: return ""
	if not previews.has(cell):
		if previews.size() >= 32: previews.clear()
		evaluations += 1
		previews[cell] = flood(hero_cell,cell)
	var after: PackedByteArray = previews[cell]
	var disconnected := false
	for step in STEPS:
		var next: Vector2i = cell + step
		if inside(next) and baseline[index(next)] == 1 and after[index(next)] == 0:
			disconnected = true
			break
	var old_tents := 0
	var new_tents := 0
	for b in world.session.buildings:
		if b.hp <= 0 or b.kind != "tent" or b.remaining > 0: continue
		if tent_access(baseline,b.cell): old_tents += 1
		if tent_access(after,b.cell): new_tents += 1
	if old_tents > 0 and new_tents == 0: return "将阻断通往帐篷的返送路线"
	if not disconnected: return ""
	var extraction_cell: Vector2i = world.board.cell_at(world.extraction)
	if inside(extraction_cell) and baseline[index(extraction_cell)] == 1 and after[index(extraction_cell)] == 0:
		return "将切断通往 H 撤离点的路线"
	return "将封闭一侧通路，请确认留有出口"
