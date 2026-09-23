extends "res://tests/full_session_test.gd"

func _initialize() -> void:
	preload("res://scripts/feature_policy.gd").peripheral_enabled = true
	content_variation = true
	call_deferred("run")
