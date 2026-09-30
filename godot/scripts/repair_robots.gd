extends RefCounted
## Shared camp utility drones. Only the host spends wood and runs repairs.
const Visual = preload("res://scripts/pawn_visual.gd")
var world: Node
var visuals: Array[Node3D] = []
var routes := {}
var targets := {}
var retry := {}
func _init(owner: Node) -> void: world = owner

func deploy(workshop: Dictionary) -> void:
	var center: Vector3 = world.board.point(workshop.cell)
	var point := center
	for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var candidate: Vector3 = world.board.point(workshop.cell+offset)
		if world.board.body_open(candidate,.2):
			point = candidate
			break
	world.outfitting.data().robots.append({"position":point,"workshop":int(workshop.id),"clock":0.0})
	sync_visuals()

func sync_visuals() -> void:
	var robots: Array = world.outfitting.data().robots
	while visuals.size() > robots.size(): visuals.pop_back().queue_free()
	while visuals.size() < robots.size():
		var node := Node3D.new()
		node.name = "RepairRobot"
		world.add_child(node)
		Visual.box(node,Vector3(.65,.30,.62),Vector3.ZERO,Color("7c9c8b"))
		Visual.box(node,Vector3(.35,.12,.28),Vector3(0,.20,0),Color("d7bd75"))
		for x in [-.43,.43]:
			for z in [-.35,.35]:
				Visual.box(node,Vector3(.40,.06,.12),Vector3(x,.05,z),Color("314b40"))
		Visual.box(node,Vector3(.10,.34,.10),Vector3(0,-.28,.32),Color("d6be80"))
		var label := Label3D.new()
		label.text = "维修"
		label.font = world.hud.font
		label.font_size = 22
		label.pixel_size = .012
		label.position.y = .6
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		node.add_child(label)
		world.vision.shade(node)
		visuals.append(node)
	for i in range(robots.size()):
		visuals[i].position = robots[i].position + Vector3.UP*.9
		visuals[i].visible = world.vision.is_visible(world.board.cell_at(robots[i].position))

func find_job(index: int, robot: Dictionary) -> void:
	var workshop: Dictionary = world.session.building(robot.workshop)
	if workshop.is_empty() or workshop.remaining > 0: return
	var candidates: Array = world.session.buildings.filter(func(b): return b.hp > 0 and b.remaining <= 0 and b.hp < world.Catalog.max_health(b) and world.board.point(b.cell).distance_to(world.board.point(workshop.cell)) <= 24 and not targets.values().has(b.id))
	candidates.sort_custom(func(a,b): return a.hp/world.Catalog.max_health(a) < b.hp/world.Catalog.max_health(b))
	for b in candidates:
		var route: PackedVector3Array = world.board.route(robot.position,world.board.point(b.cell),true,.2)
		if route.is_empty() and robot.position.distance_to(world.board.point(b.cell)) > 2.9: continue
		targets[index] = b.id
		routes[index] = route
		return

func update(dt: float) -> void:
	var robots: Array = world.outfitting.data().robots
	for i in range(robots.size()):
		var robot: Dictionary = robots[i]
		var workshop: Dictionary = world.session.building(robot.workshop)
		if workshop.is_empty():
			for b in world.session.buildings:
				if b.kind == "workshop" and b.hp > 0 and b.remaining <= 0:
					robot.workshop = b.id
					break
		if world.session.building(robot.workshop).is_empty(): continue
		if not world.session.technologies.has("mechanical") or world.session.supply() < world.session.demand(): continue
		var target: Dictionary = world.session.building(targets.get(i,-1))
		if target.is_empty() or target.remaining > 0 or target.hp >= world.Catalog.max_health(target):
			targets.erase(i)
			routes.erase(i)
			retry[i] = float(retry.get(i,0.0))-dt
			if retry[i] <= 0:
				retry[i] = 1.0
				find_job(i,robot)
			continue
		var route: PackedVector3Array = routes.get(i,PackedVector3Array())
		if not route.is_empty():
			var next: Vector3 = robot.position.move_toward(route[0],3.5*dt)
			if not world.board.body_segment_open(robot.position,next,.2):
				targets.erase(i)
				routes.erase(i)
				continue
			robot.position = next
			if next.distance_to(route[0]) < .02: route.remove_at(0)
			routes[i] = route
			continue
		if robot.position.distance_to(world.board.point(target.cell)) > 2.9:
			targets.erase(i)
			continue
		if world.session.wood < 1: continue
		robot.clock = minf(1.0,robot.clock+dt)
		if robot.clock >= 1:
			robot.clock = 0.0
			world.session.wood -= 1
			target.hp = minf(world.Catalog.max_health(target),target.hp+world.Catalog.max_health(target)*.08)
			world.dino_ai.emit_noise(robot.position,5.0,"building",target.id)
			world.work_impact(world.board.point(target.cell),Color("94c9ac"))
	sync_visuals()
