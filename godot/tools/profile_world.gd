extends "res://scripts/world.gd"
## Profiling-only root; retains the exact production update and accumulates boundaries.
var profile := {}
func add_time(key: String, start: int) -> void:
	profile[key] = profile.get(key, 0) + Time.get_ticks_usec() - start
func update_dinosaurs(dt: float) -> void:
	var t := Time.get_ticks_usec()
	super.update_dinosaurs(dt)
	add_time("dinosaurs_us", t)
func update_buildings(dt: float) -> void:
	var t := Time.get_ticks_usec()
	super.update_buildings(dt)
	add_time("buildings_us", t)
func update_effects(dt: float) -> void:
	var t := Time.get_ticks_usec()
	super.update_effects(dt)
	add_time("effects_us", t)
func update_lighting() -> void:
	var t := Time.get_ticks_usec()
	super.update_lighting()
	add_time("lighting_us", t)
