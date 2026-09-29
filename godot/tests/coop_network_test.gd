extends SceneTree
var world: Node
var role := "host"
var folder := ""
var port := 24566
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks+=1
	print(role," CHECK ",message," ",ok)
	if not ok:
		failures+=1
		push_error(message)

func signal_phase(name: String, data: Dictionary = {}) -> void:
	FileAccess.open(folder.path_join(name+".json"),FileAccess.WRITE).store_string(JSON.stringify(data))

func wait_phase(name: String, seconds: float = 20) -> Dictionary:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while not FileAccess.file_exists(folder.path_join(name+".json")) and Time.get_ticks_msec()<end: await process_frame
	if not FileAccess.file_exists(folder.path_join(name+".json")):
		expect(false,"Timed out waiting for "+name)
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(name+".json")))

func until(condition: Callable, message: String, seconds: float = 12) -> void:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<end: await process_frame
	expect(condition.call(),message)

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	world.hud.refresh(0)
	for i in range(8): await process_frame
	RenderingServer.force_draw(false)
	var out := "res://captures/coop/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	expect(root.get_texture().get_image().save_png(out.path_join(name+".png"))==OK,"Native two-process screenshot "+name)

func plot(kind: String) -> Vector2i:
	world.build_mode=kind
	var origin: Vector2i = world.board.cell_at(world.hero.position)
	for y in range(-4,5):
		for x in range(-4,5):
			var cell := origin+Vector2i(x,y)
			if world.placement_error(cell).is_empty() and world.placement_warning(cell).is_empty(): return cell
	return Vector2i(-1,-1)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role=arg.trim_prefix("--role=")
		if arg.begins_with("--fixture="): folder=arg.trim_prefix("--fixture=")
		if arg.begins_with("--port="): port=int(arg.trim_prefix("--port="))
	load("res://scripts/save_store.gd").directory="user://coop_network_test"
	world=load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled=false
	root.add_child(world)
	current_scene=world
	world.sound.set_process(false)
	if role=="host": await run_host()
	else: await run_client()
	print("COOP NETWORK ",role,": ",checks," checks, ",failures," failures")
	signal_phase(role+"-done",{"checks":checks,"failures":failures})
	world.free()
	quit(0 if failures==0 else 1)

func run_host() -> void:
	expect(world.coop.host("standard",port,"camp").is_empty(),"Host binds an actual ENet UDP port")
	world.prepare_demo()
	for d in world.dinosaurs: d.free()
	world.dinosaurs.clear()
	world.spawn_clocks.clear()
	world.session.wood=1000
	world.session.gold=1000
	var host_position: Vector3 = world.hero.position
	signal_phase("listening")
	await until(func(): return world.coop.guest_peer>0,"Authenticated second process joins")
	await wait_phase("moved")
	expect(world.hero.position.is_equal_approx(host_position),"Guest movement does not move the host")
	expect(world.worker.delivered==0,"Guest work does not replace host worker")
	await wait_phase("harvested",35)
	expect(world.coop.partner.state.worker.delivered>0,"Guest deposits into authoritative shared economy")
	await wait_phase("build-ready")
	world.session.wood=12
	world.session.gold=12
	world.coop.world_clock=0
	signal_phase("limited-stock")
	await wait_phase("built")
	expect(world.session.wood==0 and world.session.gold==0,"Duplicate build intents charge once, never below zero")
	var b: Dictionary = world.session.buildings.back()
	expect(b.kind=="gate" and is_equal_approx(b.get("rotation",0),PI*.5),"Authoritative gate retains requested orientation")
	world.session.wood=1000
	world.session.gold=1000
	b.remaining=0.0
	world.coop.world_clock=0
	signal_phase("gate-complete",{"id":b.id})
	await wait_phase("gate-open")
	expect(b.open and world.board.is_open(b.cell),"Guest gate interaction changes host navigation")
	await wait_phase("demolished")
	expect(world.session.building(b.id).is_empty(),"Guest demolition removes authoritative building")
	var tower_id := -1
	for building in world.session.buildings:
		if building.kind=="tower": tower_id=building.id
		if building.kind=="lab":
			world.selected_id=building.id
			world.research()
	world.session.tick(10)
	world.update_buildings(0)
	world.selected_id=-1
	world.coop.world_clock=0
	signal_phase("technology-ready",{"tower":tower_id})
	await wait_phase("research-started")
	expect(world.session.research_job.get("tech")=="tower_engineering","Guest research uses host-side prerequisites and costs")
	world.session.tick(25)
	world.coop.world_clock=0
	await wait_phase("refit-started")
	expect(world.session.building(tower_id).get("refit")=="rapid","Guest refit updates authoritative tower")
	world.session.tick(12)
	world.update_buildings(0)
	var power_cell := plot("generator")
	var generator: Dictionary = world.session.build("generator", power_cell)
	generator.remaining = 0.0
	world.board.block_building(power_cell, generator.id)
	world.create_building_visual(generator)
	var gear_cell := plot("lab")
	var workshop: Dictionary = world.session.build("lab", gear_cell)
	workshop.remaining = 0.0
	world.board.block_building(gear_cell, workshop.id)
	world.create_building_visual(workshop)
	world.build_mode = ""
	world.coop.world_clock = 0
	signal_phase("workshop-foundation", {"id":workshop.id})
	await until(func(): return workshop.kind == "workshop", "Guest workshop upgrade reaches host")
	world.session.tick(15)
	world.update_buildings(0)
	world.coop.world_clock = 0
	await until(func(): return world.outfitting.data().jobs.has(str(workshop.id)), "Guest craft request starts host production")
	expect(world.outfitting.data().jobs[str(workshop.id)].owner == "2", "Network craft retains personal owner")
	world.outfitting.update(18)
	world.coop.world_clock = 0
	await wait_phase("gear-collected")
	expect(world.outfitting.data().actors["2"].boots == 1 and world.outfitting.data().actors["1"].boots == 0, "Network pickup equips guest only")
	# A crowded packet must span several datagrams and still reassemble as one frame.
	world.set_physics_process(false)
	for i in range(24):
		var dinosaur: Node3D = world.spawn_dinosaur(world.hero.position,["raptor","trex","spitter"][i%3])
		dinosaur.position+=Vector3((i%6)*1.1,0,(i/6)*1.1)
		dinosaur.health=500+i
	world.coop.world_clock=0
	signal_phase("crowded",{"count":24})
	await wait_phase("crowded-received")
	for dinosaur in world.dinosaurs: dinosaur.free()
	world.dinosaurs.clear()
	world.set_physics_process(true)
	await until(func(): return world.coop.guest_paused,"Guest pause pauses room")
	var frozen: float = world.session.elapsed
	await create_timer(.5).timeout
	expect(is_equal_approx(world.session.elapsed,frozen),"Shared clock freezes during guest pause")
	signal_phase("paused")
	await wait_phase("unpaused")
	await until(func(): return not world.coop.room_paused(),"Guest resume releases room")
	await wait_phase("disconnecting")
	await until(func(): return world.coop.guest_peer==0,"Host detects disconnection")
	var partner_id: int = world.coop.pawns[2].get_instance_id()
	expect(world.paused,"Disconnect pauses room and retains guest")
	signal_phase("disconnected")
	await until(func(): return world.coop.guest_peer>0,"Same guest reconnects",25)
	expect(world.coop.pawns[2].get_instance_id()==partner_id,"Reconnect retains same pawn, health and cargo")
	world.paused=false
	await wait_phase("rejoined")
	world.coop.close_transport()
	signal_phase("host-closed")
	await wait_phase("client-done")

func run_client() -> void:
	expect(world.coop.join("127.0.0.1",port,"camp").is_empty(),"Client connects through loopback UDP")
	await until(func(): return world.coop.connected,"Handshake and initial world snapshot arrive")
	if not world.coop.connected: return
	expect(world.coop.local_slot==2 and world.hero==world.coop.pawns[2],"Client controls its own survivor")
	expect(world.session.wood==1000 and world.session.buildings.size()==8,"Late join restores shared camp and resources")
	signal_phase("admitted")
	await capture("05-client-joined")
	var start: Vector3 = world.hero.position
	var dest := plot("tent")
	world.build_mode=""
	world.command(world.board.point(dest))
	await until(func(): return world.hero.position.distance_to(start)>1,"Authoritative movement is replicated")
	signal_phase("moved")
	await until(func(): return world.order=="idle","Guest movement completes")
	await until(func(): return world.coop.received_motion_frames>=5,"High-frequency motion frames reassemble independently of world updates",5)
	var tree_target := Vector3.ZERO
	var best := INF
	for cell in world.trees:
		var point: Vector3 = world.board.point(cell)
		if not world.vision.explored.has(cell) or world.board.route(world.hero.position,point,true).is_empty(): continue
		var distance: float = world.hero.position.distance_to(point)
		if distance<best:
			best=distance
			tree_target=point
	world.command(tree_target)
	await until(func(): return world.worker.delivered>0,"Guest harvest, return and resource delivery synchronize",30)
	world.stop_order()
	signal_phase("harvested")
	signal_phase("build-ready")
	await wait_phase("limited-stock")
	await until(func(): return world.session.wood==12,"Resource changes come from host")
	var cell := plot("gate")
	expect(cell.x>=0,"Guest can find an affordable legal gate plot")
	var count: int = world.session.buildings.size()
	world.coop.route("place",["gate",cell,PI*.5,true])
	world.coop.route("place",["gate",cell,PI*.5,true])
	world.coop.route("place",["gate",Vector2i(-500,-500),PI*.5,true])
	world.coop.route("set_gold",[999999])
	await until(func(): return world.session.buildings.size()==count+1,"Two placement requests create one building")
	expect(world.session.wood==0 and world.session.gold==0,"Client receives exact one-time cost")
	world.build_mode=""
	signal_phase("built")
	var info := await wait_phase("gate-complete")
	var id := int(info.get("id",-1))
	await until(func(): return world.session.building(id).get("remaining",1)<=0,"Completion snapshot arrives")
	var gate: Dictionary = world.session.building(id)
	world.command(world.board.point(gate.cell))
	await until(func(): return world.session.building(id).get("open",false),"Gate open state synchronizes",10)
	expect(world.board.is_open(gate.cell),"Client passage matches host")
	expect(world.visuals[id].basis.is_equal_approx(Basis(Vector3.UP,PI*.5)),"Client visual retains rotated gate")
	await capture("06-client-gate")
	signal_phase("gate-open")
	world.demolish_building(id)
	await until(func(): return world.session.building(id).is_empty(),"Demolition and refunds synchronize")
	signal_phase("demolished")
	var research_info := await wait_phase("technology-ready")
	await until(func(): return world.session.has_completed("laboratory"),"Laboratory upgrade synchronizes")
	world.begin_technology("tower_engineering")
	await until(func(): return world.session.research_job.get("tech")=="tower_engineering","Client can start shared technology research")
	signal_phase("research-started")
	await until(func(): return world.session.technologies.has("tower_engineering"),"Research unlock reaches client")
	var tower_id := int(research_info.get("tower",-1))
	world.selected_id=tower_id
	world.refit_selected("rapid")
	await until(func(): return world.session.building(tower_id).get("refit")=="rapid","Client tower upgrade is accepted")
	signal_phase("refit-started")
	var gear_info := await wait_phase("workshop-foundation")
	var workshop_id := int(gear_info.get("id", -1))
	await until(func(): return not world.session.building(workshop_id).is_empty(), "New foundation reaches client")
	world.selected_id = workshop_id
	world.research("workshop")
	await until(func(): return world.session.building(workshop_id).get("kind") == "workshop" and world.session.building(workshop_id).get("remaining", 1) <= 0, "Workshop branch and completion synchronize")
	world.outfit_action("craft", workshop_id, "boots")
	await until(func(): return world.outfitting.data().jobs.get(str(workshop_id), {}).get("remaining", 1) <= 0, "Ready equipment is replicated to client")
	world.outfit_action("collect", workshop_id)
	await until(func(): return world.outfitting.actor().boots == 1, "Guest travels and receives equipment over ENet")
	expect(is_equal_approx(world.hero.speed, world.session.survivor_speed() * 1.1) and world.outfitting.data().actors["1"].boots == 0, "Client applies its own boot speed without equipping host")
	signal_phase("gear-collected")
	await wait_phase("crowded")
	var motion_frames: int = world.coop.received_motion_frames
	await until(func(): return world.dinosaurs.size()==24 and world.coop.received_motion_frames>=motion_frames+5,"Crowded dinosaur snapshots reassemble across datagrams")
	expect(world.visuals[tower_id].get_meta("tower_variant","")=="rapid","Client displays the independently modeled upgraded tower")
	expect(world.dinosaurs.all(func(d): return d.health>=500),"Crowded snapshots retain per-dinosaur health")
	await capture("07-client-defense")
	signal_phase("crowded-received")
	world.paused=true
	await wait_phase("paused")
	world.paused=false
	signal_phase("unpaused")
	await until(func(): return not world.coop.server_paused,"Guest sees resume")
	signal_phase("disconnecting")
	world.coop.close_transport()
	await wait_phase("disconnected")
	world.free()
	world=load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled=false
	root.add_child(world)
	current_scene=world
	world.sound.set_process(false)
	expect(world.coop.join("127.0.0.1",port,"camp").is_empty(),"Reconnect uses same session token")
	await until(func(): return world.coop.connected,"Reconnect receives current snapshot")
	expect(world.worker.delivered>0,"Reconnect preserves personal work history")
	signal_phase("rejoined")
	await wait_phase("host-closed")
	await until(func(): return not world.coop.connected,"Host shutdown disables guest commands")
	var elapsed: float = world.session.elapsed
	await create_timer(.3).timeout
	expect(is_equal_approx(world.session.elapsed,elapsed) and world.paused,"Disconnected client cannot become an independent authority")
