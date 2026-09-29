extends SceneTree
const Board = preload("res://scripts/board.gd")
const Crowd = preload("res://scripts/crowd.gd")
const Survivor = preload("res://scenes/models/survivor.tscn")
var checks := 0
var failures := 0
var bodies: Array = []

class Body extends Node3D:
	var health := 100.0
	var body_radius := 0.48
	var navigation: RefCounted
	var crowd: RefCounted
	var sheltered := false
	func is_sheltered() -> bool: return sheltered
	func segment_open(from: Vector3, to: Vector3) -> bool:
		return navigation.body_segment_open(from,to,body_radius)

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func body(board: RefCounted, at: Vector3, radius: float = 0.48) -> Node3D:
	var pawn := Body.new()
	pawn.position = at
	pawn.body_radius = radius
	pawn.navigation = board
	bodies.append(pawn)
	return pawn

func clean() -> void:
	for pawn in bodies: pawn.free()
	bodies.clear()

func distance(a: Node3D, b: Node3D) -> float:
	return Vector2(a.position.x-b.position.x,a.position.z-b.position.z).length()

func run() -> void:
	var board := Board.new()
	var crowd := Crowd.new()
	var a := body(board,Vector3(-2,0,1),.30)
	var b := body(board,Vector3(1,0,1),1.28)
	crowd.rebuild(bodies)
	var landing := crowd.move(a,Vector3(5,0,1),false)
	expect(landing.x < b.position.x-1.57 and landing.x > -1, "Long survivor step stops at a large dinosaur body without tunnelling")
	expect(not crowd.segment_open(b,b.position,a.position), "Large dinosaur cannot walk through survivor")
	var rev := board.revision
	b.health = 0
	expect(crowd.move(a,Vector3(5,0,1),false) == Vector3(5,0,1), "Dead bodies immediately release occupancy")
	b.health = 100
	b.sheltered = true
	expect(crowd.move(a,Vector3(5,0,1),false) == Vector3(5,0,1), "Sheltered survivors do not block outside units")
	expect(board.revision == rev, "Unit occupancy never invalidates static AStar caches")
	bodies.erase(b)
	b.free()
	expect(crowd.space_open(Vector3(1,0,1),1.0), "Removed units are ignored before the next bucket rebuild")
	crowd.separate(1.0/30)
	clean()
	# Idle legacy overlaps separate under a bounded speed and respect walls.
	a = body(board,Vector3(1,0,1),.48)
	b = body(board,a.position,1.12)
	crowd.rebuild(bodies)
	crowd.separate(1.0/30)
	expect(a.position.distance_to(Vector3(1,0,1)) <= .081 and b.position.distance_to(Vector3(1,0,1)) <= .081, "Stacked old saves separate gradually without teleportation")
	for frame in range(60):
		crowd.rebuild(bodies)
		crowd.separate(1.0/30)
	expect(distance(a,b) >= 1.638, "Coincident mixed-size bodies recover their full footprints")
	board.block_building(Vector2i(65,64),1) # Wall occupies x=2..4.
	a.position = Vector3(1.50,0,1)
	b.position = Vector3(1.0,0,1)
	a.body_radius = .48
	b.body_radius = .48
	for frame in range(60):
		crowd.rebuild(bodies)
		crowd.separate(1.0/30)
	expect(a.position.x <= 1.521 and board.body_open(a.position,a.body_radius), "Crowd pressure cannot push a body through a building")
	expect(distance(a,b) >= .998, "Wall-side overlap resolves into available space")
	clean()
	# Exercise actual Pawn.advance routes, not only the contact helper.
	board = Board.new()
	a = Survivor.instantiate()
	b = Survivor.instantiate()
	root.add_child(a)
	root.add_child(b)
	bodies = [a,b]
	for pawn in bodies: pawn.navigation = board
	a.position = Vector3(-4,0,1)
	b.position = Vector3(4,0,1)
	a.route = PackedVector3Array([b.position])
	b.route = PackedVector3Array([a.position])
	var closest := INF
	for frame in range(120):
		crowd.rebuild(bodies)
		crowd.separate(1.0/30)
		a.advance(1.0/30)
		b.advance(1.0/30)
		closest = minf(closest,distance(a,b))
	expect(closest >= .639, "Head-on survivors retain body spacing throughout movement")
	expect(a.position.distance_to(Vector3(4,0,1)) < .1 and b.position.distance_to(Vector3(-4,0,1)) < .1, "Head-on traffic passes and completes both commands")
	a.position = Vector3(-4,0,1)
	b.position = Vector3(0,0,1)
	a.route = PackedVector3Array([b.position,Vector3(4,0,1)])
	b.route.clear()
	for frame in range(180):
		crowd.rebuild(bodies)
		a.advance(1.0/30)
	expect(a.position.distance_to(Vector3(4,0,1)) < .1, "Occupied intermediate waypoint is bypassed rather than orbited forever")
	# A single-file passage waits behind a stopped ally, then resumes the same order.
	for x in range(-6,8):
		board.block_terrain(board.cell_at(Vector3(2*x+1,0,-1)))
		board.block_terrain(board.cell_at(Vector3(2*x+1,0,3)))
	a.body_radius = .60
	b.body_radius = .60
	a.position = Vector3(-3,0,1)
	b.position = Vector3(1,0,1)
	a.route = PackedVector3Array([Vector3(7,0,1)])
	for frame in range(90):
		crowd.rebuild(bodies)
		a.advance(1.0/30)
	expect(a.position.x < 0 and not a.route.is_empty() and not a.movement_blocked, "Narrow traffic queues without cancelling the route or clipping walls")
	b.health = 0
	for frame in range(120):
		crowd.rebuild(bodies)
		a.advance(1.0/30)
	expect(a.position.distance_to(Vector3(7,0,1)) < .1, "Traffic resumes automatically when the blocking unit dies")
	clean()
	# A compact restored crowd must spread, with local work bounded under 30 Hz.
	board = Board.new()
	for i in range(48): body(board,Vector3((i%8)*.22,0,(i/8)*.22),.48 if i%4 else 1.12)
	var samples: Array = []
	for frame in range(240):
		var start := Time.get_ticks_usec()
		crowd.rebuild(bodies)
		crowd.separate(1.0/30)
		samples.append((Time.get_ticks_usec()-start)/1000.0)
	var overlaps := 0
	for i in range(bodies.size()):
		for j in range(i+1,bodies.size()):
			if distance(bodies[i],bodies[j]) < bodies[i].body_radius+bodies[j].body_radius-.03: overlaps += 1
	samples.sort()
	print("CROWD PERFORMANCE 48 restored overlaps: P95=",samples[228]," ms, residual overlaps=",overlaps)
	expect(overlaps == 0, "Dense restored crowd resolves visible trunk overlaps")
	expect(samples[228] < 12, "Local crowd solver stays below 12 ms P95 for 48 stacked bodies")
	clean()
	for i in range(128): body(board,Vector3((i%16)*6-45,0,(i/16)*6-21),.48)
	crowd.rebuild(bodies)
	crowd.separate(1.0/30)
	expect(crowd.pair_checks < 128*8, "Sparse 128-body world avoids an all-pairs collision scan")
	clean()
	print("CROWD COLLISION: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
