extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0
var world: Node

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func footprint_distance(a: Node3D, b: Node3D) -> float:
	return Vector2(a.position.x-b.position.x,a.position.z-b.position.z).length()
func quiet(d: Node3D) -> void:
	d.route.clear()
	d.speed = 0
	d.set_meta("stationary_test",true)
	d.set_meta("ai_sense_clock",999.0)
	d.set_meta("ai_wander_clock",999.0)

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500,"hard")
	world.spawn_clocks.clear()
	# Use real terrain with room to separate the complete species roster.
	var center := Vector3.ZERO
	var found := false
	for y in range(50,82):
		for x in range(50,90):
			var p: Vector3 = world.board.point(Vector2i(x,y))
			if not world.board.body_open(p,7.0): continue
			center = p
			found = true
			break
		if found: break
	expect(found,"Real island contains an unobstructed mixed-species fixture")
	if not found:
		world.free()
		quit(1)
		return
	world.hero.position = center
	for species in world.Dinosaurs.SPECIES:
		var d: Node3D = world.spawn_dinosaur(center,species)
		quiet(d)
	# Host collision includes both co-op survivors; no transport is needed here.
	world.coop.active = true
	world.coop.hosting = true
	world.hero.set_meta("coop_slot",1)
	world.coop.pawns[1] = world.hero
	world.coop.make_pawn(2)
	var partner: Node3D = world.coop.pawns[2]
	partner.position = center
	for frame in range(180): world.update_dinosaurs(1.0/30)
	var actors: Array = world.survivors()+world.dinosaurs
	var overlaps := 0
	for i in range(actors.size()):
		expect(actors[i].crowd == world.crowd,"Production crowd registers actor "+str(i))
		expect(world.board.body_open(actors[i].position,actors[i].body_radius),"Separation retains terrain clearance for actor "+str(i))
		for j in range(i+1,actors.size()):
			if footprint_distance(actors[i],actors[j]) < actors[i].body_radius+actors[j].body_radius-.01: overlaps += 1
	expect(overlaps == 0,"All seven species and both survivors separate in the production loop")
	expect(world.spawn_dinosaur(world.dinosaurs[0].position,"raptor",true) == null,"Live reinforcements refuse a footprint already occupied by a dinosaur")
	var packet: Dictionary = world.coop.replication.actor_packet()
	expect(packet.players[2].position == partner.position,"Host broadcasts the collision-adjusted partner position")
	for d in world.dinosaurs:
		expect(packet.dinosaurs[d.get_meta("save_id")].position == d.position,"Host broadcasts each collision-adjusted dinosaur position")
	# Dynamic positions round-trip without persisting collision implementation data.
	world.session.mode = "standard"
	var snapshot := Save.snapshot(world)
	expect(Save.validate(snapshot).is_empty(),"Separated production actors remain valid in existing save format")
	expect(not snapshot.hero.has("crowd"),"Spatial buckets do not leak into saves")
	# Direct pounce displacement uses the same swept footprint as normal walking.
	var pouncer: Node3D
	var blocker: Node3D
	for d in world.dinosaurs:
		if d.get_meta("species") == "elite_raptor": pouncer = d
		elif d.get_meta("species") == "trex": blocker = d
		else: d.health = 0
	world.hero.sheltered_id = 123
	partner.sheltered_id = 123
	pouncer.position = center+Vector3(-3,0,0)
	blocker.position = center
	world.crowd.rebuild(world.survivors()+world.dinosaurs)
	var strike := {"special":"pounce","remaining":.1,"duration":.65,"impact":center+Vector3(3,0,0)}
	world.dino_ai.specials.advance(pouncer,strike,.4)
	expect(pouncer.position.x < blocker.position.x and footprint_distance(pouncer,blocker) >= 1.789,"Pounce cannot tunnel through another dinosaur even on a long tick")
	# The non-host path never runs a second local solver against authoritative packets.
	world.coop.hosting = false
	var before: Vector3 = pouncer.position
	world._physics_process(.5)
	expect(pouncer.position == before,"Co-op clients do not apply duplicate collision resolution")
	world.coop.active = false
	# A real attacking pack still reaches and damages a building while keeping space.
	for d in world.dinosaurs: d.free()
	world.dinosaurs.clear()
	world.hero.sheltered_id = -1
	world.hero.position = center+Vector3(0,0,6)
	world.hero.route.clear()
	world.session.wood = 100
	world.session.gold = 100
	var target: Dictionary = world.session.build("tent",world.board.cell_at(center))
	expect(not target.is_empty(),"Battle fixture builds a valid target")
	if target.is_empty():
		world.free()
		quit(1)
		return
	target.remaining = 0
	world.board.block_building(target.cell,target.id)
	world.create_building_visual(target)
	var initial_hp: float = target.hp
	for i in range(6):
		var d: Node3D = world.spawn_dinosaur(center+Vector3(-3.5+i*1.4,0,-5),"raptor",true)
		expect(d != null,"Battle fixture spawns separated pack member "+str(i))
		if not d: continue
		d.position.y = world.board.layout.height_at(d.position.x,d.position.z)
		world.dino_ai.provoke(d,"building",target.id,world.board.point(target.cell))
	var penetration := 0.0
	for frame in range(240):
		world._physics_process(1.0/30)
		for i in range(world.dinosaurs.size()):
			for j in range(i+1,world.dinosaurs.size()):
				var a: Node3D = world.dinosaurs[i]
				var b: Node3D = world.dinosaurs[j]
				penetration = maxf(penetration,a.body_radius+b.body_radius-footprint_distance(a,b))
		if target.hp <= 0: break
	expect(target.hp < initial_hp,"Crowd avoidance still lets the attacking pack damage its building target")
	expect(penetration < .01,"Attacking pack keeps body spacing throughout real movement and combat")
	world.free()
	print("CROWD WORLD: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
