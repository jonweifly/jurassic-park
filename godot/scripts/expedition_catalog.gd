extends RefCounted
const Run = preload("res://scripts/expedition_run.gd")
## Original optional island content. These are not asserted Warcraft 6.5 rules.
const SITE_ORDER = ["cache", "clinic", "relay", "nest", "weather", "archive"]
const SITES = {
	"cache": {"name": "失联勘测营", "at": Vector2(-19, 11), "scene": "survey_camp", "seconds": 7.0, "type": "salvage", "description": "测绘队留下了密封补给。选择建筑材料或贵重零件；搜寻时会发出局部噪声。", "lore": "勘测日志 01：围栏断电后，队员们沿北侧维护通道撤离。值班员没有等到最后一通回电。", "choices": [{"name": "回收建材 · 18 木", "wood": 0, "gold": 0, "reward_wood": 18, "reward_gold": 0, "kits": 0}, {"name": "回收零件 · 12 金", "wood": 0, "gold": 0, "reward_wood": 0, "reward_gold": 12, "kits": 0}]},
	"clinic": {"name": "冰原急救站", "at": Vector2(-40, -48), "scene": "field_clinic", "seconds": 9.0, "type": "salvage", "description": "冷藏箱仍保持密封。急救包可在野外使用；也可拆走零件投资营地。", "lore": "急救记录：伤员已向停机坪转移。医护人员把最后一箱药留给后来者。", "choices": [{"name": "取出急救包 × 2", "wood": 0, "gold": 0, "reward_wood": 0, "reward_gold": 0, "kits": 2}, {"name": "拆取医疗零件 · 20 金", "wood": 0, "gold": 0, "reward_wood": 0, "reward_gold": 20, "kits": 0}]},
	"relay": {"name": "山地中继站", "at": Vector2(43, -43), "scene": "relay_station", "seconds": 16.0, "type": "repair", "description": "消耗 8 木 / 5 金修复中继，救援提前 90 秒，至少保留 3 分钟准备；公布岛上设施坐标。", "lore": "收到救援队回电：信号已经稳定。我们还在找天气窗口，保持停机坪畅通。", "choices": [{"name": "修复中继 · 8 木 / 5 金", "wood": 8, "gold": 5, "reward_wood": 0, "reward_gold": 0, "kits": 0}]},
	"nest": {"name": "雨林旧采样区", "at": Vector2(-44, 44), "scene": "sample_nest", "seconds": 12.0, "type": "sample", "description": "原采样区出现了新鲜足迹。取样后必须带回已建成的帐篷，才能结算。谨慎取样获 24 金；密集取样获 36 金，但噪声传播距离加倍，两者均需 12 秒。", "lore": "调查记录：迅猛龙会对近处同伴的警告作出反应，但树林和距离仍能切断追踪。", "choices": [{"name": "谨慎取样 · 24 金 / 噪声 8 米", "wood": 0, "gold": 0, "reward_wood": 0, "reward_gold": 24, "kits": 0}, {"name": "密集取样 · 36 金 / 噪声 16 米", "wood": 0, "gold": 0, "reward_wood": 0, "reward_gold": 36, "kits": 0, "noise": 16.0}]},
	"weather": {"name": "沼泽气象台", "at": Vector2(42, 44), "scene": "weather_station", "seconds": 18.0, "type": "repair", "description": "消耗 6 木 / 4 金恢复气象记录，获得 14 金与一份灾变记录。传输期间需留在设备旁，近处有恐龙时暂停。", "lore": "气象记录：事故发生前，维护系统多次要求检修备用供电。暴雨只是最后一根稻草。", "choices": [{"name": "恢复记录 · 6 木 / 4 金", "wood": 6, "gold": 4, "reward_wood": 0, "reward_gold": 14, "kits": 0}]},
	"archive": {"name": "旧研究档案室", "at": Vector2(24, 6), "scene": "research_archive", "seconds": 10.0, "type": "sample", "description": "取回密封档案并带回帐篷：获得 12 木 / 16 金。集齐勘测、气象与研究记录，还可还原事故经过并获得 1 个急救包。", "lore": "研究档案：停电导致围栏失效，撤离命令却被延误。记录事故经过，让后来者知道这座岛发生过什么。", "choices": [{"name": "取回档案 · 带回营地结算", "wood": 0, "gold": 0, "reward_wood": 12, "reward_gold": 16, "kits": 0}]},
}
const EVENTS = [
	{"id": "map", "at": 180.0, "title": "断续的维护频道", "text": "旧频道里传来一段坐标：一处勘测营还有未取走的补给。可以记录坐标，或先专注营地。", "choices": [{"name": "记录坐标", "wood": 0, "gold": 0, "effect": "reveal_cache"}, {"name": "稍后再说", "wood": 0, "gold": 0, "effect": "none"}]},
	{"id": "battery", "at": 300.0, "title": "备用电池调配", "text": "营地能用一批零件组装应急电源。8 黄金换取 3 分钟额外 2 点电力，结束后仍需正常发电站。", "choices": [{"name": "接入应急电源 · 8 金", "wood": 0, "gold": 8, "effect": "power"}, {"name": "保留零件", "wood": 0, "gold": 0, "effect": "none"}]},
	{"id": "medicine", "at": 450.0, "title": "营地应急物资", "text": "可以把库存材料制成一份便携急救包。它能在野外恢复 50 生命，也可以留着材料继续建设。", "choices": [{"name": "制作急救包 · 10 木 / 5 金", "wood": 10, "gold": 5, "effect": "kit"}, {"name": "优先建设", "wood": 0, "gold": 0, "effect": "none"}]},
	{"id": "tracks", "at": 600.0, "title": "大型足迹报告", "text": "维护频道报告了大型足迹。扫描需要耗费零件，会短暂显示幸存者周围 22 米内的目标；也可保留资源，靠视线观察。", "choices": [{"name": "短程扫描 45 秒 · 6 金", "wood": 0, "gold": 6, "effect": "scan"}, {"name": "保持警戒", "wood": 0, "gold": 0, "effect": "none"}]},
	{"id": "research", "at": 780.0, "title": "研究设备校准", "text": "投入零件校准设备，接下来 3 分钟研究速度提高 25%。仍然需要已完成的实验室和足够电力。", "choices": [{"name": "校准设备 · 8 金", "wood": 0, "gold": 8, "effect": "research"}, {"name": "维持现状", "wood": 0, "gold": 0, "effect": "none"}]},
	{"id": "route", "at": 960.0, "title": "救援队询问方位", "text": "救援队要求更清楚的地面标记。消耗建材制作标识可让救援提前 45 秒，至少保留 3 分钟准备。", "choices": [{"name": "制作标识 · 12 木", "wood": 12, "gold": 0, "effect": "rescue"}, {"name": "按原计划等待", "wood": 0, "gold": 0, "effect": "none"}]},
	{"id": "clinic", "at": 1110.0, "title": "未关闭的急救频道", "text": "急救站自动信标仍在广播。它可能有药物，但探索途中需要离开营地防线。", "choices": [{"name": "记录急救站坐标", "wood": 0, "gold": 0, "effect": "reveal_clinic"}, {"name": "留守营地", "wood": 0, "gold": 0, "effect": "none"}]},
	{"id": "last_supply", "at": 1320.0, "title": "撤离前的补给取舍", "text": "撤离前可以把 10 黄金换成一份急救包。也可以把黄金留作帐篷治疗或防线维护。", "choices": [{"name": "准备急救包 · 10 金", "wood": 0, "gold": 10, "effect": "kit"}, {"name": "保留黄金", "wood": 0, "gold": 0, "effect": "none"}]},
]

static func empty_state() -> Dictionary:
	return {"run": {}, "sites": {}, "job": {}, "cargo": [], "records": [], "history": [], "events_done": [], "offer": "", "offer_until": 0.0, "tracked": "", "kits": 0, "kit_cooldown": 0.0, "power_until": 0.0, "scan_until": 0.0, "research_until": 0.0, "story_rewarded": false}

static func event(id: String) -> Dictionary:
	for entry in EVENTS + Run.EVENTS:
		if entry.id == id: return entry
	return {}

static func validate(state: Dictionary) -> bool:
	if state.is_empty(): return true # Version-1 saves and not-yet-initialized sessions.
	var defaults := empty_state()
	for key in defaults:
		if not state.has(key) or typeof(state[key]) != typeof(defaults[key]): return false
	if not Run.validate(state.run, state.records): return false
	if not state.run.is_empty():
		var planned := []
		for item in state.run.plan: planned.append(item.id)
		for id in state.events_done:
			if not planned.has(id): return false
		if not state.offer.is_empty() and not planned.has(state.offer): return false
	if state.kits < 0 or state.kits > 99 or state.kit_cooldown < 0: return false
	if state.sites.size() != SITE_ORDER.size(): return false
	var occupied := {}
	for id in state.sites:
		var site: Variant = state.sites[id]
		if not SITES.has(id) or not site is Dictionary: return false
		if not site.get("cell") is Vector2i or not Rect2i(1, 1, 126, 126).has_point(site.cell): return false
		if site.get("status") not in ["hidden", "known", "discovered", "carried", "completed"]: return false
		if not site.get("progress") is float or not site.get("choice") is int or not site.get("paid") is bool: return false
		if site.choice < -1 or site.choice >= SITES[id].choices.size() or not is_finite(site.progress) or site.progress < 0 or site.progress > SITES[id].seconds: return false
		if occupied.has(site.cell): return false
		occupied[site.cell] = true
		if site.paid != (site.choice >= 0): return false
		if site.status in ["carried", "completed"] and (not site.paid or site.progress < SITES[id].seconds): return false
		if site.status == "carried" and (SITES[id].type != "sample" or not state.cargo.has(id)): return false
		if (site.status == "completed") != state.records.has(id): return false
	for key in ["cargo", "records", "events_done"]:
		var unique := {}
		for id in state[key]:
			if not id is String or unique.has(id): return false
			unique[id] = true
	for entry in state.history:
		if not entry is Dictionary or not entry.get("at") is float or not entry.get("text") is String: return false
	if state.history.size() > 32: return false
	for key in ["kit_cooldown", "offer_until", "power_until", "scan_until", "research_until"]:
		if not is_finite(state[key]) or state[key] < 0: return false
	for id in state.cargo:
		if not SITES.has(id) or not state.sites.has(id) or state.sites[id].status != "carried": return false
	for id in state.records:
		if not SITES.has(id): return false
	for id in state.events_done:
		if event(id).is_empty(): return false
	if not state.offer.is_empty() and (event(state.offer).is_empty() or state.events_done.has(state.offer)): return false
	if not state.tracked.is_empty() and not state.sites.has(state.tracked): return false
	if not state.job.is_empty():
		if not state.job.get("id") is String or not state.sites.has(state.job.id) or not state.job.get("inspect") is bool: return false
		if not state.job.inspect and (not state.sites[state.job.id].paid or state.sites[state.job.id].status != "discovered"): return false
	return true
