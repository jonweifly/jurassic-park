extends SceneTree

func _initialize() -> void:
	call_deferred("bake")

func bake() -> void:
	var world = load("res://scripts/world.gd").new()
	root.add_child(world)
