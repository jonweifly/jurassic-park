extends RefCounted
## Presentation observes completed work and rescue state without changing simulation clocks.
var world: Node
var phase := ""
var shown := {}
var pending: Array[Dictionary] = []
var cooldown := 0.0
var boarding := 0.0
var camp_ready := false
var power_ready := false

func _init(owner_world: Node) -> void:
	world = owner_world

func completed(kind: String) -> bool:
	for building in world.session.buildings:
		if building.kind == kind and building.remaining <= 0.0 and building.hp > 0.0: return true
	return false

func reset(resumed: bool = false) -> void:
	phase = world.session.phase
	shown.clear()
	pending.clear()
	cooldown = 0.0
	boarding = world.session.boarding_progress
	camp_ready = completed("tent")
	power_ready = completed("generator")
	world.hud.clear_subtitle()
	if resumed:
		# Old radio milestones are skipped on load/join instead of replayed in a burst.
		shown["opening"] = true
		shown["approach"] = world.session.duration - world.session.elapsed <= 120.0
		shown["acknowledge"] = shown["approach"]
		shown["arrival"] = phase != "playing"
		shown["boarding"] = boarding > 0.0
		shown["last_minute"] = world.session.evacuation_elapsed >= world.Catalog.EVACUATION_SECONDS - 60.0
		cooldown = 6.0
	else:
		queue_line("opening", "幸存者 · 先找地方落脚，再想办法联系救援。", 4.5)

func queue_line(id: String, text: String, duration: float = 4.5) -> void:
	if shown.get(id, false): return
	shown[id] = true
	pending.append({"id": id, "text": text, "duration": duration})

func thought(id: String, text: String) -> void:
	if cooldown > 0.0 or not pending.is_empty() or world.hud.subtitle_time > 0.0 or shown.get(id, false): return
	if world.hud.show_subtitle("幸存者 · " + text, 4.5):
		shown[id] = true
		cooldown = 28.0

func update(dt: float) -> void:
	if not world.started or world.presentation_paused(): return
	if phase.is_empty(): reset(world.session.game_time() > 0.1)
	cooldown = maxf(0.0, cooldown - dt)
	var session = world.session
	if phase != session.phase:
		phase = session.phase
		pending.clear()
		cooldown = 0.0
		if phase == "evacuate":
			queue_line("arrival", "无线电 · 救援机组：这里是回收一号，撤离点已就绪。前往 H 停机坪。", 5.5)
		elif phase in ["won", "lost"]:
			world.hud.clear_subtitle()
			queue_line("ending", "无线电 · 机组：人员已接回。保持低头，我们带你离开这座岛。" if phase == "won" else "无线电 · 机组：呼叫幸存者……能听到吗？", 5.5)
	if phase == "playing":
		if session.duration - session.elapsed <= 120.0:
			queue_line("approach", "无线电 · 机组：收到你的信标，正在接近。请准备撤离。", 5.0)
			queue_line("acknowledge", "幸存者 · 收到。我会守住撤离点，等你们过来。")
		var tent := completed("tent")
		var power := completed("generator")
		if tent and not camp_ready:
			queue_line("camp", "幸存者 · 总算有个落脚处了。把物资送回这里，再把防线撑起来。")
		if power and not power_ready:
			queue_line("power", "幸存者 · 灯亮了。只要电力不断，今晚就还有希望。")
		camp_ready = tent
		power_ready = power
		if world.hero.health < world.hero.max_health * 0.3:
			thought("wounded", "呼吸放慢……先活着回到营地。")
		elif world.order == "return" and world.worker.cargo > 0:
			thought("return", "把这趟物资带回去，脚下要稳。")
		elif world.order == "waiting_dropoff" and world.worker.cargo > 0:
			thought("dropoff", "物资有了，还得找个能放下它们的营地。")
		elif world.hero.animation_state == "chop":
			thought("wood", "这批木材，能把营地再撑牢一点。")
		elif world.hero.animation_state == "mine":
			thought("gold", "岩层里的金属……能换来电力和更好的装备。")
		elif world.hero.animation_state == "build":
			thought("repair" if world.order == "repair" else "build", "手要稳，不能让这道防线倒下。" if world.order == "repair" else "一根梁，一颗钉。先让它立住。")
		elif world.hero.swing > 0.0:
			thought("attack", "稳住，等它露出破绽。")
	elif phase == "evacuate":
		if session.boarding_progress > 0.0 and boarding <= 0.0:
			queue_line("boarding", "无线电 · 机组：看到你了。保持在停机坪范围，我们接你上来。", 5.0)
		elif boarding > 0.0 and session.boarding_progress < boarding:
			queue_line("left_pad", "幸存者 · 不能离开太久，得回到登机点。")
		if session.evacuation_elapsed >= world.Catalog.EVACUATION_SECONDS - 60.0 and session.boarding_progress <= 0.0:
			queue_line("last_minute", "无线电 · 机组：留给我们的时间不多了。尽快回到撤离点。", 5.0)
	boarding = session.boarding_progress
	if cooldown <= 0.0 and world.hud.subtitle_time <= 0.0 and not pending.is_empty():
		var line: Dictionary = pending.pop_front()
		world.hud.show_subtitle(line.text, line.duration)
		cooldown = line.duration + (1.5 if phase == "evacuate" else 6.0)
