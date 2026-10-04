extends RefCounted
## Host-owned crafting and field trips; UI submits intents, never grants rewards.
const Catalog = preload("res://scripts/outfitting_catalog.gd")
const Visual = preload("res://scripts/pawn_visual.gd")
var world: Node
var visuals := {}
var reserved := {}
var recent_hits := {}
var last_hit := Vector3.ZERO
var refresh_clock := 0.0

func _init(owner_world: Node) -> void: world = owner_world

func data() -> Dictionary:
	if world.session.outfitting.is_empty(): world.session.outfitting = Catalog.empty()
	for inventory in world.session.outfitting.actors.values():
		if not inventory.has("chainsaw"): inventory.chainsaw = 0
		if not inventory.has("saw_enabled"): inventory.saw_enabled = true
	if not world.session.outfitting.has("robots"): world.session.outfitting.robots = []
	return world.session.outfitting

func actor(pawn: Node3D = null) -> Dictionary:
	if pawn == null: pawn = world.hero
	return data().actors[str(pawn.get_meta("coop_slot", 1))]

func initialize() -> void:
	if data().sites.is_empty():
		for id in Catalog.SITES:
			var cell: Vector2i = world.adventure.choose_cell(Catalog.SITES[id].at)
			# Old saves may place the survivor behind closed gates. Use the island's
			# original entry as a fallback; do not move them or open their defenses.
			if cell.x < 0:
				cell = world.adventure.choose_cell(Catalog.SITES[id].at, world.board.point(Vector2i(65,62)))
			if cell.x < 0:
				push_error("No reachable field site: " + id)
				continue
			data().sites[id] = {"cell":cell, "status":"known", "progress":0.0, "guarded":false}
			reserve(id, cell)
	sync_visuals()

func reserve(id: String, cell: Vector2i) -> void:
	var number := -200 - Catalog.SITES.keys().find(id)
	world.board.block_building(cell, number)
	reserved[cell] = number

func sync_visuals() -> void:
	# Clients receive this refresh too; alert expiry must not depend on host simulation.
	for id in recent_hits.keys():
		if world.session.game_time() >= recent_hits[id]: recent_hits.erase(id)
	for id in data().sites:
		var site: Dictionary = data().sites[id]
		if not visuals.has(id):
			reserve(id, site.cell)
			var node: Node3D = load("res://scenes/expedition/%s.tscn" % Catalog.SITES[id].scene).instantiate()
			node.position = world.board.point(site.cell)
			world.add_child(node)
			world.vision.shade(node)
			world.scenery.obstructions.register(node)
			var label := Label3D.new()
			label.name = "Title"
			label.font = world.hud.font
			label.font_size = 26
			label.pixel_size = 0.012
			label.position.y = 3.8
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = Color("e7c68a")
			node.add_child(label)
			visuals[id] = node
		visuals[id].visible = world.vision.explored.has(site.cell)
		visuals[id].get_node("Title").visible = world.vision.is_visible(site.cell)
		visuals[id].get_node("Title").text = Catalog.SITES[id].name + (" · 已回收" if site.status != "known" else " · 左键搜寻")

func at_point(point: Vector3) -> String:
	for id in data().sites:
		var site: Dictionary = data().sites[id]
		if world.vision.is_visible(site.cell) and world.board.point(site.cell).distance_to(point) < 1.8: return id
	return ""

func workshop_error(id: int) -> String:
	var b: Dictionary = world.session.building(id)
	if b.is_empty() or b.kind != "workshop": return "需要装备工坊：选中基础建筑，升级为工坊"
	if b.remaining > 0: return "工坊仍在施工"
	return ""

func craft_error(id: int, item: String) -> String:
	if item not in Catalog.ITEMS: return "未知物品"
	if world.session.phase != "playing": return "撤离阶段不能开始制作"
	var error := workshop_error(id)
	if not error.is_empty(): return error
	if world.session.supply() < world.session.demand(): return "工坊断电，请恢复供电"
	if data().jobs.has(str(id)): return "工坊有制作任务或待领物品"
	var spec: Dictionary = Catalog.ITEMS[item]
	var inventory := actor()
	if item == "repair_bot":
		if not world.session.technologies.has("mechanical"): return "需要实验室研究「机械工程」"
		var pending: int = data().jobs.values().filter(func(job): return job.item == "repair_bot").size()
		if data().robots.size() + pending >= 3: return "营地最多部署 3 台维修机器人（含制作中）"
	if spec.rank > 0 and inventory[spec.slot] >= spec.rank: return "已装备同级或更好的物品"
	if spec.slot == "kits" and inventory.kits >= 3: return "急救包已达携带上限"
	for job in data().jobs.values():
		if item != "repair_bot" and job.owner == owner_slot() and Catalog.ITEMS[job.item].slot == spec.slot: return "已有同类物品正在制作或等待领取"
	if not spec.blueprint.is_empty():
		if spec.blueprint not in data().blueprints: return "需要从%s带回图纸" % Catalog.SITES[spec.blueprint].name
		if not world.session.technologies.has("field_equipment"): return "需要实验室研究「野外装备工程」"
		if inventory[spec.slot] < 1: return "需要先装备基础款，再进行高级改良"
	if world.session.wood < spec.wood or world.session.gold < spec.gold: return "材料不足：需要 %d 木 / %d 金" % [spec.wood, spec.gold]
	return ""

func owner_slot() -> String: return str(world.hero.get_meta("coop_slot", 1))

func craft(id: int, item: String) -> String:
	var error := craft_error(id, item)
	if not error.is_empty(): return error
	var spec: Dictionary = Catalog.ITEMS[item]
	world.session.wood -= spec.wood
	world.session.gold -= spec.gold
	data().jobs[str(id)] = {"item":item, "owner":owner_slot(), "remaining":spec.time}
	return "已开始制作%s；完成后到工坊领取。" % spec.name

func travel(point: Vector3, task: String, id: int = -1, site: String = "") -> String:
	var route: PackedVector3Array = world.worker.work_route("field", point)
	if route.is_empty() and world.hero.position.distance_to(point) > 3: return "道路不通，请清理通道后再试"
	world.stop_order()
	actor().task = task
	actor().target = id
	actor().site = site
	world.order = "field"
	world.order_target = point
	world.hero.route = route
	world.hero_route_revision = world.board.revision
	world.build_mode = ""
	return ""

func collect(id: int) -> String:
	var error := workshop_error(id)
	if not error.is_empty(): return error
	var job: Dictionary = data().jobs.get(str(id), {})
	if job.is_empty() or job.remaining > 0: return "尚无制作完成的物品"
	if job.item == "repair_bot": return "机器人完成后自动部署，无需领取"
	if job.owner != owner_slot(): return "这是队友订制的装备"
	if job.item == "medkit" and actor().kits >= 3: return "急救包已满，物品会留在工坊"
	return travel(world.board.point(world.session.building(id).cell), "collect", id)

func explore(id: String) -> String:
	if world.session.phase != "playing": return "救援已到，请准备撤离"
	if not data().sites.has(id): return "尚无此处坐标"
	if data().sites[id].status != "known": return "已取得此处物资，请返营结算"
	return travel(world.board.point(data().sites[id].cell), "explore", -1, id)

func return_home() -> String:
	var best := INF
	var target := Vector3.ZERO
	for b in world.session.buildings:
		if b.hp <= 0 or b.kind != "tent" or b.remaining > 0: continue
		var point: Vector3 = world.board.point(b.cell)
		var route: PackedVector3Array = world.worker.work_route("field", point)
		if route.is_empty() and world.hero.position.distance_to(point) > 3: continue
		var length: float = world.adventure.path_length(world.hero.position, route)
		if length < best:
			best = length
			target = point
	if best == INF: return "需要可到达、已建成的帐篷"
	return travel(target, "return")

func cancel() -> void:
	actor().task = ""
	actor().target = -1
	actor().site = ""

func use_kit() -> String:
	var inventory := actor()
	if world.hero.health <= 0: return "倒下后不能使用急救包"
	if inventory.kits <= 0: return "没有急救包：可在工坊制作或外出搜寻"
	if inventory.cooldown > 0: return "急救包冷却剩余 %.0f 秒" % ceilf(inventory.cooldown)
	if world.hero.health >= world.hero.max_health: return "生命已满，不消耗急救包"
	inventory.kits -= 1
	inventory.cooldown = 20.0
	world.hero.health = minf(world.hero.max_health, world.hero.health + 50)
	world.sound.play_ui("complete")
	return "已使用急救包，恢复 50 生命。"

func damage_multiplier(pawn: Node3D) -> float: return [1.0, 1.25, 1.5][actor(pawn).rifle]
func incoming_damage(pawn: Node3D, amount: float, direct: bool = true) -> float:
	return amount * ([1.0, 0.85, 0.75][actor(pawn).vest] if direct else 1.0)

func saw_active() -> bool:
	return actor().chainsaw > 0 and actor().saw_enabled

func toggle_saw() -> String:
	if actor().chainsaw <= 0: return "请先在工坊制作并领取电锯"
	actor().saw_enabled = not actor().saw_enabled
	return "已切换：电锯开路（不采木、不返营）" if actor().saw_enabled else "已切换：普通采木（自动返送）"

func apply_equipment(pawn: Node3D) -> void:
	var inventory := actor(pawn)
	pawn.speed = world.session.survivor_speed() * [1.0, 1.10, 1.15][inventory.boots]
	pawn.visual.set_outfit(inventory)

func tick_actor(dt: float) -> void:
	var inventory := actor()
	inventory.cooldown = maxf(0, inventory.cooldown - dt)
	apply_equipment(world.hero)
	if world.hero.health <= 0: return
	for b in world.session.buildings:
		if b.hp <= 0 or b.remaining > 0 or b.kind != "tent" or world.hero.position.distance_to(world.board.point(b.cell)) > 3: continue
		for id in inventory.cargo.duplicate():
			var spec: Dictionary = Catalog.SITES[id]
			world.session.wood += spec.wood
			world.session.gold += spec.gold
			data().reserve_kits += spec.kits
			if id != "supplies" and id not in data().blueprints: data().blueprints.append(id)
			data().sites[id].status = "completed"
			inventory.cargo.erase(id)
			world.hud.toast("已返营结算：" + spec.name + "；物资入库，图纸可在工坊查看。")
		var refill: int = mini(3 - inventory.kits, data().reserve_kits)
		inventory.kits += refill
		data().reserve_kits -= refill
		break
	if world.order != "field" or inventory.task.is_empty(): return
	if not world.hero.route.is_empty(): return
	if world.hero.position.distance_to(world.order_target) > 3:
		world.stop_order()
		world.hud.toast("路线受阻，已停止；探索进度与携带物资保留。")
		return
	if inventory.task == "return":
		world.stop_order()
	elif inventory.task == "collect":
		var key := str(inventory.target)
		var job: Dictionary = data().jobs.get(key, {})
		if not job.is_empty() and workshop_error(inventory.target).is_empty() and job.owner == owner_slot() and job.remaining <= 0:
			var spec: Dictionary = Catalog.ITEMS[job.item]
			if spec.slot != "kits" or inventory.kits < 3:
				if spec.slot == "kits": inventory.kits += 1
				else: inventory[spec.slot] = maxi(inventory[spec.slot], spec.rank)
				data().jobs.erase(key)
				apply_equipment(world.hero)
				world.hud.toast("已领取并装备：" + spec.name)
		world.stop_order()
	elif inventory.task == "explore":
		var id: String = inventory.site
		var site: Dictionary = data().sites[id]
		if site.status != "known" or world.session.phase != "playing":
			world.stop_order()
			return
		if threatened(world.order_target): return
		site.progress = minf(Catalog.SITES[id].seconds, site.progress + dt)
		world.hero.work_pose("build", world.order_target, fmod(site.progress, 0.9), dt)
		if site.progress >= Catalog.SITES[id].seconds:
			site.status = "carried"
			inventory.cargo.append(id)
			world.stop_order()
			world.hud.toast("已收好物资与资料；通过「装备 / 探索」返回帐篷结算。")

func threatened(point: Vector3) -> bool:
	return world.dinosaurs.any(func(d): return d.health > 0 and d.position.distance_to(point) < 10)

func update(dt: float) -> void:
	for key in data().jobs.keys():
		var job: Dictionary = data().jobs[key]
		var b: Dictionary = world.session.building(int(key))
		if b.is_empty():
			# Materials and finished goods are lost with the workshop; worn gear survives.
			data().jobs.erase(key)
			continue
		if job.remaining <= 0 and job.item == "repair_bot":
			world.robots.deploy(b)
			data().jobs.erase(key)
			continue
		if job.remaining <= 0 or b.remaining > 0 or world.session.supply() < world.session.demand(): continue
		job.remaining = maxf(0, job.remaining - dt)
		if job.remaining <= 0:
			if job.item == "repair_bot":
				world.robots.deploy(b)
				data().jobs.erase(key)
				world.hud.toast("维修机器人已部署，自动巡检附近建筑。")
			else: world.hud.toast("工坊制作完成：%s。前往领取后生效。" % Catalog.ITEMS[job.item].name)
	refresh_clock -= dt
	if refresh_clock > 0: return
	refresh_clock = 0.3
	sync_visuals()
	for id in data().sites:
		var site: Dictionary = data().sites[id]
		# A cleared spawn schedule is the deterministic no-encounter mode used
		# by route/save simulations.  Do not reintroduce site guards behind the
		# director's back while those tests (or a future sandbox mode) are active.
		if world.spawn_clocks.is_empty(): continue
		if site.guarded or site.status != "known": continue
		var point: Vector3 = world.board.point(site.cell)
		if not world.survivors().any(func(p): return p.health > 0 and p.position.distance_to(point) < 24): continue
		site.guarded = true
		var used := []
		for species in Catalog.SITES[id].guards:
			for offset in [Vector2i(3,0), Vector2i(-3,0), Vector2i(0,3), Vector2i(0,-3), Vector2i(4,3)]:
				var cell: Vector2i = site.cell + offset
				if cell in used or not world.board.is_open(cell): continue
				var spawn: Vector3 = world.board.point(cell)
				if not world.board.body_open(spawn, world.Dinosaurs.spec(species).radius): continue
				var dinosaur: Node3D = world.spawn_dinosaur(spawn, species, true)
				if dinosaur:
					used.append(cell)
					break

func building_hit(b: Dictionary) -> void:
	recent_hits[b.id] = world.session.game_time() + 8.0
	last_hit = world.board.point(b.cell)

func view_camp() -> void:
	world.camera_rig.following = false
	if not recent_hits.is_empty(): world.camera_focus = last_hit; return
	for b in world.session.buildings:
		if b.hp > 0 and b.kind == "tent": world.camera_focus = world.board.point(b.cell); return

func brief() -> String:
	var inventory := actor()
	if not inventory.cargo.is_empty(): return "携带探索物资 ×%d · 需返营结算" % inventory.cargo.size()
	if inventory.task == "collect": return "前往工坊领取装备"
	if inventory.task == "return": return "携带物资返回帐篷"
	if inventory.task == "explore" and data().sites.has(inventory.site):
		var site: Dictionary = data().sites[inventory.site]
		return "%s · %s" % [Catalog.SITES[inventory.site].name, "附近有恐龙，搜寻暂停" if threatened(world.board.point(site.cell)) else "搜寻 %.0f / %.0f 秒" % [site.progress, Catalog.SITES[inventory.site].seconds]]
	return "准备装备，外出搜寻；带回物资后结算"
