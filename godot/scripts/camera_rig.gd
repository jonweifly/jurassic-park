extends RefCounted
var world: Node
var focus := Vector3.ZERO
var yaw := PI / 4
var target_yaw := PI / 4
var pitch := deg_to_rad(52)
var target_pitch := deg_to_rad(52)
var following := false
var dragging := false
var initialized := false

func _init(owner_world: Node) -> void:
	world = owner_world

func center(follow: bool = false) -> void:
	following = follow
	world.camera_focus = world.hero.position

func reset() -> void:
	target_yaw = PI / 4
	target_pitch = deg_to_rad(52)
	world.camera_size = 36
	center(true)

func pan(delta: Vector2, dt: float) -> void:
	if delta.is_zero_approx(): return
	following = false
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var down := Vector3(sin(yaw), 0, cos(yaw))
	world.camera_focus += (right * delta.x + down * delta.y) * dt * world.camera_size * 0.55 * world.preferences.values.pan_speed

func handle(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		dragging = event.pressed
		return true
	if event is InputEventMouseMotion and dragging:
		if event.shift_pressed: pan(-event.relative, 0.002)
		else:
			var previous_pitch := target_pitch
			target_yaw -= event.relative.x * 0.006 * world.preferences.values.rotation_speed
			target_pitch = clampf(target_pitch + event.relative.y * 0.004 * world.preferences.values.rotation_speed * (-1 if world.preferences.values.invert_y else 1), deg_to_rad(38), deg_to_rad(70))
			if previous_pitch > deg_to_rad(44) and target_pitch <= deg_to_rad(44): center(true)
		return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var multiplier := pow(0.90 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.10, world.preferences.values.zoom_speed)
			var previous_size: float = world.camera_size
			world.camera_size = clampf(world.camera_size * multiplier, 18, 68)
			if previous_size > 24 and world.camera_size <= 24: center(true)
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		if world.preferences.matches(event, "center"): center(true); return true
		if world.preferences.matches(event, "follow"): center(not following); return true
		if world.preferences.matches(event, "reset_camera"): reset(); return true
	return false

func update(dt: float) -> void:
	if not DisplayServer.window_is_focused() or not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): dragging = false
	if not world.paused and world.started and world.session.phase in ["playing", "evacuate"] and DisplayServer.window_is_focused():
		var move := Vector2(
			float(world.preferences.held("pan_right") or Input.is_physical_key_pressed(KEY_RIGHT)) - float(world.preferences.held("pan_left") or Input.is_physical_key_pressed(KEY_LEFT)),
			float(world.preferences.held("pan_down") or Input.is_physical_key_pressed(KEY_DOWN)) - float(world.preferences.held("pan_up") or Input.is_physical_key_pressed(KEY_UP)))
		pan(move.normalized(), dt)
		var rotate := float(world.preferences.held("rotate_right")) - float(world.preferences.held("rotate_left"))
		target_yaw += rotate * dt * 1.4 * world.preferences.values.rotation_speed
	if following: world.camera_focus = world.hero.position
	world.camera_focus.x = clampf(world.camera_focus.x, -120, 120)
	world.camera_focus.z = clampf(world.camera_focus.z, -120, 120)
	world.camera_focus.y = world.board.layout.height_at(world.camera_focus.x, world.camera_focus.z)
	var blend := 1.0 - exp(-8.0 * dt)
	if not initialized or dt == 0:
		focus = world.camera_focus
		yaw = target_yaw
		pitch = target_pitch
		initialized = true
	else:
		focus = focus.lerp(world.camera_focus, blend)
		yaw = lerp_angle(yaw, target_yaw, blend)
		pitch = lerpf(pitch, target_pitch, blend)
	world.camera.size = lerpf(world.camera.size, world.camera_size, blend if dt > 0 else 1.0)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 68
	world.camera.position = focus + offset
	# Raise the boom above intervening hills at low pitch.
	for i in range(1, 9):
		var t := float(i) / 8
		var p: Vector3 = focus.lerp(world.camera.position, t)
		var floor_y: float = world.board.layout.height_at(p.x, p.z) + 3
		if p.y < floor_y: world.camera.position.y += (floor_y - p.y) / t
	world.camera.look_at(focus)
