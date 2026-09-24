extends SceneTree
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func verify(size: Vector2i, label: String) -> void:
	root.size = size
	await process_frame
	var bottom_rect: Rect2 = world.hud.bottom.get_global_rect()
	expect(bottom_rect.size.x > 0 and bottom_rect.size.y > 0 and bottom_rect.position.x >= -2 and bottom_rect.position.y >= -2, label + " bottom panel has valid viewport layout")
	expect(world.hud.bottom.offset_bottom >= -8, label + " bottom panel hugs the viewport edge")
	expect(bottom_rect.size.y <= 210, label + " bottom panel remains compact")
	expect(world.hud.minimap.custom_minimum_size.x > world.hud.minimap.custom_minimum_size.y, label + " minimap uses a wider landscape ratio")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	await verify(Vector2i(1280,800), "wide")
	await verify(Vector2i(1000,800), "windowed")
	await verify(Vector2i(1000,550), "short")
	# Repeated refreshes with changing counters must not move the middle controls.
	var resource_x: float = world.hud.resource_label.get_global_position().x
	var clock_x: float = world.hud.clock_label.get_global_position().x
	world.session.wood = 999
	world.session.elapsed = 61
	world.hud.refresh(0)
	expect(is_equal_approx(world.hud.resource_label.get_global_position().x, resource_x), "resource label has stable horizontal position")
	expect(is_equal_approx(world.hud.clock_label.get_global_position().x, clock_x), "clock label has stable horizontal position")
	# Camera height correction is smoothed and must settle when the target is static.
	world.start_session(1500.0, "standard")
	world.paused = true
	world.camera_rig.center(true)
	world.update_camera(0)
	var camera_position: Vector3 = world.camera.position
	for i in range(12): world.update_camera(1.0 / 60.0)
	expect(world.camera.position.distance_to(camera_position) < 0.01, "static camera does not jitter")
	world.free()
	print("HUD LAYOUT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
