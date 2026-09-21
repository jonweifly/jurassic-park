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
	"shelter": {"source_id": "h006", "name": "电栅栏", "wood": 12, "gold": 12, "power": 1, "supply": 0, "hp": 280.0, "time": 10.0, "requires": ["generator"], "description": "阻挡恐龙的通路，并电击附近敌人。需要发电站。"},
	"tower": {"source_id": "h005", "name": "弓箭塔", "wood": 15, "gold": 15, "power": 1, "supply": 0, "hp": 200.0, "time": 18.0, "requires": ["generator"], "description": "自动攻击附近恐龙。射程 15.625 米，需要发电站。"},
	"lab": {"source_id": "h00D", "name": "基础建筑", "wood": 5, "gold": 5, "power": 1, "supply": 0, "hp": 50.0, "time": 5.0, "requires": ["generator"], "description": "建成后选中，使用升级功能变为实验室。"},
	"laboratory": {"source_id": "h008", "name": "实验室", "wood": 5, "gold": 5, "power": 2, "supply": 0, "hp": 100.0, "time": 10.0, "requires": ["generator"], "description": "营地实验室。"},
}
const ORDER = ["tent", "fire", "generator", "shelter", "tower", "lab", "fossil", "gate"]
const SESSION_SECONDS = 3600.0
const EVACUATION_SECONDS = 300.0
const BOARDING_SECONDS = 12.0
const EXTRACTION_RADIUS = 3.0
const DAY_SECONDS = 150.0 # Still provisional, not Warcraft's verified day length.

# Original single-player progression, not verified Warcraft 6.5 rules.
const TECH_ORDER = ["pack_1", "pack_2", "pack_3", "tools", "defense", "medicine", "radio"]
const TECH = {
	"pack_1": {"name": "背负改良 I", "wood": 8, "gold": 5, "time": 20.0, "requires": "", "description": "每趟携带 2 单位资源。"},
	"pack_2": {"name": "背负改良 II", "wood": 18, "gold": 12, "time": 35.0, "requires": "pack_1", "description": "每趟携带 3 单位资源。"},
	"pack_3": {"name": "背负改良 III", "wood": 30, "gold": 20, "time": 45.0, "requires": "pack_2", "description": "每趟携带 4 单位资源。"},
	"tools": {"name": "精制工具", "wood": 12, "gold": 10, "time": 30.0, "requires": "", "description": "采集动作与施工效率提高 35%，返送仍需实际行走。"},
	"defense": {"name": "防线强化", "wood": 20, "gold": 20, "time": 45.0, "requires": "", "description": "塔、栅栏和电门伤害提高 30%，受到伤害降低 20%。"},
	"medicine": {"name": "营地医疗", "wood": 10, "gold": 12, "time": 25.0, "requires": "", "description": "帐篷治疗每 1 黄金恢复 25 生命（原为 10）。"},
	"radio": {"name": "修复救援电台", "wood": 35, "gold": 30, "time": 60.0, "requires": "", "description": "救援提前 5 分钟，至少保留 3 分钟准备时间；仅可研究一次。"},
}
