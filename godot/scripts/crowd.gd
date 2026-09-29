extends RefCounted
## Local body occupancy, independent of the static AStar grid. Host simulation only.
## Radii are world-space trunk footprints, not animated heads/tails or rigid bodies.
const CELL := 4.0
const GAP := 0.04
var buckets := {}
var cells := {}
var actors: Array = []
var max_radius := 0.0
var pair_checks := 0

func active(pawn: Variant) -> bool:
	return is_instance_valid(pawn) and not pawn.is_queued_for_deletion() and pawn.health > 0 and not pawn.is_sheltered()

func key(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.z / CELL))

func rebuild(pawns: Array) -> void:
	buckets.clear()
	cells.clear()
	actors.clear()
	max_radius = 0.0
	pair_checks = 0
	for pawn in pawns:
		if not is_instance_valid(pawn): continue
		register(pawn)

func register(pawn: Node3D) -> void:
	if not is_instance_valid(pawn): return
	pawn.crowd = self
	if not active(pawn): return
	if not cells.has(pawn.get_instance_id()): actors.append(pawn)
	max_radius = maxf(max_radius, pawn.body_radius)
	relocate(pawn)

func relocate(pawn: Node3D) -> void:
	var id := pawn.get_instance_id()
	var cell := key(pawn.position)
	if cells.has(id):
		if cells[id] == cell: return
		buckets[cells[id]].erase(pawn)
		if buckets[cells[id]].is_empty(): buckets.erase(cells[id])
	if not buckets.has(cell): buckets[cell] = []
	buckets[cell].append(pawn)
	cells[id] = cell

func nearby(from: Vector3, to: Vector3, radius: float) -> Array:
	var margin := radius + max_radius + GAP
	var low := key(Vector3(minf(from.x,to.x)-margin,0,minf(from.z,to.z)-margin))
	var high := key(Vector3(maxf(from.x,to.x)+margin,0,maxf(from.z,to.z)+margin))
	var result: Array = []
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			for pawn in buckets.get(Vector2i(x,y),[]):
				if active(pawn): result.append(pawn)
	return result

func segment_open(pawn: Node3D, from: Vector3, to: Vector3) -> bool:
	var delta := Vector2(to.x-from.x,to.z-from.z)
	var length_squared := delta.length_squared()
	for other in nearby(from,to,pawn.body_radius):
		if other == pawn: continue
		pair_checks += 1
		var offset := Vector2(from.x-other.position.x,from.z-other.position.z)
		var radius: float = pawn.body_radius + other.body_radius + GAP
		# Legacy overlaps can escape but must not move deeper or cross through.
		if offset.length_squared() < radius*radius - 0.00001:
			if offset.dot(delta) < -0.000001: return false
			continue
		var t := clampf(-offset.dot(delta) / maxf(length_squared,0.000001),0,1)
		if (offset + delta*t).length_squared() < radius*radius - 0.00001: return false
	return true

func occupied(pawn: Node3D, at: Vector3) -> bool:
	return not space_open(at,pawn.body_radius,pawn)

func space_open(at: Vector3, body_radius: float, pawn: Node3D = null) -> bool:
	for other in nearby(at,at,body_radius):
		if other == pawn: continue
		var radius: float = body_radius + other.body_radius + GAP
		if Vector2(at.x-other.position.x,at.z-other.position.z).length_squared() < radius*radius: return false
	return true

func move(pawn: Node3D, destination: Vector3, steer: bool = true) -> Vector3:
	if not active(pawn): return pawn.position
	var start: Vector3 = pawn.position
	if segment_open(pawn,start,destination): return destination
	var delta := destination-start
	delta.y = 0
	# Consistent right-hand passing prevents head-on actors choosing the same side.
	if steer:
		for angle in [0.65,-0.65,1.15,-1.15,PI*0.5,-PI*0.5]:
			var candidate := start + delta.rotated(Vector3.UP,angle)
			if segment_open(pawn,start,candidate) and pawn.segment_open(start,candidate): return candidate
	# Stop at body contact rather than tunnelling on a long tick or pounce.
	var low := 0.0
	var high := 1.0
	for i in range(8):
		var middle := (low+high)*0.5
		if segment_open(pawn,start,start+delta*middle): low=middle
		else: high=middle
	return start+delta*low

func separate(dt: float) -> void:
	if dt <= 0: return
	# Bounded correction recovers old stacked saves without teleporting or pushing
	# anybody through terrain. Large bodies yield less, with a per-actor speed cap.
	var remaining := {}
	for pawn in actors:
		if active(pawn): remaining[pawn.get_instance_id()] = minf(dt,0.1)*2.4
	for pass_index in range(3):
		for pawn in actors:
			if not active(pawn): continue
			for other in nearby(pawn.position,pawn.position,pawn.body_radius):
				if pawn == other or pawn.get_instance_id() > other.get_instance_id(): continue
				pair_checks += 1
				var delta: Vector3 = pawn.position-other.position
				delta.y = 0
				var distance := delta.length()
				var overlap: float = pawn.body_radius+other.body_radius+GAP-distance
				if overlap <= 0.001: continue
				if distance < 0.0001:
					# Stable simulation order, without consuming the gameplay RNG.
					var angle := float(actors.find(pawn)*17+actors.find(other)*31)*2.399963
					delta = Vector3(cos(angle),0,sin(angle))
				else: delta /= distance
				var mass_a: float = pawn.body_radius*pawn.body_radius
				var mass_b: float = other.body_radius*other.body_radius
				push(pawn,delta*overlap*mass_b/(mass_a+mass_b),remaining)
				push(other,-delta*overlap*mass_a/(mass_a+mass_b),remaining)

func push(pawn: Node3D, delta: Vector3, remaining: Dictionary) -> void:
	var id := pawn.get_instance_id()
	delta = delta.limit_length(remaining[id])
	if delta.length_squared() < 0.0000001: return
	var start: Vector3 = pawn.position
	var candidate := start+delta
	if not pawn.segment_open(start,candidate):
		candidate = start+Vector3(delta.x,0,0)
		if absf(delta.x) < 0.0001 or not pawn.segment_open(start,candidate):
			candidate = start+Vector3(0,0,delta.z)
			if not pawn.segment_open(start,candidate): return
	remaining[id] -= start.distance_to(candidate)
	pawn.position = candidate
	if pawn.navigation and pawn.navigation.layout: pawn.position.y = pawn.navigation.layout.height_at(candidate.x,candidate.z)
	relocate(pawn)
