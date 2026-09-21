extends RefCounted
const Run = preload("res://scripts/expedition_run.gd")
var world: Node

func _init(owner_world: Node) -> void:
	world = owner_world

func data() -> Dictionary:
	return world.session.adventure.get("run", {})

func accept(id: String) -> String:
	var run := data()
	if world.session.phase != "playing" or run.is_empty(): return "当前无法接受委托"
	if not run.active.is_empty(): return "本局已选择委托；可自由决定是否完成，不会扣除资源"
	if not run.offers.has(id): return "此委托不在本局候选中"
	run.active = id
	for site_id in Run.CONTRACTS[id].sites:
		var site: Dictionary = world.session.adventure.sites[site_id]
		if site.status == "hidden": site.status = "known"
	world.adventure.note("已接受委托：" + Run.CONTRACTS[id].name + "。坐标已记入日志；奖励需完成调查后回帐篷领取。")
	return ""

func completed_count(id: String) -> int:
	var count := 0
	for site in Run.CONTRACTS[id].sites:
		if world.session.adventure.records.has(site): count += 1
	return count

func reward_text(id: String) -> String:
	var spec: Dictionary = Run.CONTRACTS[id]
	return "额外补给：%d 木 / %d 金 / %d 急救包" % [spec.wood, spec.gold, spec.kits]

func settle() -> void:
	var run := data()
	if run.is_empty() or run.active.is_empty() or run.claimed or world.hero.health <= 0: return
	if world.session.phase not in ["playing", "evacuate"] or completed_count(run.active) != 2: return
	for b in world.session.buildings:
		if b.hp <= 0 or b.remaining > 0 or b.kind != "tent": continue
		if world.hero.position.distance_to(world.board.point(b.cell)) > 3: continue
		var spec: Dictionary = Run.CONTRACTS[run.active]
		run.claimed = true
		world.session.wood += spec.wood
		world.session.gold += spec.gold
		world.session.adventure.kits += spec.kits
		world.adventure.note("委托完成：" + spec.name + "。" + reward_text(run.active))
		world.sound.play_ui("complete")
		return

func status_text() -> String:
	var run := data()
	if run.is_empty(): return "原有探索计划 · 保留载入前的事件安排"
	var text := "探索编号 %d" % run.seed
	if run.active.is_empty(): return text + " · 本局有两项可选委托，可择一接受"
	var spec: Dictionary = Run.CONTRACTS[run.active]
	return text + " · " + spec.name + (" · 已领取" if run.claimed else (" · 返回帐篷领取" if completed_count(run.active) == 2 else " · %d / 2" % completed_count(run.active)))
