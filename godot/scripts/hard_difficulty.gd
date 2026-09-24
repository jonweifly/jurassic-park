extends RefCounted
## Hard-only encounter budget derived from the same output/mitigation rules as defenses.
const Catalog = preload("res://scripts/catalog.gd")
const Dinosaurs = preload("res://scripts/dinosaur_catalog.gd")
const Regions = preload("res://scripts/regions.gd")
const LIVING_LIMIT := 56
const EVACUATION_RESERVE := 6
const MAX_PRESSURE_STEP := 0.10
const MIN_INTERVAL := 36.0
const MAX_INTERVAL := 100.0
const MAX_WAVE_SIZE := 16
const MAX_HEALTH_MULTIPLIER := 3.2
const MAX_DAMAGE_MULTIPLIER := 1.9

static func camp_metrics(session: RefCounted) -> Dictionary:
	var result := {"dps": 0.0, "durability": 0.0, "buildings": 0, "towers": 0, "tech": 0.0}
	var powered: bool = session.supply() >= session.demand()
	for b in session.buildings:
		if b.hp <= 0 or b.remaining > 0: continue
		result.buildings += 1
		if b.kind not in ["tower", "shelter", "gate"]: continue
		var cell: Vector2i = b.get("cell", Vector2i(64, 64))
		var mountain: bool = Regions.at(Vector3((cell.x - 64) * 2 + 1, 0, (cell.y - 64) * 2 + 1)) == "mountain"
		var reduction := (1.18 if mountain else 1.0) / (0.8 if session.technologies.has("defense") else 1.0)
		result.durability += minf(b.hp, Catalog.max_health(b)) * reduction
		if b.kind == "tower": result.towers += 1
		if not powered or (b.kind == "gate" and b.get("open", false)): continue
		var damage: float = session.defense_multiplier() * Catalog.attack_damage(b) * (1.5 if mountain else 1.0)
		# Melee electricity has lower simultaneous coverage than a ranged tower.
		result.dps += damage / Catalog.attack_interval(b) * (1.0 if b.kind == "tower" else 0.35)
	for tech in session.technologies:
		if session.technologies[tech]: result.tech += 1.0
	return result

static func camp_strength(session: RefCounted) -> float:
	var m := camp_metrics(session)
	# Output remains responsive well beyond the old handful-of-towers plateau.
	return clampf(0.55 * minf(float(m.dps) / 500.0, 1.0) + 0.25 * minf(float(m.durability) / 6500.0, 1.0)
		+ 0.10 * minf(float(m.buildings) / 40.0, 1.0) + 0.10 * minf(float(m.tech) / 7.0, 1.0), 0.0, 1.0)

static func target_pressure(session: RefCounted) -> float:
	var time: float = session.game_time()
	return clampf(0.50 * smoothstep(100.0, 1500.0, time)
		+ 0.50 * smoothstep(120.0, 600.0, time) * camp_strength(session), 0.0, 1.0)

static func profile(pressure: float) -> Dictionary:
	var p := clampf(pressure, 0.0, 1.0)
	return {"pressure": p, "count": 2 + floori((MAX_WAVE_SIZE - 2) * p), "interval": lerpf(MAX_INTERVAL, MIN_INTERVAL, p),
		"health": lerpf(1.0, MAX_HEALTH_MULTIPLIER, p), "damage": lerpf(1.0, MAX_DAMAGE_MULTIPLIER, p)}

static func group(time: float, pressure: float, wave: int = 0) -> Array:
	var count: int = profile(pressure).count
	var result: Array = []
	if time >= 1080.0 and pressure >= 0.55 and wave % 4 == 0:
		result.append("alpha_trex")
	if time >= 720.0: result.append("trex")
	if time >= 360.0 and result.size() < count - 1: result.append("young_trex")
	if pressure >= 0.85 and time >= 1200.0: result.append("trex")
	if time >= 480.0 and count >= 5: result.append("elite_raptor")
	if time >= 420.0 and count >= 4: result.append("spitter")
	while result.size() < count:
		var i := result.size()
		if time >= 900.0 and i % 5 == 0: result.append("spitter" if wave % 2 == 0 else "elite_raptor")
		else: result.append("raptor" if time >= 180.0 and i % 2 == 0 else "small_raptor")
	return result

static func health_target(session: RefCounted, species: Array, pressure: float) -> float:
	var base_health := 0.0
	for kind in species: base_health += Dinosaurs.spec(kind).hp
	var m := camp_metrics(session)
	# Aim for a sustained 22–32s exchange against covered defenses, with a ceiling.
	# This is a budget, not invulnerability: path layout, electric counterplay and
	# concentrated fire still reward good construction. Opening waves stay unscaled.
	var readiness := smoothstep(180.0, 900.0, session.game_time())
	var output_budget: float = minf(m.dps, 800.0) * lerpf(22.0, 32.0, pressure) * readiness
	return clampf(maxf(profile(pressure).health, output_budget / maxf(base_health, 1.0)), 1.0, MAX_HEALTH_MULTIPLIER)

static func strengthen(d: Node3D, pressure: float, health_multiplier: float = -1.0) -> void:
	if not is_instance_valid(d): return
	var tuning := profile(pressure)
	var hp: float = tuning.health if health_multiplier < 0 else clampf(health_multiplier, 1.0, MAX_HEALTH_MULTIPLIER)
	d.max_health *= hp
	d.health *= hp
	d.attack_damage *= tuning.damage
	d.set_meta("ai_hard_damage_multiplier", float(tuning.damage))
