extends RefCounted
## Reliable world changes and bounded, interpolated actor snapshots are separate.
const Save = preload("res://scripts/save_store.gd")
var world: Node
var net: Node
var tree_stocks := {}
var animals := {}
var sequence := 0
var received_sequence := -1
var elapsed := 0.0

func _init(owner_world: Node, session_net: Node) -> void:
	world = owner_world
	net = session_net

func world_packet(full: bool = false) -> Dictionary:
	var trees := {}
	for cell in world.trees: trees[cell] = world.trees[cell].wood
	var changes := {}
	for cell in trees:
		if full or tree_stocks.get(cell,-1) != trees[cell]: changes[cell] = trees[cell]
	for cell in tree_stocks:
		if not trees.has(cell): changes[cell] = 0
	tree_stocks = trees
	var fields: Array = Save.SESSION_FIELDS.duplicate()
	fields.erase("adventure")
	return {"full":full,"session":Save.fields(world.session,fields+["kills_by_species"]),"trees":changes,
		"explored":world.vision.explored.keys(),"focus":world.defense.focus_uid,"players":actor_packet()}

func pawn_packet(pawn: Node3D) -> Dictionary:
	return {"position":pawn.position,"health":pawn.health,"max_health":pawn.max_health,
		"carrying":pawn.carrying,"cargo_kind":pawn.cargo_kind,"visual":Save.visual_state(pawn)}

func actor_packet() -> Dictionary:
	sequence += 1
	var players := {}
	for slot in net.pawns:
		players[slot] = pawn_packet(net.pawns[slot])
		var worker: RefCounted = world.worker if slot == 1 else net.partner.state.worker
		players[slot].worker = Save.fields(worker,Save.WORKER_FIELDS)
		players[slot].order = world.order if slot == 1 else net.partner.state.order
		players[slot].target = world.order_target if slot == 1 else net.partner.state.order_target
	var dinosaurs := {}
	var guns := {}
	for b in world.session.buildings:
		if b.kind=="tower" and world.visuals.has(b.id): guns[b.id]=world.visuals[b.id].get_node("Model/Gun").rotation.y
	for d in world.dinosaurs:
		var packet := pawn_packet(d)
		packet.species = d.get_meta("species")
		packet.strike = d.get_meta("ai_strike",{}).duplicate(true)
		dinosaurs[d.get_meta("save_id")] = packet
	return {"seq":sequence,"players":players,"dinosaurs":dinosaurs,"guns":guns,"time":world.session.elapsed,
		"evacuation":world.session.evacuation_elapsed,"paused":net.room_paused(),"phase":world.session.phase,"boarding":world.session.boarding_progress}

func apply_world(data: Dictionary) -> void:
	for cell in world.trees.keys():
		if (data.full and not data.trees.has(cell)) or data.trees.get(cell,1) <= 0: world.clear_tree(cell)
	for cell in data.trees:
		if world.trees.has(cell): world.trees[cell].wood = data.trees[cell]
	var current := {}
	for b in world.session.buildings: current[b.id] = b
	var wanted := {}
	for b in data.session.buildings:
		if b.hp > 0: wanted[b.id] = b
	for id in world.visuals.keys():
		if not wanted.has(id) or current.get(id,{}).get("kind") != wanted[id].kind:
			if current.has(id): world.board.remove_building(current[id].cell)
			world.visuals[id].free()
			world.visuals.erase(id)
	for key in data.session:
		if key not in ["elapsed","evacuation_elapsed","phase","boarding_progress"]: world.session.set(key,data.session[key])
	for b in world.session.buildings:
		if b.hp <= 0: continue
		var blocked: bool = not b.get("open",false)
		if blocked and world.board.structures.get(b.cell,-1) != b.id: world.board.block_building(b.cell,b.id)
		elif not blocked and world.board.structures.has(b.cell): world.board.remove_building(b.cell)
		if not world.visuals.has(b.id): world.create_building_visual(b)
		world.scenery.update_building(world.visuals[b.id],b)
		if b.kind=="gate": world.visuals[b.id].get_node("Model/Leaf").rotation.y = -PI*.48 if b.get("open",false) else 0.0
	for cell in data.explored: world.vision.explored[cell] = true
	world.defense.focus_uid = data.focus
	apply_actors(data.players)
	world.vision.update()
	world.weather.update_roofs()

func apply_pawn(pawn: Node3D, packet: Dictionary) -> void:
	if not pawn.has_meta("net_target") or pawn.position.distance_to(packet.position)>6: pawn.position=packet.position
	pawn.set_meta("net_from",pawn.position)
	pawn.set_meta("net_target",packet.position)
	pawn.health=packet.health
	pawn.max_health=packet.max_health
	pawn.carrying=packet.carrying
	pawn.cargo_kind=packet.cargo_kind
	Save.restore_visual(pawn,packet.visual)
	pawn.health_label.text="%d / %d" %[maxi(0,int(pawn.health)),int(pawn.max_health)]
	pawn.health_label.visible=pawn.health>0 and pawn.health<pawn.max_health
	pawn.selection.visible=not pawn.is_dinosaur and pawn.health>0

func apply_actors(data: Dictionary) -> void:
	if data.seq<=received_sequence: return
	received_sequence=data.seq
	elapsed=0
	net.last_packet_ms=Time.get_ticks_msec()
	net.server_paused=data.paused
	world.session.elapsed=data.time
	world.session.evacuation_elapsed=data.evacuation
	world.session.phase=data.phase
	world.session.boarding_progress=data.boarding
	for slot in data.players:
		if not net.pawns.has(slot): net.make_pawn(slot)
		apply_pawn(net.pawns[slot],data.players[slot])
		net.pawns[slot].set_meta("net_work_target",data.players[slot].target)
		if slot==net.local_slot:
			Save.restore_fields(world.worker,data.players[slot].worker,Save.WORKER_FIELDS)
			world.order=data.players[slot].order
			world.order_target=data.players[slot].target
	for id in data.guns:
		if world.visuals.has(id): world.visuals[id].set_meta("net_yaw",data.guns[id])
	for id in animals.keys():
		if not data.dinosaurs.has(id):
			world.dinosaurs.erase(animals[id])
			animals[id].queue_free()
			animals.erase(id)
	for id in data.dinosaurs:
		var packet: Dictionary = data.dinosaurs[id]
		if not animals.has(id):
			# Receiving peers instantiate visuals; they never run spawning or AI rules.
			var spec: Dictionary = world.Dinosaurs.spec(packet.species)
			var d: Node3D = load("res://scenes/models/%s.tscn" % spec.model).instantiate()
			d.is_dinosaur=true
			d.scale*=spec.scale
			d.set_meta("species",packet.species)
			d.set_meta("save_id",id)
			world.add_child(d)
			world.dinosaurs.append(d)
			animals[id]=d
		var d: Node3D = animals[id]
		var previous: Dictionary = d.get_meta("ai_strike",{})
		apply_pawn(d,packet)
		d.set_meta("ai_strike",packet.strike)
		if not packet.strike.is_empty() and (previous.is_empty() or packet.strike.remaining>previous.get("remaining",0.0)):
			if packet.strike.has("special"): world.dino_ai.specials.telegraph(d,packet.strike)
			elif packet.strike.get("heavy",false): world.dino_ai.tactics.telegraph(d,packet.strike.remaining)
	world.update_lighting()

func render(dt: float) -> void:
	elapsed+=dt
	for pawn in net.pawns.values()+animals.values():
		if not pawn.has_meta("net_target"): continue
		pawn.position=pawn.get_meta("net_from").lerp(pawn.get_meta("net_target"),clampf(elapsed/.10,0,1))
		if not net.server_paused:
			pawn.visual.player.advance(dt)
			pawn.visual.ground(world.board.layout)
			if pawn.has_meta("net_work_target") and pawn.visual.state in ["chop","mine","build"]:
				pawn.visual.correct_work(pawn.visual.state,pawn.get_meta("net_work_target"),pawn.visual.player.current_animation_position)
	for b in world.session.buildings:
		if b.kind!="tower" or not world.visuals.has(b.id): continue
		var node: Node3D = world.visuals[b.id]
		var gun: Node3D = node.get_node("Model/Gun")
		gun.rotation.y=lerp_angle(gun.rotation.y,node.get_meta("net_yaw",gun.rotation.y),1.0-exp(-14*dt))
		world.scenery.TowerVisuals.update(world.scenery,node,b)
	world.update_effects(dt)
	world.vision.tick(dt)
	world.scenery.clock+=dt if not net.server_paused else 0.0
