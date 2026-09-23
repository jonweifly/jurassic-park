extends RefCounted
const Catalog = preload("res://scripts/expedition_catalog.gd")
const Contracts = preload("res://scripts/expedition_contracts.gd")
const Features = preload("res://scripts/feature_policy.gd")
var contracts: RefCounted
var world: Node
var visuals: Dictionary = {}
var reserved: Dictionary = {}
var refresh_clock := 0.0
var noise_clock := 0.0

func _init(owner_world: Node) -> void:
	world = owner_world
	contracts = Contracts.new(world)

func data() -> Dictionary:
	return world.session.adventure

func initialize(content_seed: int = 0) -> void:
	if not Features.peripheral_enabled: return
	if data().is_empty(): world.session.adventure = Catalog.empty_state()
	if data().sites.is_empty():
		if content_seed > 0: data().run = Catalog.Run.create(content_seed)
		for id in Catalog.SITE_ORDER:
			var cell := choose_cell(Catalog.SITES[id].at)
			if cell.x < 0:
				push_error("No reachable expedition site: " + id)
				continue
			data().sites[id] = {"cell": cell, "status": "hidden", "progress": 0.0, "choice": -1, "paid": false}
			reserve(id, cell)
	for id in data().sites:
		if not visuals.has(id): add_visual(id)

func reserve(id: String, cell: Vector2i) -> void:
	var number := -100 - Catalog.SITE_ORDER.find(id)
	world.board.block_building(cell, number)
	reserved[cell] = number

func clear_visuals() -> void:
	for cell in reserved:
		if world.board.structures.get(cell) == reserved[cell]: world.board.remove_building(cell)
	reserved.clear()
	for visual in visuals.values():
		visual.hide()
		visual.queue_free()
	visuals.clear()

func restore() -> void:
	clear_visuals()
	initialize()

func choose_cell(at: Vector2) -> Vector2i:
	var center: Vector2i = world.board.cell_at(Vector3(at.x, 0, at.y))
	var avoid: Dictionary = {}
	for p in world.hero.route: avoid[world.board.cell_at(p)] = true
	for d in world.dinosaurs:
		avoid[world.board.cell_at(d.position)] = true
		for p in d.route: avoid[world.board.cell_at(p)] = true
	for radius in range(0, 19):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius: continue
				var cell := center + Vector2i(x, y)
				if not world.board.can_build(cell) or avoid.has(cell): continue
				var p: Vector3 = world.board.point(cell)
				if p.distance_to(world.hero.position) < 14 or p.distance_to(world.extraction) < 9: continue
				var ring_open := true
				# An open surrounding ring prevents a new landmark from sealing a choke point.
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						if not world.board.is_open(cell + Vector2i(dx, dy)): ring_open = false
				if not ring_open or world.board.route(world.hero.position, p).is_empty(): continue
				return cell
	return Vector2i(-1, -1)

func add_visual(id: String) -> void:
	var site: Dictionary = data().sites[id]
	if not reserved.has(site.cell): reserve(id, site.cell)
	var n: Node3D = load("res://scenes/expedition/%s.tscn" % Catalog.SITES[id].scene).instantiate()
	n.position = world.board.point(site.cell)
	world.add_child(n)
	world.vision.shade(n)
	world.scenery.style_leaves(n)
	world.scenery.obstructions.register(n)
	var title := Label3D.new()
	title.name = "Title"
	title.text = "◇ " + Catalog.SITES[id].name
	title.font = world.hud.font
	title.font_size = 26
	title.pixel_size = 0.012
	title.position.y = 3.8
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.modulate = Color("e4c984")
	n.add_child(title)
	var marker: MeshInstance3D = world.ring(1.05, Color("d8bd76"))
	marker.reparent(n)
	marker.position = Vector3(0, 0.09, 0)
	marker.name = "Marker"
	visuals[id] = n
	n.visible = false

func refresh_visibility() -> void:
	if not Features.peripheral_enabled: return
	for id in data().get("sites", {}):
		var site: Dictionary = data().sites[id]
		var visible_now: bool = world.vision.is_visible(site.cell)
		if visible_now and site.status in ["hidden", "known"]:
			site.status = "discovered"
			note("发现 " + Catalog.SITES[id].name + "。右键调查，或按 %s 查看探索日志。" % world.preferences.key_name("journal"))
		if not visuals.has(id): continue
		var n: Node3D = visuals[id]
		n.visible = world.vision.explored.has(site.cell)
		n.get_node("Title").visible = visible_now
		n.get_node("Marker").visible = visible_now and site.status not in ["carried", "completed"]

func note(message: String) -> void:
	if not Features.peripheral_enabled: return
	data().history.append({"at": world.session.elapsed, "text": message})
	while data().history.size() > 32: data().history.pop_front()
	world.hud.toast(message)

func at_point(p: Vector3) -> String:
	if not Features.peripheral_enabled: return ""
	for id in data().get("sites", {}):
		var site: Dictionary = data().sites[id]
		if site.status == "hidden": continue
		if world.board.point(site.cell).distance_to(p) < 1.8: return id
	return ""

func go_to(id: String, inspect: bool = true) -> String:
	if not Features.peripheral_enabled: return "调查系统暂缓"
	if not data().sites.has(id) or data().sites[id].status == "hidden": return "尚未获得此处坐标"
	if world.session.phase not in ["playing", "evacuate"]: return "本局已结束"
	var target: Vector3 = world.board.point(data().sites[id].cell)
	var route: PackedVector3Array = world.board.route(world.hero.position, target, true)
	if route.is_empty() and world.hero.position.distance_to(target) > 3.0: return "前往此处的道路被阻挡，请清理或另选路线"
	world.stop_order()
	data().job = {"id": id, "inspect": inspect}
	data().tracked = id
	world.order = "expedition"
	world.order_target = target
	world.hero.route = route
	world.hero_route_revision = world.board.revision
	return ""

func choice_error(id: String, choice: int) -> String:
	if not Features.peripheral_enabled: return "调查系统暂缓"
	if world.session.phase != "playing": return "正在撤离，无法开始新的调查"
	if not data().sites.has(id) or choice < 0 or choice >= Catalog.SITES[id].choices.size(): return "调查选项无效"
	var site: Dictionary = data().sites[id]
	if site.status != "discovered": return "需要到现场发现设施，或此处已完成"
	if site.paid: return "" if choice == site.choice else "已投入材料，继续原来的方案即可"
	var spec: Dictionary = Catalog.SITES[id].choices[choice]
	if world.session.wood < spec.wood or world.session.gold < spec.gold: return "库存不足：需要 %d 木 / %d 金" % [spec.wood, spec.gold]
	return ""

func begin(id: String, choice: int) -> String:
	var error := choice_error(id, choice)
	if not error.is_empty(): return error
	var site: Dictionary = data().sites[id]
	# Validate the actual route before charging. Interrupted paid work can resume for free.
	error = go_to(id, false)
	if not error.is_empty(): return error
	if not site.paid:
		var spec: Dictionary = Catalog.SITES[id].choices[choice]
		world.session.wood -= spec.wood
		world.session.gold -= spec.gold
		site.choice = choice
		site.paid = true
	return ""

func cancel_job() -> void:
	if not Features.peripheral_enabled: return
	if not data().is_empty(): data().job = {}

func repair_blocked(id: String) -> bool:
	if Catalog.SITES[id].type != "repair": return false
	var target: Vector3 = world.board.point(data().sites[id].cell)
	for d in world.dinosaurs:
		if d.health > 0 and d.position.distance_to(target) < 8: return true
	return false

func update(dt: float) -> void:
	if not Features.peripheral_enabled: return
	if data().is_empty() or not world.started: return
	data().kit_cooldown = maxf(0, data().kit_cooldown - dt)
	refresh_clock -= dt
	noise_clock -= dt
	if refresh_clock <= 0:
		refresh_clock = 0.3
		refresh_visibility()
		deposit_samples()
		contracts.settle()
		update_events()
	if world.order != "expedition" or data().job.is_empty(): return
	var id: String = data().job.id
	var site: Dictionary = data().sites[id]
	var target: Vector3 = world.board.point(site.cell)
	if not world.hero.route.is_empty(): return
	if world.hero.position.distance_to(target) > 3:
		world.stop_order()
		note("调查路线已被阻挡，现场进度仍保留。")
		return
	if data().job.get("inspect", false):
		world.stop_order()
		refresh_visibility()
		world.hud.expedition_panel.open(id)
		return
	if world.session.phase != "playing":
		world.stop_order()
		note("救援已到达，调查已中断。请准备撤离。")
		return
	if repair_blocked(id): return
	site.progress = minf(Catalog.SITES[id].seconds, site.progress + dt)
	world.hero.work_pose("build" if Catalog.SITES[id].type == "repair" else "mine", target, fmod(site.progress, 0.9), dt)
	if noise_clock <= 0:
		world.dino_ai.emit_noise(world.hero.position, Catalog.SITES[id].choices[site.choice].get("noise", 8.0), "hero")
		world.sound.play_at("hammer" if Catalog.SITES[id].type == "repair" else "mine", target, -7)
		noise_clock = 1.0
	if site.progress >= Catalog.SITES[id].seconds: finish(id)

func finish(id: String) -> void:
	if not Features.peripheral_enabled: return
	var site: Dictionary = data().sites[id]
	if site.status != "discovered" or not site.paid: return
	world.stop_order()
	if Catalog.SITES[id].type == "sample":
		site.status = "carried"
		data().cargo.append(id)
		note("已取得" + Catalog.SITES[id].name + "的资料，请带回一座已完成的帐篷。")
	else:
		reward(id)
		if id == "relay":
			world.session.duration = minf(world.session.duration, maxf(world.session.elapsed + 180, world.session.duration - 90))
			for other in data().sites:
				if data().sites[other].status == "hidden": data().sites[other].status = "known"
	refresh_visibility()

func reward(id: String) -> void:
	if not Features.peripheral_enabled: return
	var site: Dictionary = data().sites[id]
	if site.status == "completed": return
	var choice: Dictionary = Catalog.SITES[id].choices[site.choice]
	world.session.wood += choice.reward_wood
	world.session.gold += choice.reward_gold
	data().kits += choice.kits
	site.status = "completed"
	if not data().records.has(id): data().records.append(id)
	note(Catalog.SITES[id].name + "已完成。" + Catalog.SITES[id].lore)
	world.sound.play_ui("complete")
	if not data().story_rewarded and data().records.has("cache") and data().records.has("weather") and data().records.has("archive"):
		data().story_rewarded = true
		data().kits += 1
		note("事故记录已整理完整。额外获得 1 个急救包；撤离后可在日志中回顾。")

func deposit_samples() -> void:
	if not Features.peripheral_enabled: return
	if data().cargo.is_empty() or world.hero.health <= 0: return
	for b in world.session.buildings:
		if b.hp <= 0 or b.remaining > 0 or b.kind != "tent": continue
		if world.hero.position.distance_to(world.board.point(b.cell)) > 3: continue
		for id in data().cargo.duplicate():
			reward(id)
			data().cargo.erase(id)
		return

func return_samples(require_cargo: bool = true) -> String:
	if not Features.peripheral_enabled: return "调查系统暂缓"
	if world.session.phase not in ["playing", "evacuate"] or world.hero.health <= 0: return "当前无法返营"
	if require_cargo and data().cargo.is_empty(): return "没有待返送的调查资料"
	var best := INF
	var target := Vector3.ZERO
	for b in world.session.buildings:
		if b.kind != "tent" or b.hp <= 0 or b.remaining > 0: continue
		var p: Vector3 = world.board.point(b.cell)
		var route: PackedVector3Array = world.board.route(world.hero.position, p, true)
		if route.is_empty() and world.hero.position.distance_to(p) > 3: continue
		if route.size() < best:
			best = route.size()
			target = p
	if best == INF: return "需要一座可到达、已完成的帐篷"
	world.stop_order()
	world.order = "move"
	world.order_target = target
	world.hero.route = world.board.route(world.hero.position, target, true)
	world.hero_route_revision = world.board.revision
	return ""

func use_kit() -> String:
	if not Features.peripheral_enabled: return "急救包系统暂缓"
	if world.paused or world.session.phase not in ["playing", "evacuate"] or world.hero.health <= 0: return "当前无法使用急救包"
	if data().get("kits", 0) <= 0: return "没有急救包：可探索急救站或留意无线电事件"
	if data().kit_cooldown > 0: return "急救包冷却剩余 %.0f 秒" % data().kit_cooldown
	if world.hero.health >= world.hero.max_health: return "生命已满，不消耗急救包"
	data().kits -= 1
	data().kit_cooldown = 20.0
	world.hero.health = minf(world.hero.max_health, world.hero.health + 50)
	world.sound.play_ui("complete")
	return ""

func update_events() -> void:
	if not Features.peripheral_enabled: return
	if world.session.phase != "playing": return
	if not data().offer.is_empty():
		if world.session.elapsed >= data().offer_until:
			data().events_done.append(data().offer)
			data().offer = ""
		else: return
	var plan: Array = Catalog.EVENTS if data().run.is_empty() else data().run.plan
	for event in plan:
		if world.session.elapsed < event.at or data().events_done.has(event.id): continue
		data().offer = event.id
		data().offer_until = world.session.elapsed + 90.0
		note("无线电消息：" + Catalog.event(event.id).title + "。按 %s 查看，可忽略，不会自动扣除资源。" % world.preferences.key_name("journal"))
		return

func event_error(choice: int) -> String:
	if not Features.peripheral_enabled: return "无线电事件暂缓"
	if world.session.phase != "playing" or data().offer.is_empty() or world.session.elapsed >= data().offer_until: return "消息已结束"
	var event := Catalog.event(data().offer)
	if choice < 0 or choice >= event.choices.size(): return "选项无效"
	var option: Dictionary = event.choices[choice]
	if world.session.wood < option.wood or world.session.gold < option.gold: return "库存不足：需要 %d 木 / %d 金" % [option.wood, option.gold]
	return ""

func choose_event(choice: int) -> String:
	var error := event_error(choice)
	if not error.is_empty(): return error
	var event := Catalog.event(data().offer)
	var option: Dictionary = event.choices[choice]
	world.session.wood -= option.wood
	world.session.gold -= option.gold
	match option.effect:
		"reveal_cache", "reveal_clinic", "reveal_nest":
			var id: String = option.effect.trim_prefix("reveal_")
			if data().sites.has(id) and data().sites[id].status == "hidden": data().sites[id].status = "known"
		"lumber": world.session.wood += 16
		"reinforcements": world.session.wood += 22
		"power": data().power_until = world.session.game_time() + 180.0
		"research": data().research_until = world.session.game_time() + 180.0
		"scan": data().scan_until = world.session.game_time() + 45.0
		"kit": data().kits += 1
		"rescue": world.session.duration = minf(world.session.duration, maxf(world.session.elapsed + 180, world.session.duration - 45))
	data().events_done.append(event.id)
	data().offer = ""
	note(event.title + "：" + option.name)
	return ""

func summary() -> String:
	if not Features.peripheral_enabled: return ""
	if data().is_empty(): return "%s 探索日志 · 发现岛上设施" % world.preferences.key_name("journal")
	if not data().job.is_empty() and world.order == "expedition":
		var id: String = data().job.id
		if not world.hero.route.is_empty(): return "前往：" + Catalog.SITES[id].name
		if repair_blocked(id): return "附近有恐龙，修复暂停 · 可撤退，进度保留"
		return "%s · %.0f / %.0f 秒" % [Catalog.SITES[id].name, data().sites[id].progress, Catalog.SITES[id].seconds]
	if not data().cargo.is_empty(): return "调查资料 × %d 待返送帐篷 · %s 日志" % [data().cargo.size(), world.preferences.key_name("journal")]
	if not data().offer.is_empty() and world.session.phase == "playing": return "无线电：%s · %s 查看" % [Catalog.event(data().offer).title, world.preferences.key_name("journal")]
	if not data().tracked.is_empty():
		var id: String = data().tracked
		return "追踪：%s · 距离 %.0f 米" % [Catalog.SITES[id].name, world.hero.position.distance_to(world.board.point(data().sites[id].cell))]
	return "调查 %d / 6 · 急救包 %d（%s）· %s 日志" % [data().records.size(), data().kits, world.preferences.key_name("kit"), world.preferences.key_name("journal")]

func route_brief(id: String) -> String:
	if not data().sites.has(id) or data().sites[id].status == "hidden": return ""
	var target: Vector3 = world.board.point(data().sites[id].cell)
	var path: PackedVector3Array = world.board.route(world.hero.position, target, true)
	if path.is_empty() and world.hero.position.distance_to(target) > 3: return "道路阻挡：当前无法到达，请清理通道。"
	var distance := path_length(world.hero.position, path)
	var home_distance := INF
	var from: Vector3 = path[-1] if not path.is_empty() else world.hero.position
	for b in world.session.buildings:
		if b.hp <= 0 or b.kind != "tent" or b.remaining > 0: continue
		var home: Vector3 = world.board.point(b.cell)
		var back: PackedVector3Array = world.board.route(from, home, true)
		if back.is_empty() and from.distance_to(home) > 3: continue
		home_distance = minf(home_distance, path_length(from, back))
	var text := "去程约 %.0f 米 / %.0f 秒" % [distance, distance / maxf(0.1, world.hero.speed)]
	text += " · 返营约 %.0f 秒" % (home_distance / maxf(0.1, world.hero.speed)) if is_finite(home_distance) else " · 尚无可达的返送帐篷"
	var visible_threats := 0
	for d in world.dinosaurs:
		if d.health > 0 and world.vision.is_visible(world.board.cell_at(d.position)) and d.position.distance_to(target) < 16: visible_threats += 1
	text += "\n现场附近已见恐龙 %d · 未知区域不保证安全；时间未计战斗与施工。" % visible_threats
	return text

func path_length(from: Vector3, path: PackedVector3Array) -> float:
	var length := 0.0
	for point in path:
		length += from.distance_to(point)
		from = point
	return length
