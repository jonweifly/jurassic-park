extends RefCounted
const Catalog = preload("res://scripts/catalog.gd")
const Dinosaurs = preload("res://scripts/dinosaur_catalog.gd")
const PRIORITIES := ["nearest", "large", "ranged"]
const LABELS := ["最近目标", "大型优先", "远程优先"]
const LARGE := ["young_trex", "trex", "alpha_trex"]
var world: Node
var focus_uid := -1
var marking := false

func _init(owner_world: Node) -> void: world = owner_world

func focused() -> Node3D:
	if focus_uid < 0: return null
	for d in world.dinosaurs:
		if d.health > 0 and d.get_meta("save_id") == focus_uid: return d
	focus_uid = -1
	return null

func mark_at(point: Vector3) -> bool:
	var target: Node3D
	var best := 2.4
	for d in world.dinosaurs:
		if d.health <= 0 or not d.visible: continue
		var distance := Vector2(d.position.x - point.x, d.position.z - point.z).length()
		if distance < best:
			best = distance
			target = d
	if target == null:
		world.hud.toast("请选择可见的恐龙；右键取消集火选择。")
		return false
	focus_uid = target.get_meta("save_id")
	marking = false
	world.hud.toast("集火：" + Dinosaurs.spec(target.get_meta("species")).name + "；射程内箭塔优先攻击。")
	return true

func choose(b: Dictionary, origin: Vector3) -> Node3D:
	var target: Node3D
	var best := INF
	var priority := Catalog.target_priority(b) if b.kind == "tower" else "nearest"
	var marked := focused() if b.kind == "tower" else null
	for d in world.dinosaurs:
		var distance := origin.distance_to(d.position)
		if d.health <= 0 or not d.visible or distance >= Catalog.attack_range(b): continue
		if d == marked: return d
		var species: String = d.get_meta("species", "raptor")
		var preferred := (priority == "large" and species in LARGE) or (priority == "ranged" and species == "spitter")
		var score := distance - (1000.0 if preferred else 0.0)
		if score < best:
			best = score
			target = d
	return target

static func hit_damage(b: Dictionary, species: String, multiplier: float) -> float:
	var damage := Catalog.attack_damage(b) * multiplier
	if b.kind != "tower": return damage
	var armor: float = Dinosaurs.spec(species).armor
	if b.get("refit", "") == "heavy":
		armor *= 0.25
		if species in LARGE: damage *= 1.35
	elif b.get("refit", "") == "range" and species == "spitter": damage *= 1.5
	return damage * (1.0 - armor)

static func apply_slow(d: Node3D) -> void:
	# Refresh duration only: multiple fences never multiply movement penalties.
	d.set_meta("ai_electric_slow", 1.2)

static func slow_factor(d: Node3D) -> float:
	if float(d.get_meta("ai_electric_slow", 0.0)) <= 0: return 1.0
	var species: String = d.get_meta("species", "raptor")
	return 0.92 if species == "alpha_trex" else (0.85 if species in LARGE else 0.65)
