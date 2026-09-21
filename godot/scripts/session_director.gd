extends RefCounted
## Authored standard-mode pacing; local dinosaur perception remains authoritative.
var world: Node

func _init(owner_world: Node) -> void:
	world = owner_world

func configure() -> void:
	world.spawn_clocks.assign([{ "period": 95.0, "next": 100.0, "species": ["small_raptor"] }])

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

func spawn_group(species: Array, finale: bool = false) -> void:
	var limit := 36 if world.session.mode == "standard" else 72
	# Keep a small reserve for authored evacuation encounters, without removing live foes.
	if finale: limit += 6
	var available := maxi(0, limit - living_count())
	for i in range(mini(available, species.size())):
		if finale: world.dino_ai.spawn_patrol(species[i], world.extraction)
		elif i == 0: world.dino_ai.spawn_patrol(species[i])
		else: world.spawn_dinosaur(Vector3(10000, 0, 0), species[i])

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
			if s.elapsed >= clock.next:
				clock.next = s.elapsed + clock.period
				spawn_group(group() if s.mode == "standard" else clock.species)
				world.hud.toast("林间传来咆哮……岛上出现了新的恐龙。")
	elif s.phase == "evacuate" and s.finale_wave < 3:
		if s.evacuation_elapsed >= s.finale_wave * 60.0:
			if s.mode == "standard": spawn_group(["raptor", "small_raptor"] if s.finale_wave < 2 else ["young_trex"], true)
			if s.finale_wave == 0:
				world.hud.toast("救援已抵达！5 分钟内前往北侧 H；标准模式需要守住停机坪 12 秒。")
				world.sound.play_ui("warning")
			s.finale_wave += 1

func objective() -> String:
	var s = world.session
	if s.phase == "evacuate": return "前往北侧 H 停机坪撤离"
	if not s.has_completed("tent"): return "① 落脚：建造免费帐篷"
	if not s.has_completed("fire"): return "② 右键树木，返送 5 木建营火"
	if not s.has_completed("fossil"): return "③ 采集 10 木，建化石挖掘场"
	if not s.has_completed("generator"): return "④ 右键挖掘场采金，建立电力"
	if not s.has_completed("tower"): return "⑤ 建立弓箭塔与围栏防线"
	if s.duration - s.elapsed <= 180: return "救援准备：治疗并检查北侧路线"
	if not s.has_completed("laboratory"): return "⑥ 建基础建筑，选中后按 %s 升级" % world.preferences.key_name("upgrade")
	if s.technologies.is_empty(): return "⑦ 打开科技，选择物流或防御投资"
	if not s.technologies.has("radio"): return "发展营地，修复电台可提前救援"
	return "守住营地，准备撤离；受伤可回帐篷治疗"
