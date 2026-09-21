extends RefCounted
## Versioned data-only saves. Never deserialize objects or write into the project.
const VERSION := 3
const ExpeditionCatalog = preload("res://scripts/expedition_catalog.gd")
const MAP_ID := "reference-island-65065-v1"
const SESSION_FIELDS = ["wood", "gold", "elapsed", "phase", "buildings", "next_id", "harvest_level", "duration", "evacuation_elapsed", "kills", "mode", "technologies", "research_job", "completed_notice", "rescue_warned", "finale_wave", "next_dinosaur_id", "healing_spent", "boarding_progress", "adventure", "profession"]
const SURVIVAL_FIELDS = ["hunger", "fatigue", "food", "raw_meat", "cooked_meat", "berries", "survival_clock"]
const WORKER_FIELDS = ["cargo_kind", "cargo", "resource_kind", "resource_target", "target_id", "clock", "retry_clock", "delivered", "noise_clock", "recovery", "pose_clock"]
const PAWN_FIELDS = ["position", "rotation", "health", "max_health", "route", "attack_cooldown", "path_cooldown", "swing", "dying", "death_clock", "current_speed", "travelled", "age", "carrying", "cargo_kind", "work_state", "work_timeout"]
const CAMERA_FIELDS = ["focus", "yaw", "target_yaw", "pitch", "target_pitch", "following"]
static var directory := "user://saves"
static var pending: Dictionary = {}
static var pending_message := ""

static func fields(object: Object, names: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in names: result[key] = object.get(key)
	return result.duplicate(true)

static func restore_fields(object: Object, values: Dictionary, names: Array) -> void:
	var copied := values.duplicate(true)
	for key in names: object.set(key, copied[key])

static func visual_state(pawn: Node) -> Dictionary:
	return {"rotation": pawn.visual.model.rotation, "state": pawn.visual.state, "time": pawn.visual.player.current_animation_position if not pawn.visual.player.current_animation.is_empty() else 0.0}

static func restore_visual(pawn: Node, data: Dictionary) -> void:
	pawn.visual.model.rotation = data.rotation
	var state: String = data.state if not data.state.is_empty() else "idle"
	pawn.visual.state = state
	pawn.visual.player.play(pawn.visual.clips.get(state, state), 0.0)
	pawn.visual.player.seek(data.time, true)
	pawn.visual.show_equipment(state, pawn.carrying, pawn.cargo_kind)

static func valid_visual(data: Variant) -> bool:
	return data is Dictionary and data.get("rotation") is Vector3 and data.get("state") in ["", "idle", "walk", "carry", "carry_idle", "attack", "death", "chop", "mine", "build"] and data.get("time") is float

static func snapshot(w: Node) -> Dictionary:
	var stocks: Dictionary = {}
	for cell in w.trees: stocks[cell] = w.trees[cell].wood
	var animals: Array[Dictionary] = []
	var target_uid := -1
	for d in w.dinosaurs:
		var metadata: Dictionary = {}
		for key in d.get_meta_list():
			if String(key).begins_with("ai_") or key in [&"species", &"base_speed", &"base_interval", &"save_id"]: metadata[key] = d.get_meta(key)
		animals.append({"pawn": fields(d, PAWN_FIELDS), "meta": metadata, "visual": visual_state(d)})
		if d.get_instance_id() == w.hero.target_id: target_uid = d.get_meta("save_id")
	return {
		"version": VERSION, "map": MAP_ID, "saved_at": int(Time.get_unix_time_from_system() * 1000000),
		"session": fields(w.session, SESSION_FIELDS), "survival": fields(w.session, SURVIVAL_FIELDS), "worker": fields(w.worker, WORKER_FIELDS),
		"hero": fields(w.hero, PAWN_FIELDS), "hero_visual": visual_state(w.hero), "animals": animals, "trees": stocks,
		"explored": w.vision.explored.duplicate(), "rng_seed": w.rng.seed, "rng_state": w.rng.state,
		"spawn_clocks": w.spawn_clocks.duplicate(true), "order": w.order, "order_target": w.order_target,
		"target_uid": target_uid, "selected_id": w.selected_id,
		"noises": w.dino_ai.noises.duplicate(true), "next_noise_id": w.dino_ai.next_noise_id,
		"generator_clock": w.dino_ai.generator_clock, "night": w.night,
		"camera": fields(w.camera_rig, CAMERA_FIELDS), "camera_focus": w.camera_focus, "camera_size": w.camera_size,
		"scenery_clock": w.scenery.clock,
	}

static func matches(data: Dictionary, object: Object, names: Array) -> bool:
	for key in names:
		if not data.has(key) or typeof(data[key]) != typeof(object.get(key)): return false
	return true

static func safe_data(value: Variant, depth: int = 0) -> bool:
	if depth > 12: return false
	if value is Object: return false
	if value is float: return is_finite(value)
	if value is Vector3: return value.is_finite()
	if value is Dictionary:
		for key in value:
			if not safe_data(key, depth + 1) or not safe_data(value[key], depth + 1): return false
	if value is Array or value is PackedVector3Array:
		for item in value:
			if not safe_data(item, depth + 1): return false
	return true

static func validate(data: Dictionary) -> String:
	if data.get("version") != VERSION: return "存档版本不兼容"
	if data.get("map") != MAP_ID: return "存档地图版本不兼容"
	if not safe_data(data): return "存档含无效数据"
	var shape := {"saved_at": TYPE_INT, "session": TYPE_DICTIONARY, "worker": TYPE_DICTIONARY, "hero": TYPE_DICTIONARY, "hero_visual": TYPE_DICTIONARY, "animals": TYPE_ARRAY, "trees": TYPE_DICTIONARY, "explored": TYPE_DICTIONARY, "rng_seed": TYPE_INT, "rng_state": TYPE_INT, "spawn_clocks": TYPE_ARRAY, "order": TYPE_STRING, "order_target": TYPE_VECTOR3, "target_uid": TYPE_INT, "selected_id": TYPE_INT, "noises": TYPE_ARRAY, "next_noise_id": TYPE_INT, "generator_clock": TYPE_FLOAT, "night": TYPE_BOOL, "camera": TYPE_DICTIONARY, "camera_focus": TYPE_VECTOR3, "camera_size": TYPE_FLOAT, "scenery_clock": TYPE_FLOAT}
	for key in shape:
		if not data.has(key) or typeof(data[key]) != shape[key]: return "存档字段不完整：" + key
	var session = load("res://scripts/session.gd").new()
	var worker = load("res://scripts/worker.gd").new(null)
	var pawn = load("res://scripts/pawn.gd").new()
	var camera = load("res://scripts/camera_rig.gd").new(null)
	var valid := valid_visual(data.hero_visual) and matches(data.session, session, SESSION_FIELDS) and matches(data.worker, worker, WORKER_FIELDS) and matches(data.hero, pawn, PAWN_FIELDS) and matches(data.camera, camera, CAMERA_FIELDS)
	if data.has("survival"):
		if not data.survival is Dictionary: valid = false
		else:
			for key in SURVIVAL_FIELDS:
				if not data.survival.has(key): valid = false
	for animal in data.animals:
		if not animal is Dictionary or not animal.get("pawn") is Dictionary or not animal.get("meta") is Dictionary:
			valid = false
			break
		if not matches(animal.pawn, pawn, PAWN_FIELDS) or not valid_visual(animal.get("visual")): valid = false
		if animal.meta.get("species", "") not in ["raptor", "small_raptor", "trex", "young_trex"]: valid = false
		for key in ["save_id", "ai_target_id", "ai_last_noise"]:
			if not animal.meta.get(key) is int: valid = false
		for key in ["ai_home", "ai_last_known"]:
			if not animal.meta.get(key) is Vector3: valid = false
		for key in ["ai_state", "ai_target_kind", "ai_species"]:
			if not animal.meta.get(key) is String: valid = false
		for key in ["base_speed", "base_interval", "ai_awareness", "ai_wander_clock", "ai_sense_clock", "ai_retaliation"]:
			if not animal.meta.get(key) is float: valid = false
		if animal.meta.has("ai_strike"):
			var strike: Variant = animal.meta.ai_strike
			if not strike is Dictionary: valid = false
			elif not strike.is_empty():
				if not strike.get("remaining") is float or strike.get("kind") not in ["hero", "building"] or not strike.get("id") is int: valid = false
		if animal.meta.get("ai_state") == "patrol" and (not animal.meta.get("ai_patrol_destination") is Vector3 or not animal.meta.get("ai_patrol_seconds") is float): valid = false
	pawn.free()
	if not valid: return "存档实体字段不完整"
	var s: Dictionary = data.session
	if s.phase not in ["playing", "evacuate"] or s.mode not in ["classic", "standard"] or s.wood < 0 or s.gold < 0 or s.duration <= 0 or s.elapsed < 0 or s.harvest_level not in range(4): return "存档单局状态无效"
	if data.hero.health <= 0 or data.hero.max_health <= 0 or data.animals.size() > 128: return "存档角色状态无效"
	if not ExpeditionCatalog.validate(s.adventure): return "探索存档状态无效"
	if data.order not in ["expedition", "idle", "move", "wood", "gold", "build", "repair", "return", "waiting_dropoff", "attack", "heal"]: return "存档命令无效"
	var catalog = load("res://scripts/catalog.gd")
	var ids: Dictionary = {}
	for b in s.buildings:
		if not b is Dictionary: return "存档建筑无效"
		for key in ["id", "kind", "cell", "hp", "remaining", "cooldown"]:
			if not b.has(key): return "存档建筑字段缺失"
		if not b.id is int or not b.cell is Vector2i or not catalog.BUILDINGS.has(b.kind) or not (b.hp is float or b.hp is int) or not (b.remaining is float or b.remaining is int) or not (b.cooldown is float or b.cooldown is int): return "存档建筑类型无效"
		if b.id <= 0 or b.id >= s.next_id or ids.has(b.id) or not Rect2i(0, 0, 128, 128).has_point(b.cell): return "存档建筑编号或位置无效"
		ids[b.id] = true
		for resource in ["wood", "gold"]:
			var key: String = "invested_" + resource
			if b.has(key):
				var maximum: int = catalog.BUILDINGS[b.kind][resource] + (5 if b.kind == "laboratory" else 0)
				if not b[key] is int or b[key] < 0 or b[key] > maximum: return "存档建筑投入无效"
	for tech in s.technologies:
		if not catalog.TECH.has(tech): return "存档科技无效"
	if not s.research_job.is_empty():
		if not catalog.TECH.has(s.research_job.get("tech", "")) or not s.research_job.get("remaining") is float: return "存档研究任务无效"
	for cell in data.trees:
		if not cell is Vector2i or not data.trees[cell] is int or data.trees[cell] <= 0 or not Rect2i(0, 0, 128, 128).has_point(cell): return "存档树林无效"
	for cell in data.explored:
		if not cell is Vector2i or not Rect2i(0, 0, 128, 128).has_point(cell): return "存档迷雾无效"
	for clock in data.spawn_clocks:
		if not clock is Dictionary or not clock.get("period") is float or not clock.get("next") is float or not clock.get("species") is Array: return "存档刷新计时无效"
		if clock.period <= 0: return "存档刷新间隔无效"
		for species in clock.species:
			if species not in ["raptor", "small_raptor", "trex", "young_trex"]: return "存档恐龙种类无效"
	for event in data.noises:
		if not event is Dictionary: return "存档声源无效"
		for key in ["id", "position", "radius", "source_kind", "source_id", "remaining"]:
			if not event.has(key): return "存档声源字段缺失"
	return ""

static func digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()

static func migrate(data: Dictionary) -> Dictionary:
	# Preserve old event timelines and exact rewards; never redraw a loaded session.
	if data.get("version") not in [1, 2] or not data.get("session") is Dictionary: return data
	data = data.duplicate(true)
	if data.version == 1: data.session["adventure"] = {}
	if not data.session.has("profession"): data.session["profession"] = "explorer"
	var adventure: Variant = data.session.get("adventure")
	if adventure is Dictionary and not adventure.is_empty(): adventure["run"] = {}
	data.version = VERSION
	return data

static func read_slot(slot: String) -> Dictionary:
	var path := directory.path_join(slot + ".jps")
	if not FileAccess.file_exists(path): return {"error": "没有可用存档"}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return {"error": "无法读取存档"}
	if file.get_length() < 69 or file.get_length() > 4194304: return {"error": "存档文件长度异常"}
	if file.get_buffer(4).get_string_from_ascii() != "JP05": return {"error": "存档格式无法识别"}
	var hash_value := file.get_buffer(64).get_string_from_ascii()
	var bytes := file.get_buffer(file.get_length() - 68)
	if digest(bytes) != hash_value: return {"error": "存档校验失败，文件可能损坏"}
	var data: Variant = bytes_to_var(bytes)
	if not data is Dictionary: return {"error": "存档数据无效"}
	data = migrate(data)
	var error := validate(data)
	return {"data": data, "slot": slot} if error.is_empty() else {"error": error}

static func latest() -> Dictionary:
	var best: Dictionary = {}
	var damaged := false
	for slot in ["manual", "auto0", "auto1", "auto2", "manual_backup"]:
		var result := read_slot(slot)
		if result.has("error"):
			if FileAccess.file_exists(directory.path_join(slot + ".jps")): damaged = true
			continue
		if best.is_empty() or result.data.saved_at > best.data.saved_at: best = result
	if best.is_empty(): return {"error": "没有可读取的存档"}
	best["recovered"] = damaged
	return best

static func write(w: Node, automatic: bool = false) -> String:
	if not w.started or w.session.phase not in ["playing", "evacuate"] or w.hero.health <= 0: return "仅可保存进行中的生存局"
	var data := snapshot(w)
	var error := validate(data)
	if not error.is_empty(): return error
	var slot := "manual"
	if automatic:
		var oldest := 9223372036854775807
		for candidate in ["auto0", "auto1", "auto2"]:
			var result := read_slot(candidate)
			if result.has("error"):
				slot = candidate
				break
			if result.data.saved_at < oldest:
				oldest = result.data.saved_at
				slot = candidate
	var folder := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return "无法创建存档目录"
	var path := folder.path_join(slot + ".jps")
	var bytes := var_to_bytes(data)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file: return "无法写入存档；请检查磁盘空间和权限"
	file.store_buffer("JP05".to_ascii_buffer())
	file.store_buffer(digest(bytes).to_ascii_buffer())
	file.store_buffer(bytes)
	file.flush()
	var written := file.get_error()
	file.close()
	if written != OK: return "存档写入失败，原存档已保留"
	if slot == "manual" and not read_slot("manual").has("error"):
		if DirAccess.copy_absolute(path, folder.path_join("manual_backup.jps")) != OK: return "无法备份原存档，本次保存已取消"
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: return "存档替换失败，原存档已保留"
	return ""

static func apply(w: Node, data: Dictionary) -> void:
	# Only call on a freshly instantiated island, after validate().
	restore_fields(w.session, data.session, SESSION_FIELDS)
	var survival: Dictionary = data.get("survival", {})
	for key in SURVIVAL_FIELDS:
		if survival.has(key): w.session.set(key, survival[key])
	for cell in w.trees.keys():
		if not data.trees.has(cell): w.clear_tree(cell)
		else: w.trees[cell].wood = data.trees[cell]
	for b in w.session.buildings:
		if b.hp <= 0: continue
		if not b.get("open", false): w.board.block_building(b.cell, b.id)
		w.create_building_visual(b)
		if b.kind == "gate": w.visuals[b.id].get_node("Model/Leaf").rotation.y = -PI * 0.48 if b.get("open", false) else 0.0
	restore_fields(w.hero, data.hero, PAWN_FIELDS)
	restore_fields(w.worker, data.worker, WORKER_FIELDS)
	w.hero.target_id = -1
	for animal in data.animals:
		# A saved corpse can occupy a blocked cell; instantiate at the open hero cell then restore.
		var d: Node3D = w.spawn_dinosaur(w.hero.position, animal.meta.species)
		if not d: continue
		restore_fields(d, animal.pawn, PAWN_FIELDS)
		for key in animal.meta: d.set_meta(key, animal.meta[key])
		d.last_board_revision = w.board.revision
		restore_visual(d, animal.visual)
		if d.get_meta("save_id") == data.target_uid: w.hero.target_id = d.get_instance_id()
	w.session.next_dinosaur_id = data.session.next_dinosaur_id
	w.adventure.restore()
	for d in w.dinosaurs:
		d.last_board_revision = w.board.revision
		var strike: Dictionary = d.get_meta("ai_strike", {})
		if strike.get("heavy", false): w.dino_ai.tactics.telegraph(d, strike.remaining)
	w.hero_route_revision = w.board.revision
	w.order = data.order
	w.order_target = data.order_target
	w.selected_id = data.selected_id
	w.spawn_clocks.assign(data.spawn_clocks)
	w.dino_ai.noises.assign(data.noises)
	w.dino_ai.next_noise_id = data.next_noise_id
	w.dino_ai.generator_clock = data.generator_clock
	w.vision.explored = data.explored.duplicate()
	w.night = data.night
	w.scenery.clock = data.scenery_clock
	restore_fields(w.camera_rig, data.camera, CAMERA_FIELDS)
	w.camera_focus = data.camera_focus
	w.camera_size = data.camera_size
	w.rng.seed = data.rng_seed
	w.rng.state = data.rng_state
	w.started = true
	w.paused = true
	w.vision.update()
	w.adventure.refresh_visibility()
	w.update_camera(0)
	w.hero.advance(0)
	restore_visual(w.hero, data.hero_visual)
	w.update_lighting()
	w.destination.position = w.order_target + Vector3(0, 0.12, 0)
	w.destination.visible = w.order == "move"
