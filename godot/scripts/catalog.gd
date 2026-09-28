extends RefCounted
## Most costs, HP, build times and prerequisites were read from the 6.5 candidate.
## Exception: fossil gold=0 is provisional (ngol inherited cost is unresolved).
## See docs/research/jurassic-park-6.5-reference.md; combat and terrain remain provisional.

const BUILDINGS = {
	"fossil": {"source_id": "n000", "name": "化石挖掘场", "wood": 10, "gold": 0, "power": 0, "supply": 0, "hp": 100.0, "time": 10.0, "requires": ["tent", "fire"], "description": "建成后右键采金，幸存者会将化石送回帐篷。"},
	"gate": {"source_id": "h00N", "name": "电门", "wood": 12, "gold": 12, "power": 1, "supply": 0, "hp": 300.0, "time": 10.0, "requires": ["generator"], "description": "右键开关，切换需要 5 秒。开门可通行，电击停止。"},
	"tent": {"source_id": "h002", "name": "帐篷", "wood": 0, "gold": 0, "power": 0, "supply": 0, "hp": 100.0, "time": 10.0, "requires": [], "description": "营地的起点。建成后可以建造营火和发电站。"},
	"fire": {"source_id": "h001", "name": "营火", "wood": 5, "gold": 0, "power": 0, "supply": 0, "hp": 75.0, "time": 4.0, "requires": ["tent"], "description": "照亮夜间营地。需要已完成的帐篷。"},
	"generator": {"source_id": "h004", "name": "发电站", "wood": 10, "gold": 10, "power": 0, "supply": 5, "hp": 100.0, "time": 10.0, "requires": ["tent"], "description": "提供 5 点电力，解锁防御设施。需要帐篷。"},
	"shelter": {"source_id": "h006", "name": "电栅栏", "wood": 12, "gold": 12, "power": 1, "supply": 0, "hp": 280.0, "time": 10.0, "requires": ["generator"], "description": "电击并减速 1.2 秒：小型 35%、大型 15%、首领 8%；不叠加。需供电。"},
	"tower": {"source_id": "h005", "name": "弓箭塔", "wood": 15, "gold": 15, "power": 1, "supply": 0, "hp": 200.0, "time": 18.0, "requires": ["generator"], "description": "自动攻击附近恐龙。射程 15.625 米，需要发电站。"},
	"lab": {"source_id": "h00D", "name": "基础建筑", "wood": 5, "gold": 5, "power": 1, "supply": 0, "hp": 50.0, "time": 5.0, "requires": ["generator"], "description": "建成后选中，使用升级功能变为实验室。"},
	"laboratory": {"source_id": "h008", "name": "实验室", "wood": 5, "gold": 5, "power": 2, "supply": 0, "hp": 100.0, "time": 10.0, "requires": ["generator"], "description": "营地实验室。"},
}
const ORDER = ["tent", "fire", "generator", "shelter", "tower", "lab", "fossil", "gate"]
const REFITS = {
	"range": {"name": "远射", "kinds": ["tower"], "wood": 12, "gold": 10, "time": 12.0, "description": "射程 20 米，间隔 1.35 秒；对喷毒龙伤害 +50%，默认优先远程目标。"},
	"rapid": {"name": "速射", "kinds": ["tower"], "wood": 10, "gold": 14, "time": 12.0, "description": "射程 11 米，攻击间隔 0.6 秒。适合覆盖入口和围栏后方。"},
	"heavy": {"name": "重弩", "kinds": ["tower"], "wood": 18, "gold": 22, "time": 18.0, "description": "射程 17 米，36 伤害 / 2.4 秒；大型伤害 +35%，忽略 75% 箭甲，默认优先大型目标。"},
	"brace": {"name": "加固", "kinds": ["shelter", "gate"], "wood": 14, "gold": 8, "time": 12.0, "description": "耐久上限 +180；保留原有伤势，改造期间停止电击。"},
}
const TOWER_REINFORCEMENT = {"wood": 12, "gold": 10, "time": 12.0, "hp": 120.0}

static func max_health(b: Dictionary) -> float:
	return float(BUILDINGS[b.kind].hp) + (180.0 if b.get("refit", "") == "brace" else 0.0) + (TOWER_REINFORCEMENT.hp if b.kind == "tower" and b.get("reinforced", false) else 0.0)

static func attack_range(b: Dictionary) -> float:
	if b.kind != "tower": return 2.8
	return {"range": 20.0, "rapid": 11.0, "heavy": 17.0}.get(b.get("refit", ""), 15.625)

static func attack_interval(b: Dictionary) -> float:
	return {"range": 1.35, "rapid": 0.6, "heavy": 2.4}.get(b.get("refit", ""), 1.0)

static func attack_damage(b: Dictionary) -> float:
	if b.kind != "tower": return 15.0
	return 36.0 if b.get("refit", "") == "heavy" else 10.0

static func target_priority(b: Dictionary) -> String:
	return b.get("priority", {"range": "ranged", "heavy": "large"}.get(b.get("refit", ""), "nearest"))
const SESSION_SECONDS = 3600.0
const EVACUATION_SECONDS = 300.0
const BOARDING_SECONDS = 12.0
const EXTRACTION_RADIUS = 3.0
const DAY_SECONDS = 150.0 # Still provisional, not Warcraft's verified day length.

# Original single-player progression, not verified Warcraft 6.5 rules.
const TECH_ORDER = ["tower_engineering", "pack_1", "pack_2", "pack_3", "tools", "defense", "medicine", "radio"]
const TECH = {
	"tower_engineering": {"name": "箭塔工程", "wood": 20, "gold": 15, "time": 25.0, "requires": "", "description": "解锁远射塔、速射塔与重弩塔。研究后选中箭塔，支付费用升级一项专精。"},
	"pack_1": {"name": "背负改良 I", "wood": 8, "gold": 5, "time": 20.0, "requires": "", "description": "每趟携带 2 单位资源。"},
	"pack_2": {"name": "背负改良 II", "wood": 18, "gold": 12, "time": 35.0, "requires": "pack_1", "description": "每趟携带 3 单位资源。"},
	"pack_3": {"name": "背负改良 III", "wood": 30, "gold": 20, "time": 45.0, "requires": "pack_2", "description": "每趟携带 4 单位资源。"},
	"tools": {"name": "精制工具", "wood": 12, "gold": 10, "time": 30.0, "requires": "", "description": "采集动作与施工效率提高 35%，返送仍需实际行走。"},
	"defense": {"name": "防线强化", "wood": 20, "gold": 20, "time": 45.0, "requires": "", "description": "塔、栅栏和电门伤害提高 30%，受到伤害降低 20%。"},
	"medicine": {"name": "营地医疗", "wood": 10, "gold": 12, "time": 25.0, "requires": "", "description": "帐篷治疗每 1 黄金恢复 25 生命（原为 10）。"},
	"radio": {"name": "修复救援电台", "wood": 35, "gold": 30, "time": 60.0, "requires": "", "description": "救援提前 5 分钟，至少保留 3 分钟准备时间；仅可研究一次。"},
}
