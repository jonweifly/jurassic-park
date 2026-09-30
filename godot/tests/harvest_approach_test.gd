extends SceneTree
## Actual Pawn.advance -> Worker.update regression for contact/replan oscillation.
const Board = preload("res://scripts/board.gd")
var failures := 0
var checks := 0
class Slope extends RefCounted:
	var walk: Array = []
	var gradient := Vector2(0.25, 0.12)
	func _init() -> void: walk.resize(128 * 128); walk.fill(true)
	func height_at(x: float, z: float) -> float: return x * gradient.x + z * gradient.y
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func harvest(w: Node, target: Vector3, label: String) -> void:
	w.worker.cargo = 0
	w.worker.assign("wood", target)
	var limit: float = w.worker.route_length(w.hero.route) + 0.2
	var travelled := 0.0
	var close_on_impact := false
	for i in range(900):
		var before: Vector3 = w.hero.position
		w.hero.advance(1.0/30)
		w.worker.update(1.0/30)
		travelled += before.distance_to(w.hero.position)
		if w.worker.cargo > 0:
			close_on_impact = w.worker.wood_contact(w.hero.position, target)
			break
	expect(w.worker.cargo == 1, label + ": gathers instead of looping")
	expect(travelled <= limit, label + ": never backtracks after arrival")
	expect(close_on_impact, label + ": hits only at trunk contact")
	expect(w.board.body_open(w.hero.position, w.hero.body_radius), label + ": body remains outside tree collision")
func run() -> void:
	load("res://scripts/save_store.gd").directory = "user://harvest_approach_fixture"
	var w: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.start_session(1500, "standard")
	w.hero.crowd = null
	# Real terrain/tree registrations, including uneven ground near spawn.
	var start: Vector3 = w.hero.position
	var cells: Array = w.trees.keys()
	cells.sort_custom(func(a,b): return w.board.point(a).distance_squared_to(start) < w.board.point(b).distance_squared_to(start))
	var sampled := 0
	for cell in cells:
		w.hero.position = start
		var target: Vector3 = w.board.point(cell)
		if w.worker.wood_route(target).is_empty(): continue
		harvest(w, target, "Island tree " + str(cell))
		sampled += 1
		if sampled >= 8: break
	expect(sampled == 8, "Eight real island trees are reachable")
	w.trees.clear()
	w.session.buildings.clear()
	var cell := Vector2i(64,64)
	for gradient in [Vector2.ZERO, Vector2(.25,.12), Vector2(-.25,-.12)]:
		w.board = Board.new()
		w.board.layout = Slope.new()
		w.board.layout.gradient = gradient
		w.hero.navigation = w.board
		w.board.block_terrain(cell)
		w.trees[cell] = {"wood":200}
		var target: Vector3 = w.board.point(cell)
		for offset in [Vector2i(2,2),Vector2i(-2,2),Vector2i(-2,-2),Vector2i(2,-2),Vector2i(2,0),Vector2i(-2,0),Vector2i(0,2),Vector2i(0,-2)]:
			w.hero.position = w.board.point(cell + offset)
			harvest(w, target, "Slope %s approach %s" % [gradient,offset])
			expect(w.worker.wood_route(target).is_empty(), "Already touching tree never routes back to cell centre")
	# Three blocked sides still permit using the fourth, rather than a diagonal dead end.
	for side in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]: w.board.block_terrain(cell + side)
	w.hero.position = w.board.point(cell + Vector2i(0,3))
	var target: Vector3 = w.board.point(cell)
	harvest(w, target, "Only one open side")
	w.board.block_terrain(cell + Vector2i.DOWN)
	w.worker.cargo = 0
	w.hero.position = w.board.point(cell + Vector2i(0,3))
	w.worker.assign("wood", target)
	expect(w.order == "idle" and w.hero.route.is_empty(), "Enclosed tree rejects order instead of endlessly replanning")
	for i in range(60): w.worker.update(1.0/30)
	expect(w.worker.cargo == 0, "Enclosed tree cannot be harvested remotely")
	# Range is rechecked even if a route was interrupted or a pawn was displaced.
	w.board.block_terrain(cell + Vector2i.DOWN, false)
	w.worker.assign("wood", target)
	w.hero.route.clear()
	w.worker.update(2)
	expect(w.worker.cargo == 0 and not w.hero.route.is_empty(), "Far survivor resumes approaching without swinging or awarding wood")
	expect(not w.worker.wood_contact(target + Vector3(1.36,2,0), target), "Large vertical separation cannot count as contact")
	print("HARVEST APPROACH: ", checks, " checks, ", failures, " failures")
	w.free()
	quit(0 if failures == 0 else 1)
