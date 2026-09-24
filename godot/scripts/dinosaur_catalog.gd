extends RefCounted
## Species identity, combat and presentation share one registry. Legacy stats are unchanged.
const SPECIES := {
	"small_raptor": {"name": "幼年迅猛龙", "model": "small_raptor", "hp": 65.0, "speed": 5.0, "scale": 0.72, "damage": 6.0, "interval": 1.5, "radius": 0.32, "audio": "small_raptor", "role": "pack", "armor": 0.0},
	"raptor": {"name": "迅猛龙", "model": "raptor", "hp": 100.0, "speed": 350.0 / 64.0, "scale": 1.0, "damage": 12.0, "interval": 1.0, "radius": 0.48, "audio": "raptor", "role": "pack", "armor": 0.0},
	"young_trex": {"name": "幼年霸王龙", "model": "young_trex", "hp": 350.0, "speed": 215.0 / 64.0, "scale": 1.2, "damage": 15.0, "interval": 1.2, "radius": 0.82, "audio": "young_trex", "role": "bruiser", "armor": 0.0},
	"trex": {"name": "霸王龙", "model": "trex", "hp": 1000.0, "speed": 280.0 / 64.0, "scale": 1.5, "damage": 20.0, "interval": 1.4, "radius": 1.12, "audio": "trex", "role": "breaker", "armor": 0.0},
	"spitter": {"name": "棘冠喷毒龙", "model": "spitter", "hp": 260.0, "speed": 4.0, "scale": 1.0, "damage": 22.0, "interval": 3.5, "radius": 0.55, "audio": "raptor", "role": "artillery", "armor": 0.0},
	"elite_raptor": {"name": "镰爪精英", "model": "elite_raptor", "hp": 550.0, "speed": 5.8, "scale": 1.2, "damage": 26.0, "interval": 1.15, "radius": 0.63, "audio": "raptor", "role": "elite", "armor": 0.12},
	"alpha_trex": {"name": "棘背暴君 · 首领", "model": "alpha_trex", "hp": 2400.0, "speed": 3.6, "scale": 1.8, "damage": 38.0, "interval": 2.4, "radius": 1.28, "audio": "trex", "role": "boss", "armor": 0.24},
}
static func spec(species: String) -> Dictionary:
	return SPECIES.get(species, SPECIES.raptor)

static func received_damage(species: String, damage: float, source: String) -> float:
	# Armor answers concentrated arrows, while electric fences remain a useful counter.
	return damage * (1.0 - float(spec(species).armor)) if source == "tower" else damage
