extends RefCounted
## Heavy dinosaurs can break harvestable trees, never cliffs, water or buildings.
const Board = preload("res://scripts/board.gd")
var world: Node
var revision := -1
var forest_board: RefCounted
func _init(owner: Node) -> void: world = owner

func route(from: Vector3, destination: Vector3, radius: float) -> PackedVector3Array:
	if radius <= 1.0: return PackedVector3Array()
	if revision != world.board.revision:
		forest_board = Board.new()
		forest_board.layout = world.board.layout
		for cell in world.board.terrain:
			if world.trees.has(cell) and world.board.layout.walk[cell.y*128+cell.x]: continue
			forest_board.block_terrain(cell)
		for cell in world.board.structures: forest_board.block_building(cell,world.board.structures[cell])
		revision = world.board.revision
	return forest_board.route(from,destination,true,radius)

func clearing(d: Node3D, dt: float) -> bool:
	if d.body_radius <= 1 or d.route.is_empty(): return false
	var end: Vector3 = d.route[0]
	var direction := Vector2(end.x-d.position.x,end.z-d.position.z).normalized()
	var center: Vector2i = world.board.cell_at(d.position)
	var chosen := Vector2i(-1,-1)
	var nearest := INF
	for x in range(-2,3):
		for y in range(-2,3):
			var cell := center+Vector2i(x,y)
			if not world.trees.has(cell) or not world.board.layout.walk[cell.y*128+cell.x]: continue
			var p: Vector3 = world.board.point(cell)
			var delta := Vector2(p.x-d.position.x,p.z-d.position.z)
			var along := delta.dot(direction)
			var across := absf(delta.cross(direction))
			if along < 0 or along > d.body_radius+1.6 or across > d.body_radius+1.05: continue
			if delta.length_squared() < nearest:
				nearest = delta.length_squared()
				chosen = cell
	if chosen.x < 0:
		d.set_meta("ai_tree_clock",0.0)
		return false
	var clock: float = float(d.get_meta("ai_tree_clock",0.0))+dt
	if d.get_meta("ai_tree_cell",chosen) != chosen: clock = dt
	d.set_meta("ai_tree_cell",chosen)
	d.set_meta("ai_tree_clock",clock)
	d.visual.face(world.board.point(chosen)-d.position,dt)
	d.swing = .8
	if clock >= 1.2:
		world.sound.play_at("chop",world.board.point(chosen))
		world.work_impact(world.board.point(chosen),Color("ad8756"))
		world.clear_tree(chosen)
		d.set_meta("ai_tree_clock",0.0)
	return true
