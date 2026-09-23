extends SceneTree

const Session = preload("res://scripts/session.gd")

func _init() -> void:
	preload("res://scripts/feature_policy.gd").peripheral_enabled = true
	var s := Session.new()
	s.phase = "playing"
	var before := s.hunger
	s.tick(120.0)
	_check(s.hunger < before and s.fatigue > 0.0, "时间会消耗饱腹度并增加疲劳")
	s.food = 1
	_check(s.eat_food() and s.food == 0 and s.hunger > before - 2.0, "补给可以恢复饱腹度")
	s.raw_meat = 1
	s.buildings = [{"id": 1, "kind": "fire", "cell": Vector2i(1, 1), "hp": 100.0, "remaining": 0.0, "cooldown": 0.0}]
	_check(s.cook_food() and s.cooked_meat == 1 and s.raw_meat == 0, "营火可以把生肉烤成熟肉")
	s.fatigue = 80.0
	s.rest(2.0)
	_check(s.fatigue < 80.0, "休息会降低疲劳")
	s.add_berries(20)
	_check(s.berries == 8, "采集野果使用有限库存，避免无限囤积")
	print("SURVIVAL: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

var _checks := 0
var _failures := 0

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
