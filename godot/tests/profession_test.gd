extends SceneTree

const Session = preload("res://scripts/session.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _init() -> void:
	var s := Session.new()
	check(Session.PROFESSIONS.size() == 4, "Four selectable survivor professions are defined")
	s.profession = "explorer"
	check(s.survivor_speed() > 5.0 and s.carry_capacity_bonus() == 0, "Explorer improves movement")
	s.profession = "doctor"
	check(s.survivor_max_health() == 170.0 and s.healing_amount() == 12.5, "Doctor improves health and treatment")
	s.profession = "hunter"
	s.raw_meat = 0
	s.add_hunted_food(1)
	check(s.raw_meat == 2 and s.survivor_damage() > 13.0, "Hunter improves hunting yield and damage")
	s.profession = "soldier"
	check(s.survivor_damage() > 16.0 and s.carry_capacity_bonus() == -1, "Soldier improves combat with lower carrying")
	print("PROFESSION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
