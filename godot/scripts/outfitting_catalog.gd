extends RefCounted
## Personal equipment is separate from camp technology and archived survival systems.
const ITEMS := {
	"medkit": {"name":"急救包", "slot":"kits", "rank":0, "wood":4, "gold":5, "time":10.0, "description":"恢复 50 生命 · 冷却 20 秒 · 最多携带 3 个", "blueprint":""},
	"boots": {"name":"探险靴", "slot":"boots", "rank":1, "wood":8, "gold":10, "time":18.0, "description":"移动速度 +10% · 装备后持续生效", "blueprint":""},
	"vest": {"name":"防护背心", "slot":"vest", "rank":1, "wood":10, "gold":12, "time":20.0, "description":"恐龙直接攻击伤害 -15% · 不抵挡毒液", "blueprint":""},
	"rifle": {"name":"改良步枪", "slot":"rifle", "rank":1, "wood":12, "gold":18, "time":25.0, "description":"步枪伤害 +25% · 射程与枪声范围不变", "blueprint":""},
	"boots_2": {"name":"越野靴", "slot":"boots", "rank":2, "wood":14, "gold":20, "time":25.0, "description":"移动速度 +15% · 替换探险靴，不叠加", "blueprint":"ranger"},
	"vest_2": {"name":"强化背心", "slot":"vest", "rank":2, "wood":18, "gold":24, "time":30.0, "description":"直接攻击伤害 -25% · 替换旧护甲，不抵挡毒液", "blueprint":"ranger"},
	"rifle_2": {"name":"精校步枪", "slot":"rifle", "rank":2, "wood":20, "gold":30, "time":35.0, "description":"步枪伤害 +50% · 替换旧枪，仍需站定射击", "blueprint":"arsenal"},
}
const SITES := {
	"supplies": {"name":"林缘补给箱", "at":Vector2(18, 12), "scene":"survey_camp", "seconds":6.0, "wood":8, "gold":6, "kits":1, "guards":[], "description":"短途 · 带回补给后获得 8 木 / 6 金 / 急救包 ×1"},
	"ranger": {"name":"废弃巡护站", "at":Vector2(-32, 26), "scene":"field_clinic", "seconds":10.0, "wood":12, "gold":18, "kits":0, "guards":["raptor"], "description":"中途 · 迅猛龙活动 · 带回越野靴和强化背心图纸、12 木 / 18 金"},
	"arsenal": {"name":"山地军械库", "at":Vector2(46, -36), "scene":"research_archive", "seconds":14.0, "wood":18, "gold":28, "kits":0, "guards":["young_trex", "raptor"], "description":"远途 · 大型恐龙活动 · 带回精校步枪图纸、18 木 / 28 金"},
}

static func actor() -> Dictionary:
	return {"boots":0, "vest":0, "rifle":0, "kits":0, "cooldown":0.0, "cargo":[], "task":"", "target":-1, "site":""}

static func empty() -> Dictionary:
	return {"actors":{"1":actor(), "2":actor()}, "jobs":{}, "sites":{}, "blueprints":[], "reserve_kits":0}

static func validate(value: Variant, buildings: Array) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true # Earlier saves initialize safely after load.
	for key in ["actors", "jobs", "sites"]:
		if not value.get(key) is Dictionary: return false
	if not value.get("blueprints") is Array or not value.get("reserve_kits") is int or value.reserve_kits < 0 or value.reserve_kits > 3: return false
	if value.actors.size() != 2 or not value.actors.has_all(["1", "2"]): return false
	var carried := []
	for entry in value.actors.values():
		if not entry is Dictionary: return false
		for key in actor():
			if not entry.has(key) or typeof(entry[key]) != typeof(actor()[key]): return false
		for slot in ["boots", "vest", "rifle"]:
			if entry[slot] not in range(3): return false
		if entry.kits not in range(4) or entry.cooldown < 0 or entry.cooldown > 20: return false
		if entry.task not in ["", "collect", "explore", "return"] or (entry.task == "explore" and entry.site not in SITES): return false
		if entry.task == "collect" and entry.target <= 0: return false
		for id in entry.cargo:
			if id not in SITES or id in carried: return false
			carried.append(id)
	if value.sites.size() not in [0, SITES.size()]: return false
	var cells := []
	for id in value.sites:
		var site: Variant = value.sites[id]
		if id not in SITES or not site is Dictionary: return false
		if not site.get("cell") is Vector2i or not Rect2i(1,1,126,126).has_point(site.cell) or site.cell in cells: return false
		cells.append(site.cell)
		if site.get("status") not in ["known", "carried", "completed"] or not site.get("progress") is float or not site.get("guarded") is bool: return false
		if site.progress < 0 or site.progress > SITES[id].seconds: return false
		if (site.status == "carried") != (id in carried): return false
		if site.status != "known" and site.progress != SITES[id].seconds: return false
	for id in carried:
		if not value.sites.has(id): return false
	var blueprints := []
	for id in value.blueprints:
		if id not in ["ranger", "arsenal"] or id in blueprints or not value.sites.has(id) or value.sites[id].status != "completed": return false
		blueprints.append(id)
	for key in value.jobs:
		var job: Variant = value.jobs[key]
		if not key is String or not key.is_valid_int() or not job is Dictionary: return false
		if job.get("item") not in ITEMS or job.get("owner") not in ["1", "2"] or not job.get("remaining") is float: return false
		if job.remaining < 0 or job.remaining > ITEMS[job.item].time: return false
		# Destroyed workshops may persist until the next simulation tick clears their job.
		if not buildings.any(func(b): return b is Dictionary and b.get("id") == int(key) and b.get("kind") == "workshop"): return false
	return true
