extends RefCounted
## Authored standard-mode pacing; local dinosaur perception remains authoritative.
const Hard = preload("res://scripts/hard_difficulty.gd")
var world: Node

func _init(owner_world: Node) -> void:
	world = owner_world

func configure() -> void:
	world.spawn_clocks.assign([{ "period": 95.0, "next": 100.0, "species": ["small_raptor"] }])

func configure_hard() -> void:
	world.spawn_clocks.assign([{"period": 100.0, "next": 100.0, "species": ["small_raptor"], "pressure": 0.0, "health_multiplier": 1.0, "wave": 0}])

func update_hard() -> void:
	var s = world.session
	var now: float = s.game_time()
	for clock in world.spawn_clocks:
		if not clock.get("warned", false) and clock.next - now <= 12.0:
			clock.warned = true
			world.hud.toast("恐龙群正在接近。检查供电、修复防线，关闭电门。")
			world.sound.play_ui("warning")
		if now < clock.next: continue
		# Recalculate only at wave boundaries. Building one tower cannot instantly
		# pull a wave forward, and loading never causes a burst of missed waves.
		clock.pressure = move_toward(float(clock.get("pressure", 0.0)), Hard.target_pressure(s), Hard.MAX_PRESSURE_STEP)
		clock.period = Hard.profile(clock.pressure).interval
		clock.next = now + clock.period
		clock.warned = false
		var species := Hard.group(now, clock.pressure, int(clock.get("wave", 0)))
		# Only one living boss; support waves continue while it is being fought.
		if world.dinosaurs.any(func(d): return d.health > 0 and d.get_meta("species") == "alpha_trex"):
			for i in range(species.size()):
				if species[i] == "alpha_trex": species[i] = "elite_raptor"
		clock.health_multiplier = move_toward(float(clock.get("health_multiplier", Hard.profile(clock.pressure).health)), Hard.health_target(s, species, clock.pressure), 0.22)
		clock.wave = int(clock.get("wave", 0)) + 1
		spawn_group(species, s.phase == "evacuate", clock.pressure, clock.health_multiplier)
		if species.has("alpha_trex"):
			world.hud.toast("棘背暴君现身！分散防线，躲开重击预警；电栅栏可绕过厚甲。")
			world.sound.play_ui("warning")
			continue
		world.hud.toast("恐龙群来袭！" + ("守住撤离路线。" if s.phase == "evacuate" else "守住防线，优先击退大型恐龙。"))

func group() -> Array:
	var time: float = world.session.elapsed
	if time < 360: return ["small_raptor", "raptor"]
	if time < 720: return ["young_trex", "raptor", "small_raptor"]
	return ["trex", "raptor", "young_trex"]

func living_count() -> int:
	var count := 0
	for d in world.dinosaurs:
		if d.health > 0: count += 1
	return count

func camp_in_combat() -> bool:
	for d in world.dinosaurs:
		if d.health <= 0 or world.dino_ai.state(d) != "alert": continue
		if d.position.distance_to(world.hero.position) < 12: return true
		for b in world.session.buildings:
			if b.hp > 0 and d.position.distance_to(world.board.point(b.cell)) < 10: return true
	return false

func spawn_group(species: Array, finale: bool = false, pressure: float = 0.0, health_multiplier: float = -1.0) -> void:
	var limit := 36 if world.session.mode == "standard" else 72
	var hard: bool = world.session.mode == "hard"
	if hard: limit = Hard.LIVING_LIMIT
	# Keep a small reserve for authored evacuation encounters, without removing live foes.
	if finale: limit += Hard.EVACUATION_RESERVE
	var available := maxi(0, limit - living_count())
	for i in range(mini(available, species.size())):
		if hard:
			# Every hard-wave member approaches a location snapshot; perception,
			# pursuit limits, obstacles and combat telegraphs still apply normally.
			var d: Node3D = world.dino_ai.spawn_patrol(species[i], world.extraction if finale else null)
			Hard.strengthen(d, pressure, health_multiplier)
		elif finale: world.dino_ai.spawn_patrol(species[i], world.extraction)
		elif i == 0: world.dino_ai.spawn_patrol(species[i])
		else: world.spawn_dinosaur(Vector3(10000, 0, 0), species[i])
	if hard and available < species.size():
		# A population cap must not leave the camp quiet forever while old
		# patrols idle elsewhere. Reuse nearby animals without healing/scaling them.
		var needed: int = species.size() - available
		var destination: Vector3 = world.extraction if finale else world.hero.position
		if not finale:
			for b in world.session.buildings:
				if b.kind == "tent" and b.hp > 0 and b.remaining <= 0:
					destination = world.board.point(b.cell)
					break
		for d in world.dinosaurs:
			if needed <= 0: break
			if d.position.distance_to(destination) > 60.0: continue
			if world.dino_ai.redirect_patrol(d, destination): needed -= 1

func update() -> void:
	var s = world.session
	if not s.completed_notice.is_empty():
		world.hud.toast("研究完成：" + world.Catalog.TECH[s.completed_notice].name)
		world.sound.play_ui("complete")
		s.completed_notice = ""
	if s.phase == "playing":
		if s.duration - s.elapsed <= 120 and not s.rescue_warned:
			s.rescue_warned = true
			world.hud.toast("救援将在 2 分钟内抵达！治疗伤势，查看北侧 H 撤离路线。")
			world.sound.play_ui("warning")
		for clock in world.spawn_clocks:
			if s.mode == "hard": continue
			if s.mode == "standard":
				var combat := camp_in_combat()
				if clock.get("contact", false) and not combat and not clock.get("recovery_used", false):
					# At most one short extension per wave; existing animals keep acting.
					clock.next = maxf(clock.next, minf(s.elapsed + 25.0, clock.next + 25.0))
					clock.recovery_used = true
				clock.contact = combat
				if not clock.get("warned", false) and clock.next - s.elapsed <= 12.0:
					clock.warned = true
					world.hud.toast("林间活动加剧。检查供电、修复防线，关闭电门。")
					world.sound.play_ui("warning")
			if s.elapsed >= clock.next:
				clock.next = s.elapsed + clock.period
				clock.recovery_used = false
				clock.warned = false
				spawn_group(group() if s.mode == "standard" else clock.species)
				world.hud.toast("林间传来咆哮……岛上出现了新的恐龙。")
	elif s.phase == "evacuate" and s.finale_wave < 3:
		if s.evacuation_elapsed >= s.finale_wave * 60.0:
			if s.mode == "standard": spawn_group(["raptor", "small_raptor"] if s.finale_wave < 2 else ["young_trex"], true)
			if s.finale_wave == 0:
				world.hud.toast("救援已抵达！5 分钟内前往北侧 H；生存模式需要守住停机坪 12 秒。")
				world.sound.play_ui("warning")
			s.finale_wave += 1
	if s.mode == "hard" and s.phase in ["playing", "evacuate"]:
		update_hard()

func objective() -> String:
	var s = world.session
	if s.phase == "evacuate": return "前往北侧 H 停机坪撤离"
	if not s.has_completed("tent"): return "① 落脚：建造免费帐篷"
	for b in s.buildings:
		if b.hp > 0 and b.remaining <= 0 and b.hp < world.Catalog.max_health(b) * 0.6:
			return "修复营地：" + world.Catalog.BUILDINGS[b.kind].name + "受损"
	if not s.has_completed("fire"): return "② 右键树木，返送 5 木建营火"
	if not s.has_completed("fossil"): return "③ 采集 10 木，建化石挖掘场"
	if not s.has_completed("generator"): return "④ 右键挖掘场采金，建立电力"
	if not s.has_completed("tower"): return "⑤ 建立弓箭塔与围栏防线"
	if s.duration - s.elapsed <= 180: return "救援准备：治疗并检查北侧路线"
	if not s.has_completed("laboratory"): return "⑥ 建基础建筑，选中后升级实验室"
	if s.technologies.is_empty(): return "⑦ 研究防御或工具，准备下一轮来袭"
	return "守住营地，修复受损建筑并准备撤离"
