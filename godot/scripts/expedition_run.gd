extends RefCounted
## Persist the authored draw, not just its seed, so saves never redraw content.
const MAX_SEED := 999999999
const EVENTS = [
	{"id": "barter", "title": "维修组的建材清单", "text": "维修组提供了一份拆解方案。消耗 8 黄金，从库存零件中回收 16 木材；也可以留着黄金发展电力。", "choices": [{"name": "拆解零件 · 8 金换 16 木", "wood": 0, "gold": 8, "effect": "lumber"}, {"name": "保留零件", "wood": 0, "gold": 0, "effect": "none"}]},
	{"id": "clinic_lead", "title": "医护人员的最后留言", "text": "自动录音提到冰原急救站留有药品。只记录坐标不会获得物资；仍需到现场调查。", "choices": [{"name": "记录急救站坐标", "wood": 0, "gold": 0, "effect": "reveal_clinic"}, {"name": "先照顾营地", "wood": 0, "gold": 0, "effect": "none"}]},
	{"id": "survey", "title": "被遗弃的取样路线", "text": "调查员留下了雨林采样区的坐标。现场采样会产生噪声，资料需要带回帐篷；可以先记录，稍后再决定是否出发。", "choices": [{"name": "记录采样区坐标", "wood": 0, "gold": 0, "effect": "reveal_nest"}, {"name": "暂不远征", "wood": 0, "gold": 0, "effect": "none"}]},
	{"id": "materials", "title": "备用材料再利用", "text": "剩余零件可以拆成支撑件，用于抢修或扩建。消耗 12 黄金获得 22 木材；拆解不会自动维修建筑。", "choices": [{"name": "拆取支撑件 · 12 金换 22 木", "wood": 0, "gold": 12, "effect": "reinforcements"}, {"name": "保留研究经费", "wood": 0, "gold": 0, "effect": "none"}]},
]
const POOLS = [["map"], ["battery", "barter"], ["medicine", "clinic_lead"], ["tracks", "survey"], ["research", "materials"], ["route"], ["clinic"], ["last_supply"]]
const TIMES = [180.0, 300.0, 450.0, 600.0, 780.0, 960.0, 1110.0, 1320.0]
const CONTRACTS = {
	"medicine": {"name": "找回医疗物资", "sites": ["cache", "clinic"], "text": "救援队希望确认勘测营和急救站的情况。完成两处任一调查方案，再回帐篷整理记录。", "wood": 0, "gold": 6, "kits": 1},
	"signal": {"name": "恢复岛屿联络", "sites": ["relay", "weather"], "text": "中继和气象记录能帮助救援队判断岛上情况。修复两处设备，再回帐篷整理记录。", "wood": 8, "gold": 12, "kits": 0},
	"evidence": {"name": "追查撤离经过", "sites": ["cache", "archive"], "text": "勘测记录与研究档案可能解释迟到的撤离命令。完成调查并带回档案，再回帐篷整理记录。", "wood": 8, "gold": 8, "kits": 0},
	"ecology": {"name": "带回野外证据", "sites": ["nest", "archive"], "text": "对照新采集的样本和旧档案，判断岛上生物活动。两份资料都必须带回帐篷。", "wood": 0, "gold": 12, "kits": 1},
}

static func create(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = clampi(seed_value, 1, MAX_SEED)
	var plan := []
	for i in range(POOLS.size()):
		var pool: Array = POOLS[i]
		plan.append({"id": pool[rng.randi_range(0, pool.size() - 1)], "at": TIMES[i] + (0.0 if i == 0 else float(rng.randi_range(-25, 25)))})
	var candidates := CONTRACTS.keys()
	var offers := []
	for i in range(2):
		var index := rng.randi_range(0, candidates.size() - 1)
		offers.append(candidates[index])
		candidates.remove_at(index)
	return {"seed": int(rng.seed), "plan": plan, "offers": offers, "active": "", "claimed": false}

static func validate(run: Dictionary, records: Array) -> bool:
	if run.is_empty(): return true
	if not run.get("seed") is int or run.seed < 1 or run.seed > MAX_SEED: return false
	if not run.get("plan") is Array or run.plan.size() != POOLS.size(): return false
	for i in range(POOLS.size()):
		var item: Variant = run.plan[i]
		if not item is Dictionary or item.get("id") not in POOLS[i]: return false
		if not item.get("at") is float or not is_finite(item.at) or absf(item.at - TIMES[i]) > (0 if i == 0 else 25): return false
	if not run.get("offers") is Array or run.offers.size() != 2: return false
	if run.offers[0] == run.offers[1]: return false
	for id in run.offers:
		if not id is String or not CONTRACTS.has(id): return false
	if not run.get("active") is String or not run.get("claimed") is bool: return false
	if not run.active.is_empty() and not run.offers.has(run.active): return false
	if run.claimed:
		if run.active.is_empty(): return false
		for site in CONTRACTS[run.active].sites:
			if not records.has(site): return false
	return true
