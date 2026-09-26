extends SceneTree
const Coop = preload("res://scripts/coop_session.gd")
var world: Node
var checks := 0
var failures := 0
var port := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func make_world() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled=false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)

func run() -> void:
	port=26000+int(Time.get_ticks_usec()%10000)
	Coop.save_path="user://coop_rules_%d/latest.jpc" % Time.get_ticks_usec()
	make_world()
	expect(world.coop.host("standard",port).is_empty(),"Coop host starts")
	world.coop.make_pawn(2)
	world.spawn_clocks.clear()
	var host: Node3D = world.hero
	var guest: Node3D = world.coop.pawns[2]
	var worker: RefCounted = world.worker
	var selected: int = world.selected_id
	world.session.wood=1000
	world.session.gold=1000
	world.build_mode="tower"
	world.build_rotation=PI
	world.coop.partner.run(func():
		world.selected_id=777
		world.build_mode="gate"
		world.build_rotation=PI*.5
		world.worker.cargo=2
		world.worker.cargo_kind="wood"
		world.command(world.board.point(Vector2i(65,64))))
	expect(world.hero==host and world.worker==worker and world.selected_id==selected,"Remote scope restores host identity, worker and selection")
	expect(world.build_mode=="tower" and world.build_rotation==PI and world.order=="idle","Remote commands do not overwrite host build preview or order")
	expect(world.worker.cargo==0 and world.coop.partner.state.worker.cargo==2,"Each survivor owns a separate cargo")
	world.coop.partner.tick(.1)
	expect(world.hero==host and world.pointer_feedback!=null,"Partner tick restores input and actor context")
	world.build_mode=""
	world.coop.partner.run(world.stop_order)
	guest.position=world.board.point(Vector2i(65,64))
	host.position=world.board.point(Vector2i(65,62))
	var d: Node3D = world.spawn_dinosaur(guest.position,"raptor")
	d.position=guest.position+Vector3(1,0,0)
	d.set_meta("ai_home",d.position)
	world.vision.update()
	var target: Dictionary = world.dino_ai.visible_target(d)
	expect(target.get("kind")=="hero" and target.get("id")==2,"Dinosaur targets nearby guest instead of distant host")
	d.set_meta("ai_state","alert")
	d.set_meta("ai_target_kind","hero")
	d.set_meta("ai_target_id",2)
	d.attack_cooldown=0
	var host_hp: float = host.health
	var guest_hp: float = guest.health
	world.dino_ai.attack_if_close(d)
	world.dino_ai.resolve_strike(d,1)
	expect(guest.health<guest_hp and host.health==host_hp,"Dinosaur bite damages the targeted guest only")
	d.set_meta("ai_target_id",1)
	d.position=host.position+Vector3(1,0,0)
	d.attack_cooldown=0
	world.dino_ai.attack_if_close(d)
	world.dino_ai.resolve_strike(d,1)
	expect(host.health<host_hp,"Dinosaur can still bite the host")
	guest.position=host.position+Vector3(1.8,0,0)
	host_hp=host.health
	guest_hp=guest.health
	world.dino_ai.specials.resolve(d,{"special":"stomp","impact":host.position})
	expect(host.health<host_hp and guest.health<guest_hp,"Area attacks damage both exposed survivors")
	d.health=0
	var kills: int = world.session.kills
	world.dino_ai.update_death(d,.1)
	world.dino_ai.update_death(d,.1)
	expect(world.session.kills==kills+1,"One dinosaur death rewards the shared team once")
	guest.health=0
	world.session.gold=20
	expect(not world.coop.all_down(),"One downed survivor does not fail the team")
	world.coop.revive()
	expect(guest.health>0 and world.session.gold==10,"Nearby living host revives guest for exactly ten gold")
	world.coop.revive()
	expect(world.session.gold==10,"Repeated revive does not spend again")
	host.health=0
	world.coop.partner.run(world.coop.revive)
	expect(host.health>0 and world.session.gold==0,"Guest can revive the host through its own context")
	host.position=world.extraction
	guest.position=world.board.point(Vector2i(65,64))
	expect(not world.coop.all_inside(),"Extraction waits for the other living survivor")
	guest.position=world.extraction+Vector3(1,0,0)
	expect(world.coop.all_inside(),"Both living survivors can extract together")
	world.session.phase="evacuate"
	world.session.boarding_progress=world.Catalog.BOARDING_SECONDS-.01
	world._physics_process(.02)
	expect(world.session.phase=="won","Shared boarding completes one team victory")
	world.session.phase="playing"
	host.health=0
	guest.health=0
	world._physics_process(.02)
	expect(world.session.phase=="lost","All down fails the entire team")
	host.health=host.max_health
	guest.health=guest.max_health
	world.session.phase="playing"
	world.session.gold=1000
	world.session.wood=1000
	host.position=world.board.point(Vector2i(65,62))
	guest.position=world.board.point(Vector2i(65,64))
	world.session.elapsed=200
	var count: int = world.director.living_count()
	world.director.spawn_group(["small_raptor"])
	expect(world.director.living_count()==count+2,"After grace period coop adds a bounded support dinosaur")
	world.session.elapsed=0
	count=world.director.living_count()
	world.director.spawn_group(["small_raptor"])
	expect(world.director.living_count()==count+1,"Coop opening keeps original group size")
	world.coop.guest_paused=true
	var previous: Vector3 = host.position
	world.command(previous+Vector3(4,0,0))
	expect(world.order=="idle","Host cannot move while guest has paused the room")
	world.coop.guest_paused=false
	world.coop.partner.state.worker.cargo=3
	world.coop.partner.state.worker.cargo_kind="gold"
	expect(world.coop.save_game().is_empty(),"Coop game saves separately from single-player")
	var data := Coop.read_save()
	expect(not data.has("error") and data.partner.worker.cargo==3,"Coop save preserves partner cargo")
	world.free()
	make_world()
	expect(world.coop.host("standard",port,"",true).is_empty(),"New room restores saved coop world")
	expect(world.coop.pawns.size()==2 and world.coop.partner.state.worker.cargo==3 and world.coop.partner.state.worker.cargo_kind=="gold","Restore preserves both survivors and does not duplicate cargo")
	var before := Vector2i(world.session.wood,world.session.gold)
	for request in [["place",["invalid",Vector2i.ZERO,0.0,true]],["place",["gate",Vector2i(-1,0),0.0,true]],["place",["gate",Vector2i(65,62),NAN,true]],["priority",[1,99]],["demolish",["all"]],["tech",["unknown"]],["set_gold",[99999]]]:
		expect(not world.coop.valid_intent(request[0],request[1]),"Reject malformed or unauthorized intent "+request[0])
	expect(before==Vector2i(world.session.wood,world.session.gold),"Invalid intents leave economy unchanged")
	var file := FileAccess.open(Coop.save_path,FileAccess.WRITE)
	file.store_buffer(var_to_bytes({"protocol":"old"}))
	file.close()
	expect(Coop.read_save().has("error"),"Corrupted or incompatible coop saves are rejected")
	world.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Coop.save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Coop.save_path.get_base_dir()))
	print("COOP RULES: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
