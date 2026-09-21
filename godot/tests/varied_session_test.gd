extends "res://tests/full_session_test.gd"

func _initialize() -> void:
	content_variation = true
	call_deferred("run")
