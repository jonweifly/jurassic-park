extends Node
## Two-player ENet room. Only this node exposes RPCs; clients send bounded intents.
const PROTOCOL := "jp-coop-2"
const DEFAULT_PORT := 24565
const Actor = preload("res://scripts/coop_actor.gd")
const Replication = preload("res://scripts/coop_replication.gd")
const Save = preload("res://scripts/save_store.gd")
const SAVE_PATH := "user://coop/latest.jpc"
static var save_path := SAVE_PATH
static var reconnect_token := ""
var world: Node
var active := false
var hosting := false
var connected := false
var connecting := false
var local_slot := 1
var acting_slot := 1
var dispatching := false
var pawns := {}
var partner: RefCounted
var replication: RefCounted
var guest_peer := 0
var guest_token := ""
var room_password := ""
var port := DEFAULT_PORT
var status := "局域网或虚拟局域网 · 双人合作"
var server_paused := false
var guest_paused := false
var last_pause := false
var last_packet_ms := 0
var connect_started := 0
var pending := {}
var world_clock := 0.0
var actor_clock := 0.0
var last_command := 0
var command_count := 0
var command_window := 0
var ui: RefCounted
var incoming_sequence := -1
var incoming_chunks := {}
var received_motion_frames := 0

func _ready() -> void:
	world=get_parent()
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_failed)
	multiplayer.server_disconnected.connect(_server_left)
	replication=Replication.new(world,self)

func host(mode: String = "standard", selected_port: int = DEFAULT_PORT, password: String = "", resume: bool = false) -> String:
	if active or connecting or world.started: return "请先返回开始界面再创建合作局。"
	if selected_port<1024 or selected_port>65535 or mode not in ["standard","hard"] or password.length()>64: return "房间设置无效。"
	var saved := read_save() if resume else {}
	if resume and saved.has("error"): return saved.error
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(selected_port,4,3)
	if error != OK: return "无法创建房间，端口可能已被占用。"
	multiplayer.multiplayer_peer=peer
	port=selected_port
	room_password=password
	active=true
	hosting=true
	connected=true
	pawns[1]=world.hero
	world.hero.set_meta("coop_slot",1)
	if resume:
		Save.apply(world,saved.world)
		if saved.has("partner"):
			make_pawn(2)
			partner.run(func():
				Save.restore_fields(world.hero,saved.partner.pawn,Save.PAWN_FIELDS)
				Save.restore_fields(world.worker,saved.partner.worker,Save.WORKER_FIELDS)
				world.order="idle"
				world.hero.route.clear()
				Save.restore_visual(world.hero,saved.partner.visual)
				world.outfitting.apply_equipment(world.hero)
				# Replan field orders on the restored board, keeping personal cargo intact.
				var task: Dictionary = world.outfitting.actor().duplicate(true)
				world.outfitting.cancel()
				if task.task == "collect": world.outfitting.collect(task.target)
				elif task.task == "explore": world.outfitting.explore(task.site)
				elif task.task == "return": world.outfitting.return_home()
				)
		world.paused=false
	else: world.start_session(1500,mode)
	status="房间已创建 · 等待朋友加入"
	decorate_pawn(1)
	return ""

func join(address: String, selected_port: int = DEFAULT_PORT, password: String = "") -> String:
	if active or connecting or world.started: return "请先返回开始界面再加入。"
	address=address.strip_edges()
	if address.is_empty() or address.length()>253 or selected_port<1024 or selected_port>65535 or password.length()>64: return "请输入有效地址和端口。"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address,selected_port,3)
	if error != OK: return "连接创建失败，请检查地址。"
	if reconnect_token.is_empty(): reconnect_token=Crypto.new().generate_random_bytes(24).hex_encode()
	multiplayer.multiplayer_peer=peer
	room_password=password
	port=selected_port
	connecting=true
	connect_started=Time.get_ticks_msec()
	status="正在连接房主……"
	return ""

func _connected() -> void:
	_hello.rpc_id(1,PROTOCOL,room_password,reconnect_token)

func _peer_connected(id: int) -> void:
	if hosting: pending[id]=Time.get_ticks_msec()

@rpc("any_peer","call_remote","reliable",0)
func _hello(protocol: String, password: String, token: String) -> void:
	if not hosting: return
	var sender := multiplayer.get_remote_sender_id()
	if not pending.has(sender): return
	var error := ""
	if protocol != PROTOCOL: error="游戏版本不同，请使用同一版本。"
	elif password != room_password: error="房间口令不正确。"
	elif token.length()!=48: error="连接身份无效。"
	elif guest_peer!=0: error="房间已满，最多两人。"
	elif not guest_token.is_empty() and token!=guest_token: error="此位置保留给掉线队友；请由房主重新创建房间。"
	if not error.is_empty():
		_rejected.rpc_id(sender,error)
		return # Pending handshake expires, allowing the rejection to reach the peer.
	pending.erase(sender)
	guest_peer=sender
	guest_token=token
	guest_paused=false
	last_command=0
	if not pawns.has(2): make_pawn(2)
	world.vision.update()
	_welcome.rpc_id(sender,replication.world_packet(true))
	status="队友已加入 · 双人合作"
	world.hud.toast("队友已加入：共享营地和资源，各自控制幸存者。")

@rpc("authority","call_remote","reliable",0)
func _rejected(message: String) -> void:
	if not connecting: return
	status=message
	close_transport()

@rpc("authority","call_remote","reliable",0)
func _welcome(data: Dictionary) -> void:
	if not connecting: return
	active=true
	hosting=false
	connecting=false
	connected=true
	local_slot=2
	pawns[1]=world.hero
	world.hero.set_meta("coop_slot",1)
	make_pawn(2)
	world.hero=pawns[2]
	world.worker=world.Worker.new(world)
	world.started=true
	world.paused=false
	last_pause=false
	replication.apply_world(data)
	decorate_pawn(1)
	decorate_pawn(2)
	world.camera_rig.center(true)
	status="已加入 · 双人合作"
	if ui: ui.panel.hide()

func make_pawn(slot: int) -> void:
	var pawn: Node3D = world.SurvivorScene.instantiate()
	pawn.name="Survivor%d" % slot
	pawn.navigation=world.board
	pawn.position=spawn_point()
	pawn.speed=world.session.survivor_speed()
	pawn.health=world.session.survivor_max_health()
	pawn.max_health=pawn.health
	pawn.set_meta("coop_slot",slot)
	world.add_child(pawn)
	pawns[slot]=pawn
	if hosting and slot==2: partner=Actor.new(world,pawn)
	decorate_pawn(slot)

func spawn_point() -> Vector3:
	var origin: Vector2i = world.board.cell_at(world.hero.position)
	for radius in range(1,9):
		for x in range(-radius,radius+1):
			for y in range(-radius,radius+1):
				var cell := origin+Vector2i(x,y)
				if not world.board.inside(cell) or not world.board.is_open(cell): continue
				var point: Vector3 = world.board.point(cell)
				if point.distance_to(world.hero.position)<1.5: continue
				if not world.board.route(world.hero.position,point).is_empty(): return point
	return world.hero.position

func decorate_pawn(slot: int) -> void:
	var pawn: Node3D = pawns[slot]
	if not pawn.has_node("CoopName"):
		var label := Label3D.new()
		label.name="CoopName"
		label.position.y=2.5
		label.font_size=24
		label.pixel_size=.012
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		pawn.add_child(label)
	var color := Color("c7f4d6") if slot==local_slot else Color("83c9f1")
	pawn.get_node("CoopName").text=("你" if slot==local_slot else "队友")+ (" · 房主" if slot==1 else "")
	pawn.get_node("CoopName").modulate=color
	pawn.selection.material_override=pawn.selection.material_override.duplicate()
	pawn.selection.material_override.albedo_color=color

func room_paused() -> bool:
	return world.paused or guest_paused if hosting else server_paused

func _process(dt: float) -> void:
	var now := Time.get_ticks_msec()
	if connecting and now-connect_started>10000:
		status="连接超时，请检查房主地址、网络和 UDP 端口。"
		close_transport()
	if not active: return
	if not connected: return
	if hosting:
		for peer in pending.keys():
			if now-pending[peer]>6000:
				multiplayer.multiplayer_peer.disconnect_peer(peer)
				pending.erase(peer)
		world_clock-=dt
		actor_clock-=dt
		if guest_peer>0:
			if world_clock<=0:
				world_clock=.5
				_world_update.rpc_id(guest_peer,replication.world_packet())
			if actor_clock<=0:
				actor_clock=.1
				var packet: Dictionary = replication.actor_packet()
				var bytes := var_to_bytes(packet).compress(FileAccess.COMPRESSION_DEFLATE)
				var count := ceili(bytes.size()/1100.0)
				for index in range(count):
					_actor_chunk.rpc_id(guest_peer,packet.seq,index,count,bytes.slice(index*1100,mini((index+1)*1100,bytes.size())))
	else:
		if now-last_packet_ms>10000:
			_server_left()
			return
		if last_pause!=world.paused:
			last_pause=world.paused
			_pause_request.rpc_id(1,last_pause)
		replication.render(dt)

@rpc("authority","call_remote","reliable",0)
func _world_update(data: Dictionary) -> void:
	if active and not hosting: replication.apply_world(data)

@rpc("authority","call_remote","unreliable",1)
func _actor_chunk(sequence: int, index: int, count: int, bytes: PackedByteArray) -> void:
	if not active or hosting or sequence<=replication.received_sequence or sequence<incoming_sequence: return
	if count<1 or count>128 or index<0 or index>=count or bytes.size()>1100: return
	if sequence!=incoming_sequence:
		incoming_sequence=sequence
		incoming_chunks.clear()
	incoming_chunks[index]=bytes
	if incoming_chunks.size()!=count: return
	var packed := PackedByteArray()
	for part in range(count):
		if not incoming_chunks.has(part): return
		packed.append_array(incoming_chunks[part])
	var data: Variant = bytes_to_var(packed.decompress_dynamic(262144,FileAccess.COMPRESSION_DEFLATE))
	if data is Dictionary and data.get("seq")==sequence:
		received_motion_frames+=1
		replication.apply_actors(data)
	incoming_chunks.clear()

@rpc("any_peer","call_remote","reliable",0)
func _pause_request(value: bool) -> void:
	if hosting and multiplayer.get_remote_sender_id()==guest_peer: guest_paused=value

func _peer_disconnected(id: int) -> void:
	pending.erase(id)
	if not hosting or id!=guest_peer: return
	guest_peer=0
	guest_paused=false
	world.paused=true
	status="队友断线 · 已暂停，可等待重连或继续"
	if partner: partner.run(world.stop_order)

func _failed() -> void:
	status="无法连接房主，请确认地址、端口及双方网络。"
	close_transport()

func _server_left() -> void:
	status="与房主的连接已断开；可返回菜单后重新加入。"
	close_transport()
	world.paused=true
	world.hud.toast(status)

func close_transport() -> void:
	connecting=false
	connected=false
	guest_peer=0
	guest_paused=false
	pending.clear()
	if multiplayer.multiplayer_peer: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
	# Keep active on an already started client: it must never resume as a local simulation.

func route(action: String, args: Array = []) -> bool:
	if not active or dispatching: return false
	if hosting:
		if (guest_paused and action not in ["tech","stop"]) or (world.hero.health<=0 and action!="stop"):
			world.hud.toast("等待队友关闭暂停面板。" if guest_paused else "幸存者已倒下，等待队友救援。")
			return true
		return false
	if not connected:
		world.hud.toast("连接已断开，请返回菜单重连。")
		return true
	# Confirmation dialogs may resume and submit in the same frame. Order the
	# release before its command on the same reliable channel.
	if last_pause!=world.paused:
		last_pause=world.paused
		_pause_request.rpc_id(1,last_pause)
	last_command+=1
	_intent.rpc_id(1,last_command,action,args)
	return true

@rpc("any_peer","call_remote","reliable",0)
func _intent(sequence: int, action: String, args: Array) -> void:
	if not hosting or multiplayer.get_remote_sender_id()!=guest_peer or guest_peer==0: return
	if sequence<=last_command: return
	last_command=sequence
	var now := Time.get_ticks_msec()
	if now-command_window>1000:
		command_window=now
		command_count=0
	command_count+=1
	if command_count>30 or not valid_intent(action,args): return
	if world.session.phase not in ["playing","evacuate"] or pawns[2].health<=0: return
	if room_paused() and action not in ["tech","stop"]:
		_notice.rpc_id(guest_peer,"房间已暂停，请双方关闭暂停面板后操作。")
		return
	dispatching=true
	partner.run(func(): dispatch(action,args))
	dispatching=false
	world_clock=0

func valid_intent(action: String, args: Array) -> bool:
	if args.size()>4 or not Save.safe_data(args): return false
	match action:
		"command", "focus": return args.size()==1 and args[0] is Vector3 and absf(args[0].x)<128 and absf(args[0].z)<128 and absf(args[0].y)<64
		"place": return args.size()==4 and args[0] is String and args[0] in world.Catalog.BUILDINGS and args[1] is Vector2i and world.board.inside(args[1]) and args[2] is float and absf(args[2])<=TAU and args[3] is bool
		"demolish", "repair", "research", "reinforce": return args.size()==1 and args[0] is int and args[0]>0
		"upgrade_base": return args.size()==2 and args[0] is int and args[0]>0 and args[1] in ["laboratory", "workshop"]
		"outfit": return args.size()==3 and args[0] in ["craft", "collect", "explore", "return", "kit"] and args[1] is int and args[2] is String and (args[0]!="craft" or args[2] in world.outfitting.Catalog.ITEMS) and (args[0]!="explore" or args[2] in world.outfitting.Catalog.SITES)
		"refit": return args.size()==2 and args[0] is int and args[1] is String and args[1] in world.Catalog.REFITS
		"priority": return args.size()==2 and args[0] is int and args[1] is int and args[1] in range(3)
		"tech": return args.size()==1 and args[0] is String and args[0] in world.Catalog.TECH
		"heal", "stop", "clear_focus", "revive": return args.is_empty()
	return false

func dispatch(action: String, args: Array) -> void:
	match action:
		"command": world.command(args[0])
		"place":
			world.build_mode=args[0]
			world.build_rotation=args[2]
			if not args[3] and not world.placement_warning(args[1]).is_empty():
				world.hud.toast("此处可能封堵通路，请再次检查建造位置。")
				return
			world.place_building(args[1],true)
		"demolish": world.demolish_building(args[0])
		"repair":
			world.selected_id=args[0]
			world.repair_selected()
		"outfit": world.outfit_action(args[0], args[1], args[2])
		"upgrade_base":
			world.selected_id=args[0]
			world.research(args[1])
		"research":
			world.selected_id=args[0]
			world.research()
		"refit":
			world.selected_id=args[0]
			world.refit_selected(args[1])
		"reinforce":
			world.selected_id=args[0]
			world.reinforce_selected()
		"priority": world.set_tower_priority(args[0],args[1])
		"tech": world.begin_technology(args[0])
		"heal": world.heal()
		"stop": world.stop_order()
		"focus": world.defense.mark_at(args[0])
		"clear_focus": world.clear_focus()
		"revive": revive()

@rpc("authority","call_remote","reliable",0)
func _notice(message: String) -> void:
	if active and not hosting: world.hud.toast(message)

func forward_notice(message: String) -> bool:
	if hosting and active and connected and guest_peer>0:
		_notice.rpc_id(guest_peer,message)
	return hosting and acting_slot==2

func effect(kind: String, args: Array) -> void:
	if hosting and active and connected and guest_peer>0: _effect.rpc_id(guest_peer,kind,args)

@rpc("authority","call_remote","unreliable",2)
func _effect(kind: String, args: Array) -> void:
	if not active or hosting or not connected: return
	match kind:
		"impact":
			if world.encounter: world.encounter.impact(args[0], args[1])
		"tracer": world.tracer(args[0],args[1],args[2])
		"sound": world.sound.play_at(args[0],args[1],args[2],args[3])
		"dinosaur":
			if replication.animals.has(args[0]): world.sound.play_dinosaur(replication.animals[args[0]],args[1])
		"tower":
			if world.visuals.has(args[0]): world.scenery.TowerVisuals.fire(world.visuals[args[0]],world.scenery.clock)

func tick_partner(dt: float) -> void:
	if partner: partner.tick(dt)

func revive() -> void:
	if route("revive"): return
	if not active or not hosting or room_paused() or world.hero.health<=0: return
	for pawn in pawns.values():
		if pawn==world.hero or pawn.health>0: continue
		if world.hero.position.distance_to(pawn.position)>3 or not world.vision.clear_line(world.board.cell_at(world.hero.position),world.board.cell_at(pawn.position)):
			world.hud.toast("请先靠近倒下的队友（3 米内）。")
			return
		if world.session.gold<10:
			world.hud.toast("救起队友需要 10 黄金。")
			return
		world.session.gold-=10
		pawn.health=pawn.max_health*.35
		pawn.dying=false
		pawn.death_clock=.8
		pawn.route.clear()
		pawn.play_animation("idle",0)
		world.hud.toast("队友已被救起，建议返回帐篷治疗。")
		world_clock=0
		return
	world.hud.toast("当前没有需要救起的队友。")

func all_down() -> bool:
	return pawns.values().all(func(p): return p.health<=0)

func all_inside() -> bool:
	var living := pawns.values().filter(func(p): return p.health>0)
	return not living.is_empty() and living.all(func(p): return p.position.distance_to(world.extraction)<world.Catalog.EXTRACTION_RADIUS)

func save_game() -> String:
	if not hosting: return "合作存档由房主保存。"
	var data := {"protocol":PROTOCOL,"world":Save.snapshot(world)}
	if partner:
		data.partner={"pawn":Save.fields(pawns[2],Save.PAWN_FIELDS),"worker":Save.fields(partner.state.worker,Save.WORKER_FIELDS),"visual":Save.visual_state(pawns[2])}
	var error := Save.validate(data.world)
	if not error.is_empty(): return "请在房主存活时保存合作局。"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
	var bytes := var_to_bytes(data)
	var file := FileAccess.open(save_path+".tmp",FileAccess.WRITE)
	if not file: return "无法写入合作存档。"
	file.store_buffer(bytes)
	file.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path+".tmp"),ProjectSettings.globalize_path(save_path))!=OK: return "无法替换合作存档。"
	return ""

static func read_save() -> Dictionary:
	var file := FileAccess.open(save_path,FileAccess.READ)
	if not file: return {"error":"没有合作存档。"}
	if file.get_length()>4194304: return {"error":"合作存档无效。"}
	var data: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	# Live peers require the current protocol; older local saves can still migrate.
	if not data is Dictionary or data.get("protocol") not in ["jp-coop-1", PROTOCOL] or not data.get("world") is Dictionary or not Save.safe_data(data): return {"error":"合作存档版本或数据无效。"}
	if not Save.validate(data.world).is_empty(): return {"error":"合作存档校验失败。"}
	if data.has("partner"):
		var pawn = load("res://scripts/pawn.gd").new()
		var worker = load("res://scripts/worker.gd").new(null)
		var good: bool = data.partner is Dictionary and data.partner.get("pawn") is Dictionary and data.partner.get("worker") is Dictionary and Save.valid_visual(data.partner.get("visual"))
		if good: good=Save.matches(data.partner.pawn,pawn,Save.PAWN_FIELDS) and Save.matches(data.partner.worker,worker,Save.WORKER_FIELDS)
		pawn.free()
		if not good: return {"error":"队友存档无效。"}
	return data

func menu() -> void:
	if hosting and active and world.session.phase in ["playing","evacuate"]:
		var error := save_game()
		if not error.is_empty():
			world.hud.confirm_discard(error+"\n仍然离开房间？未保存的合作进度将丢失。",return_to_menu)
			return
	return_to_menu()

func return_to_menu() -> void:
	close_transport()
	get_tree().reload_current_scene()

func _exit_tree() -> void:
	if active or connecting: close_transport()
