extends RefCounted
## One survivor owns one work order. Stock changes only at a surviving drop-off.
var world: Node
var cargo_kind := ""
var cargo := 0
var resource_kind := ""
var resource_target := Vector3.ZERO
var target_id := -1
var clock := 0.0
var retry_clock := 0.0
var delivered := 0
var noise_clock := 0.0
var recovery := 0.0
var pose_clock := 0.0
var broke_notified := false

const WORK_DISTANCES := {"wood": 1.43, "gold": 1.7, "build": 3.0, "repair": 3.0, "return": 3.0, "heal": 3.0}

func _init(owner_world: Node) -> void:
	world = owner_world

func capacity() -> int:
	# A04M Har2 / Har3: levels 1–4 carry 1 / 2 / 3 / 4.
	return mini(4, maxi(1, world.session.harvest_level + 1 + world.session.carry_capacity_bonus()))

func work_distance(kind: String) -> float:
	return float(WORK_DISTANCES.get(kind, 2.0))

func assign(kind: String, target: Vector3, building_id: int = -1) -> void:
	if world.adventure: world.adventure.cancel_job()
	if world.outfitting: world.outfitting.cancel()
	world.leave_shelter(world.hero)
	clock = 0
	recovery = 0
	pose_clock = 0
	target_id = building_id
	resource_kind = kind if kind in ["wood", "gold"] else ""
	resource_target = target
	if cargo > 0 and kind in ["wood", "gold"] and not (kind == "wood" and world.outfitting.saw_active()):
		begin_return()
	else: travel(kind, target)

# Movement follows terrain in XZ. Use the same contact rule for planning and work,
# with an inset arrival point so rounding can never cause an endless replan.
func wood_contact(from: Vector3, target: Vector3) -> bool:
	return Vector2(from.x - target.x, from.z - target.z).length() <= work_distance("wood") and absf(from.y - target.y) <= 0.55 and world.board.body_open(from, world.hero.body_radius)

func wood_route(target: Vector3) -> PackedVector3Array:
	var origin: Vector3 = world.hero.position
	if wood_contact(origin, target): return PackedVector3Array()
	var best := PackedVector3Array()
	var shortest := INF
	var cell: Vector2i = world.board.cell_at(target)
	# Prefer the side facing the camera so the survivor remains readable while
	# working. Fall back to the shortest reachable side when terrain blocks it.
	var camera_direction := Vector2(world.camera.position.x - target.x, world.camera.position.z - target.z)
	if camera_direction.length_squared() < 0.001: camera_direction = Vector2(1, 1)
	camera_direction = camera_direction.normalized()
	var sides := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	sides.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_score := Vector2(a.x, a.y).dot(camera_direction)
		var b_score := Vector2(b.x, b.y).dot(camera_direction)
		return a_score > b_score
	)
	# A blocked tree cell is square: diagonal approaches cannot reach the trunk
	# without clipping its collision. Choose an accessible cardinal working side.
	for side in sides:
		if not world.board.is_open(cell + side): continue
		var center: Vector3 = world.board.point(cell + side)
		var approach := target + Vector3(side.x, 0, side.y) * 1.36
		if world.board.layout: approach.y = world.board.layout.height_at(approach.x, approach.z)
		if not wood_contact(approach, target): continue
		var route := PackedVector3Array()
		if world.hero.segment_open(origin, approach):
			route.append(approach)
		else:
			route = world.board.route(origin, center, false, world.hero.body_radius)
			var end: Vector3 = route[-1] if not route.is_empty() else origin
			if end.distance_to(center) > 0.05 or not world.hero.segment_open(end, approach): continue
			route.append(approach)
		var previous := origin
		var valid := true
		for point in route:
			if not world.hero.segment_open(previous, point):
				valid = false
				break
			previous = point
		if not valid: continue
		var length := route_length(route)
		var camera_bias := Vector2(side.x, side.y).dot(camera_direction)
		var score := length - camera_bias * 2.0
		if score < shortest:
			shortest = score
			best = route
	return best

func work_route(kind: String, target: Vector3) -> PackedVector3Array:
	if kind == "wood": return wood_route(target)
	var route: PackedVector3Array = world.board.route(world.hero.position, target, kind != "move")
	# A grid route starts at the next cell's centre. From an off-centre position,
	# that first diagonal can clip a building corner: first straighten inside this cell.
	if not route.is_empty() and not world.hero.segment_open(world.hero.position, route[0]):
		var center: Vector3 = world.board.point(world.board.cell_at(world.hero.position))
		if world.hero.segment_open(world.hero.position,center) and world.hero.segment_open(center,route[0]):
			route.insert(0,center)
	if kind not in ["wood", "gold", "build", "repair"]: return route
	var end: Vector3 = route[-1] if not route.is_empty() else world.hero.position
	var direction := target - end
	direction.y = 0
	var distance := work_distance(kind)
	if direction.length() > distance:
		var approach := end + direction.normalized() * (direction.length() - distance)
		if world.board.body_segment_open(end, approach, world.hero.body_radius):
			if world.board.layout: approach.y = world.board.layout.height_at(approach.x, approach.z)
			route.append(approach)
	return route

func route_length(route: PackedVector3Array) -> float:
	var length := 0.0
	var previous: Vector3 = world.hero.position
	for point in route:
		length += previous.distance_to(point)
		previous = point
	return length

func travel(kind: String, target: Vector3) -> bool:
	world.order = kind
	world.order_target = target
	world.hero.route = work_route(kind, target)
	world.hero_route_revision = world.board.revision
	var at_work: bool = wood_contact(world.hero.position, target) if kind == "wood" else world.hero.position.distance_to(target) <= 3.0
	if world.hero.route.is_empty() and not at_work:
		world.order = "idle"
		world.hud.toast("工作位置无法到达，请清理道路后重新下令。")
		return false
	return true

func begin_return() -> void:
	world.leave_shelter(world.hero)
	var best := INF
	var dropoff: Dictionary = {}
	for b in world.session.buildings:
		if b.kind != "tent" or b.hp <= 0 or b.remaining > 0: continue
		var p: Vector3 = world.board.point(b.cell)
		var route: PackedVector3Array = work_route("return", p)
		if route.is_empty() and world.hero.position.distance_to(p) > work_distance("return"): continue
		var length := route_length(route)
		if length < best:
			best = length
			dropoff = b
	if dropoff.is_empty():
		var announce: bool = world.order != "waiting_dropoff"
		world.order = "waiting_dropoff"
		world.hero.route.clear()
		retry_clock = 1.0
		if announce: world.hud.toast("携带资源等待返送：需要一座可到达、已完成的帐篷。")
		return
	target_id = dropoff.id
	travel("return", world.board.point(dropoff.cell))

func resume_harvest() -> void:
	if resource_kind == "wood" and not world.trees.has(world.board.cell_at(resource_target)):
		var cells: Array = world.trees.keys()
		cells.sort_custom(func(a, b): return world.board.point(a).distance_squared_to(resource_target) < world.board.point(b).distance_squared_to(resource_target))
		var found := false
		for cell in cells:
			var p: Vector3 = world.board.point(cell)
			if p.distance_to(resource_target) > 16: break
			var route := wood_route(p)
			if not route.is_empty() or wood_contact(world.hero.position, p):
				resource_target = p
				found = true
				break
		if not found:
			world.order = "idle"
			world.hud.toast("附近可到达的树木已采完。")
			return
	if resource_kind == "gold":
		var field: Dictionary = world.building_at(world.board.cell_at(resource_target))
		if field.is_empty() or field.kind != "fossil" or field.remaining > 0:
			world.order = "idle"
			return
	if resource_kind.is_empty(): world.order = "idle"
	else: travel(resource_kind, resource_target)

func update(dt: float) -> void:
	world.hero.carrying = cargo > 0
	world.hero.cargo_kind = cargo_kind
	noise_clock -= dt
	# Validate orders while travelling, before playing another stroke at a lost target.
	if world.order in ["build", "repair", "heal"] and world.session.building(target_id).is_empty():
		world.stop_order()
		world.hud.toast("工作目标已不存在，已停止前往。")
		return
	if world.order == "gold" and world.building_at(world.board.cell_at(resource_target)).is_empty():
		if cargo > 0: begin_return()
		else:
			world.stop_order()
			world.hud.toast("挖掘场已不可用，已停止采集。")
		return
	if world.order == "wood" and recovery <= 0 and not world.trees.has(world.board.cell_at(resource_target)):
		if cargo > 0: begin_return()
		else: resume_harvest()
		return
	if recovery > 0:
		# Keep the tool visible through impact before turning to carry the load.
		if world.order not in ["wood", "gold"]:
			recovery = 0
		else:
			recovery = maxf(0, recovery - dt)
			world.hero.work_pose("chop" if cargo_kind == "wood" else "mine", world.order_target, 1.35 - recovery, dt)
			if recovery == 0: begin_return()
			return
	if world.order == "waiting_dropoff":
		retry_clock -= dt
		if retry_clock <= 0: begin_return()
		return
	if world.order == "return":
		var tent: Dictionary = world.session.building(target_id)
		if tent.is_empty() or tent.remaining > 0 or (world.hero.route.is_empty() and world.hero.position.distance_to(world.order_target) > work_distance("return")):
			begin_return()
			return
	if world.order not in ["wood", "gold", "build", "repair", "return", "heal"]: return
	if not world.hero.route.is_empty(): return
	var at_work: bool = wood_contact(world.hero.position, world.order_target) if world.order == "wood" else world.hero.position.distance_to(world.order_target) <= 3.0
	if not at_work:
		clock = 0
		travel(world.order, world.order_target)
		return
	if world.order == "heal":
		var tent: Dictionary = world.session.building(target_id)
		if tent.is_empty() or tent.kind != "tent" or tent.remaining > 0:
			world.stop_order()
			world.hud.toast("治疗中止：帐篷已不可用。")
			return
		world.enter_shelter(world.hero, tent)
		if world.hero.health >= world.hero.max_health:
			world.stop_order()
			world.hud.toast("治疗完成。")
			return
		clock += dt
		if clock >= 1.0:
			clock -= 1.0
			# Running out of gold pauses regeneration but keeps the shelter; being
			# inside is the reward for staying put, not something to lose to a price.
			if world.session.gold < 1:
				if not broke_notified:
					broke_notified = true
					world.hud.toast("黄金不足，暂停治疗。留在帐篷里仍然安全。")
				return
			broke_notified = false
			world.session.gold -= 1
			world.session.healing_spent += 1
			world.hero.health = minf(world.hero.max_health, world.hero.health + world.session.healing_amount())
		return
	if world.order == "return":
		if cargo_kind == "wood": world.session.wood += cargo
		else: world.session.gold += cargo
		delivered += cargo
		world.sound.play_at("deposit", world.hero.position)
		cargo = 0
		cargo_kind = ""
		resume_harvest()
		return
	if world.order in ["build", "repair"]:
		var b: Dictionary = world.session.building(target_id)
		if b.is_empty():
			world.order = "idle"
			return
		var previous := pose_clock
		pose_clock += dt
		world.hero.work_pose("build", world.order_target, fmod(pose_clock, 0.9), dt)
		if floori((previous - 0.65) / 0.9) < floori((pose_clock - 0.65) / 0.9):
			world.sound.play_at("hammer", world.hero.visual.work_tip(), -3)
			world.work_impact(world.order_target, Color("bfa47a"))
		if noise_clock <= 0:
			world.dino_ai.emit_noise(world.hero.position, 5.0, "hero", world.survivor_id(world.hero))
			noise_clock = 1.0
		if world.order == "build":
			if world.session.work(target_id, dt * world.session.work_multiplier()):
				world.order = "idle"
				world.sound.play_at("complete", world.hero.position)
				world.hud.toast(world.Catalog.BUILDINGS[b.kind].name + "已建成。")
		else:
			clock += dt
			if clock < 1: return
			clock = 0
			var max_hp: float = world.Catalog.max_health(b)
			if b.hp >= max_hp or world.session.wood < 1:
				world.order = "idle"
				world.hud.toast("修理完成。" if b.hp >= max_hp else "木材不足，修理已停止。")
				return
			# Temporary repair rate/cost until inherited repair ability is resolved.
			world.session.wood -= 1
			b.hp = minf(max_hp, b.hp + max_hp * 0.08)
			if b.hp >= max_hp:
				world.order = "idle"
				world.hud.toast("修理完成。")
		return
	if world.order == "wood" and world.outfitting.saw_active():
		clock += dt
		world.hero.work_pose("chop", world.order_target, minf(clock,1.1), dt)
		if clock >= 1.1:
			world.clear_tree(world.board.cell_at(world.order_target))
			world.dino_ai.emit_noise(world.hero.position, 14.0, "hero", world.survivor_id(world.hero))
			world.sound.play_at("chop", world.hero.visual.work_tip())
			world.work_impact(world.order_target, Color("ad8756"))
			world.stop_order()
			world.hud.toast("道路已清开。左键下一棵树继续开路。")
		return
	clock += dt * world.session.work_multiplier()
	world.hero.work_pose("chop" if world.order == "wood" else "mine", world.order_target, minf(clock, 1.1), dt)
	if clock < 1.1: return # L1 gather timing still provisional.
	clock = 0
	var amount := capacity() - cargo
	if world.order == "wood":
		var c: Vector2i = world.board.cell_at(world.order_target)
		if not world.trees.has(c):
			resume_harvest()
			return
		amount = mini(amount, world.trees[c].wood)
		world.trees[c].wood -= amount
		if world.trees[c].wood <= 0:
			# Some broadleaf stands double as a restrained early food source.
			# Cell parity keeps the result deterministic across saves and replays.
			if posmod(c.x * 3 + c.y * 5, 4) == 0:
				world.session.add_berries(1)
				world.hud.toast("砍伐时找到一份可食用野果。")
			world.clear_tree(c)
	else:
		var field: Dictionary = world.building_at(world.board.cell_at(world.order_target))
		if field.is_empty() or field.kind != "fossil" or field.remaining > 0:
			world.order = "idle"
			return
		if not field.has("reserves"): field.reserves = 10000 # Provisional deposit reserve.
		amount = mini(amount, field.reserves)
		field.reserves -= amount
		if amount <= 0:
			world.order = "idle"
			world.hud.toast("化石挖掘场已枯竭。")
			return
	cargo_kind = world.order
	world.dino_ai.emit_noise(world.hero.position, 6.0 if cargo_kind == "wood" else 7.0, "hero", world.survivor_id(world.hero))
	world.sound.play_at("chop" if cargo_kind == "wood" else "mine", world.hero.visual.work_tip())
	world.work_impact(world.order_target, Color("ad8756") if cargo_kind == "wood" else Color("bdb69c"))
	cargo += amount
	recovery = 0.25
