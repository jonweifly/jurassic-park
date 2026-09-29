extends RefCounted
const Catalog = preload("res://scripts/catalog.gd")
const Features = preload("res://scripts/feature_policy.gd")
const Dinosaurs = preload("res://scripts/dinosaur_catalog.gd")

var wood: int = 0 # Provisional: inherited starting lumber still needs verification.
var gold: int = 10
var elapsed: float = 0.0
var phase: String = "playing"
var buildings: Array[Dictionary] = []
var next_id: int = 1
var harvest_level: int = 0
var duration: float = Catalog.SESSION_SECONDS
var evacuation_elapsed: float = 0.0
var kills: int = 0
var kills_by_species: Dictionary = {}
var mode := "classic"

func record_kill(species: String) -> void:
	kills += 1
	if Dinosaurs.SPECIES.has(species):
		kills_by_species[species] = int(kills_by_species.get(species, 0)) + 1

func unclassified_kills() -> int:
	var classified := 0
	for amount in kills_by_species.values(): classified += int(amount)
	return maxi(0, kills - classified)

static func mode_name(value: String) -> String:
	return {"classic": "长局模式", "standard": "标准生存", "hard": "困难生存"}.get(value, "长局模式")

var technologies: Dictionary = {}
var research_job: Dictionary = {}
var completed_notice := ""
var rescue_warned := false
var finale_wave := 0
var next_dinosaur_id := 1
var healing_spent := 0
var boarding_progress := 0.0
var adventure: Dictionary = {}
var outfitting: Dictionary = {}
var profession := "explorer"

const PROFESSIONS := {
	"explorer": {"name": "探险者", "description": "移动更快，适合采集和返送。", "speed": 1.12, "capacity": 0, "max_health": 0.0, "damage": 1.0, "hunt": 1},
	"doctor": {"name": "医生", "description": "生命上限更高，帐篷治疗效果提升。", "speed": 0.98, "capacity": 0, "max_health": 20.0, "damage": 1.0, "hunt": 0},
	"hunter": {"name": "猎人", "description": "狩猎产出更多肉类，适合主动获取食物。", "speed": 1.0, "capacity": 0, "max_health": 0.0, "damage": 1.12, "hunt": 1},
	"soldier": {"name": "军人", "description": "战斗伤害更高、生命更稳，但负重较低。", "speed": 1.0, "capacity": -1, "max_health": 12.0, "damage": 1.28, "hunt": 0},
}

static func profession_spec(id: String) -> Dictionary:
	return PROFESSIONS.get(id, PROFESSIONS.explorer)

func profession_name() -> String:
	return profession_spec(profession).name

# Lightweight survivor loop. Values are intentionally session-owned so they
# remain deterministic and can be restored independently of scene instances.
var hunger: float = 100.0
var fatigue: float = 0.0
var food: int = 2
var raw_meat: int = 0
var cooked_meat: int = 0
var berries: int = 0
var survival_clock: float = 0.0
var survival_damage: float = 0.0

const MAX_HUNGER := 100.0
const MAX_FATIGUE := 100.0

func survival_status() -> String:
	return "饱腹 %d%% · 疲劳 %d%% · 食物 %d · 熟肉 %d" % [roundi(hunger), roundi(fatigue), food + berries, cooked_meat]

func eat_food() -> bool:
	if not Features.peripheral_enabled: return false
	var restored := 0.0
	if cooked_meat > 0:
		cooked_meat -= 1
		restored = 38.0
	elif berries > 0:
		berries -= 1
		restored = 20.0
	elif food > 0:
		food -= 1
		restored = 24.0
	else:
		return false
	hunger = minf(MAX_HUNGER, hunger + restored)
	fatigue = maxf(0.0, fatigue - 3.0)
	return true

func cook_food() -> bool:
	if not Features.peripheral_enabled: return false
	if raw_meat <= 0 or not has_completed("fire"): return false
	raw_meat -= 1
	cooked_meat += 1
	return true

func rest(dt: float) -> void:
	if not Features.peripheral_enabled: return
	fatigue = maxf(0.0, fatigue - dt * 22.0)
	hunger = maxf(0.0, hunger - dt * 0.05)

func add_hunted_food(amount: int = 1) -> void:
	if not Features.peripheral_enabled: return
	var bonus: int = int(profession_spec(profession).hunt)
	raw_meat = mini(20, raw_meat + maxi(0, amount + bonus))

func add_berries(amount: int = 1) -> void:
	if not Features.peripheral_enabled: return
	berries = mini(8, berries + maxi(0, amount))

func research_error(tech: String) -> String:
	if phase != "playing": return "撤离阶段不能开始研究"
	if not Catalog.TECH.has(tech): return "未知研究项目"
	if technologies.has(tech): return "已完成研究"
	if not research_job.is_empty(): return "实验室正在研究其他项目"
	if not has_completed("laboratory"): return "需要已完成的实验室（选中基础建筑后使用升级功能）"
	if supply() < demand(): return "电力不足，请恢复供电"
	var spec: Dictionary = Catalog.TECH[tech]
	if not spec.requires.is_empty() and not technologies.has(spec.requires): return "需要先研究" + Catalog.TECH[spec.requires].name
	if wood < spec.wood or gold < spec.gold: return "需要 %d 木材和 %d 黄金" % [spec.wood, spec.gold]
	return ""

func begin_research(tech: String) -> String:
	var error := research_error(tech)
	if not error.is_empty(): return error
	var spec: Dictionary = Catalog.TECH[tech]
	wood -= spec.wood
	gold -= spec.gold
	research_job = {"tech": tech, "remaining": spec.time}
	return ""

func research_powered() -> bool:
	return has_completed("laboratory") and supply() >= demand()

func work_multiplier() -> float:
	return 1.35 if technologies.has("tools") else 1.0

func carry_capacity_bonus() -> int:
	if not Features.peripheral_enabled: return 0
	return int(profession_spec(profession).capacity)

func survivor_speed() -> float:
	# Preserve the former default explorer's movement feel without role modifiers.
	if not Features.peripheral_enabled: return 5.6
	return 5.0 * float(profession_spec(profession).speed)

func survivor_max_health() -> float:
	if not Features.peripheral_enabled: return 150.0
	return 150.0 + float(profession_spec(profession).max_health)

func survivor_damage() -> float:
	if not Features.peripheral_enabled: return 13.0
	return 13.0 * float(profession_spec(profession).damage)

func healing_amount() -> float:
	var base := 25.0 if technologies.has("medicine") else 10.0
	return base * (1.25 if Features.peripheral_enabled and profession == "doctor" else 1.0)

func defense_multiplier() -> float:
	return 1.3 if technologies.has("defense") else 1.0

func stage_name() -> String:
	if phase == "evacuate": return "最终撤离"
	if duration - elapsed <= 180: return "救援准备"
	if elapsed >= 720: return "危机期"
	if elapsed >= 360: return "扩张期"
	return "建立营地"

func game_time() -> float:
	return elapsed + evacuation_elapsed

func supply() -> int:
	var value := 2 if Features.peripheral_enabled and game_time() < adventure.get("power_until", 0.0) else 0
	for b in buildings:
		if b.hp > 0 and b.remaining <= 0:
			value += Catalog.BUILDINGS[b.kind].supply
	return value

func demand() -> int:
	var value := 0
	for b in buildings:
		if b.hp > 0:
			value += Catalog.BUILDINGS[b.kind].power
	return value

func can_afford(kind: String) -> String:
	if phase != "playing": return "本局已结束"
	if not Catalog.BUILDINGS.has(kind): return "未知建筑"
	var spec: Dictionary = Catalog.BUILDINGS[kind]
	for requirement in spec.requires:
		if not has_completed(requirement): return "需要先建成" + Catalog.BUILDINGS[requirement].name
	if wood < spec.wood: return "木材不足"
	if gold < spec.gold: return "黄金不足"
	if spec.power > 0 and demand() + spec.power > supply(): return "电力不足，请先建成发电站"
	return ""

func build(kind: String, cell: Vector2i, rotation: float = 0.0) -> Dictionary:
	if not is_finite(rotation): return {}
	if not can_afford(kind).is_empty(): return {}
	var spec: Dictionary = Catalog.BUILDINGS[kind]
	wood -= spec.wood
	gold -= spec.gold
	var b := {"id": next_id, "kind": kind, "cell": cell, "hp": spec.hp, "remaining": spec.time, "cooldown": 0.0, "invested_wood": spec.wood, "invested_gold": spec.gold}
	if kind in ["shelter", "gate"]: b.rotation = fposmod(roundf(rotation / (PI * 0.5)), 4.0) * PI * 0.5
	next_id += 1
	buildings.append(b)
	return b

func has_completed(kind: String) -> bool:
	for b in buildings:
		if b.kind == kind and b.hp > 0 and b.remaining <= 0: return true
	return false

func tick(dt: float) -> void:
	if phase not in ["playing", "evacuate"]: return
	if Features.peripheral_enabled:
		survival_clock += dt
		hunger = maxf(0.0, hunger - dt * 0.012)
		fatigue = minf(MAX_FATIGUE, fatigue + dt * 0.010)
		if hunger <= 8.0: fatigue = minf(MAX_FATIGUE, fatigue + dt * 0.018)
		if hunger <= 3.0: health_damage_tick(dt * 1.2)
		elif fatigue >= 96.0: health_damage_tick(dt * 0.45)

	if phase == "playing" and not research_job.is_empty() and research_powered():
		research_job.remaining = maxf(0, research_job.remaining - dt * (1.25 if Features.peripheral_enabled and game_time() < adventure.get("research_until", 0.0) else 1.0))
		if research_job.remaining <= 0:
			var tech: String = research_job.tech
			technologies[tech] = true
			if tech.begins_with("pack_"): harvest_level = int(tech.trim_prefix("pack_"))
			if tech == "radio": duration = minf(duration, maxf(elapsed + 180, duration - 300))
			completed_notice = tech
			research_job = {}
	for b in buildings:
		if b.hp > 0 and b.get("upgrading", false): work(b.id, dt)
	if phase == "playing":
		elapsed += dt
		if elapsed >= duration: phase = "evacuate"
	else:
		evacuation_elapsed += dt
		if evacuation_elapsed >= Catalog.EVACUATION_SECONDS: phase = "lost"

func health_damage_tick(amount: float) -> void:
	# Session cannot own the pawn, so world applies this accumulated damage.
	survival_damage += amount

func building(id: int) -> Dictionary:
	for b in buildings:
		if b.id == id and b.hp > 0: return b
	return {}

func demolition_quote(id: int) -> Dictionary:
	var b := building(id)
	if b.is_empty() or phase not in ["playing", "evacuate"]: return {}
	var spec: Dictionary = Catalog.BUILDINGS[b.kind]
	# Legacy upgraded labs paid for both the foundation and the upgrade.
	var legacy_upgrade := 5 if b.kind in ["laboratory", "workshop"] and b.get("upgrading", false) else 0
	var paid_wood: int = b.get("invested_wood", int(spec.wood) + legacy_upgrade)
	var paid_gold: int = b.get("invested_gold", int(spec.gold) + legacy_upgrade)
	var ratio := 0.5 * clampf(float(b.hp) / Catalog.max_health(b), 0.0, 1.0)
	return {"wood": floori(paid_wood * ratio), "gold": floori(paid_gold * ratio)}

func demolish(id: int) -> Dictionary:
	var quote := demolition_quote(id)
	if quote.is_empty(): return {}
	var b := building(id)
	# Dead records already round-trip through the save format; no second claim is possible.
	b.hp = 0.0
	wood += quote.wood
	gold += quote.gold
	return quote

func work(id: int, dt: float) -> bool:
	var b := building(id)
	if b.is_empty(): return false
	b.remaining = maxf(0.0, b.remaining - dt)
	return b.remaining <= 0

func research(selected_id: int = -1, destination: String = "laboratory") -> String:
	if destination not in ["laboratory", "workshop"]: return "未知升级方向"
	if phase != "playing": return "本局已结束"
	var target: Dictionary = {}
	for b in buildings:
		if b.id == selected_id and b.kind == "lab" and b.hp > 0 and b.remaining <= 0: target = b
	if target.is_empty(): return "请先选中已完成的基础建筑"
	if not has_completed("generator"): return "需要发电站"
	if supply() < demand() + 1: return "升级还需要 1 点电力"
	var cost: Dictionary = Catalog.BUILDINGS[destination]
	if wood < cost.wood or gold < cost.gold: return "升级需要 %d 木材和 %d 黄金" % [cost.wood, cost.gold]
	wood -= cost.wood
	gold -= cost.gold
	target.invested_wood = int(target.get("invested_wood", Catalog.BUILDINGS.lab.wood)) + cost.wood
	target.invested_gold = int(target.get("invested_gold", Catalog.BUILDINGS.lab.gold)) + cost.gold
	target.kind = destination
	target.hp = cost.hp
	target.remaining = cost.time
	target.upgrading = true
	return ""

func refit_error(id: int, option: String) -> String:
	var b := building(id)
	if phase != "playing": return "撤离阶段不能改造"
	if b.is_empty() or not Catalog.REFITS.has(option): return "请选择可改造的防御建筑"
	var spec: Dictionary = Catalog.REFITS[option]
	if b.kind not in spec.kinds: return "此建筑不支持该改造"
	if b.remaining > 0: return "请先完成施工"
	if not b.get("refit", "").is_empty(): return "已选定改造方向"
	if b.kind == "tower" and not technologies.has("tower_engineering"): return "需要实验室研究「箭塔工程」"
	if supply() < demand(): return "改造需要正常供电"
	if wood < spec.wood or gold < spec.gold: return "需要 %d 木材和 %d 黄金" % [spec.wood, spec.gold]
	return ""

func refit(id: int, option: String) -> String:
	var error := refit_error(id, option)
	if not error.is_empty(): return error
	var b := building(id)
	var spec: Dictionary = Catalog.REFITS[option]
	wood -= spec.wood
	gold -= spec.gold
	b.invested_wood = int(b.get("invested_wood", Catalog.BUILDINGS[b.kind].wood)) + spec.wood
	b.invested_gold = int(b.get("invested_gold", Catalog.BUILDINGS[b.kind].gold)) + spec.gold
	# Preserve existing damage; reinforcing a breached wall is not a free repair.
	var previous_maximum := Catalog.max_health(b)
	b.refit = option
	b.hp += Catalog.max_health(b) - previous_maximum
	b.remaining = spec.time
	b.upgrading = true
	return ""

func reinforce_error(id: int) -> String:
	var b := building(id)
	if phase != "playing": return "撤离阶段不能加固"
	if b.is_empty() or b.kind != "tower": return "请选择箭塔"
	if b.remaining > 0: return "请先完成施工"
	if b.get("reinforced", false): return "箭塔已加固"
	if supply() < demand(): return "加固需要正常供电"
	var spec: Dictionary = Catalog.TOWER_REINFORCEMENT
	if wood < spec.wood or gold < spec.gold: return "需要 %d 木材和 %d 黄金" % [spec.wood, spec.gold]
	return ""

func reinforce(id: int) -> String:
	var error := reinforce_error(id)
	if not error.is_empty(): return error
	var b := building(id)
	var spec: Dictionary = Catalog.TOWER_REINFORCEMENT
	wood -= spec.wood
	gold -= spec.gold
	b.invested_wood = int(b.get("invested_wood", Catalog.BUILDINGS.tower.wood)) + spec.wood
	b.invested_gold = int(b.get("invested_gold", Catalog.BUILDINGS.tower.gold)) + spec.gold
	b.reinforced = true
	b.hp += spec.hp
	b.remaining = spec.time
	b.upgrading = true
	return ""
