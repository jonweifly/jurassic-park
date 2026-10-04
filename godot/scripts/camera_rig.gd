extends RefCounted
## Lower, wider-lens tactical camera: nearby geometry gets visible depth while
## the ground focus remains unchanged for picking and navigation.
const DEFAULT_YAW := PI / 4.0
const DEFAULT_PITCH := deg_to_rad(44.0)
const MIN_PITCH := deg_to_rad(30.0)
const MAX_PITCH := deg_to_rad(72.0)
const LOOK_HEIGHT := 0.72
var world: Node
var focus := Vector3.ZERO
var yaw := DEFAULT_YAW
var target_yaw := DEFAULT_YAW
var pitch := DEFAULT_PITCH
var target_pitch := DEFAULT_PITCH
var following := false
var dragging := false
var initialized := false
var boom_height := 0.0
var impact_strength := 0.0
var impact_clock := 0.0

func impact(at: Vector3, strength: float) -> void:
	if world.presentation_paused() or not world.preferences.values.get("impact_motion", true): return
	if not world.vision.is_visible(world.board.cell_at(at)): return
	var attenuation := clampf(1.0 - at.distance_to(focus) / 28.0, 0.0, 1.0)
	impact_strength = maxf(impact_strength, minf(strength, 0.16) * attenuation)
	impact_clock = 0.0

func _init(owner_world: Node) -> void:
	world = owner_world

func center(follow: bool = false) -> void:
	following = follow
	world.camera_focus = world.hero.position

func reset() -> void:
	target_yaw = DEFAULT_YAW
	target_pitch = DEFAULT_PITCH
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
			target_pitch = clampf(target_pitch + event.relative.y * 0.004 * world.preferences.values.rotation_speed * (-1 if world.preferences.values.invert_y else 1), MIN_PITCH, MAX_PITCH)
			if previous_pitch > deg_to_rad(44) and target_pitch <= deg_to_rad(44): center(true)
		return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var multiplier := pow(0.90 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.10, world.preferences.values.zoom_speed)
			world.camera_size = clampf(world.camera_size * multiplier, 18, 68)
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
	var perspective: bool = world.preferences.values.get("perspective", true)
	world.camera.projection = Camera3D.PROJECTION_PERSPECTIVE if perspective else Camera3D.PROJECTION_ORTHOGONAL
	# A narrow lens gives useful depth while retaining the familiar RTS footprint.
	# camera.size still represents the visible span at the focus, including old saves.
	var distance: float = world.camera.size / (2.0 * tan(deg_to_rad(world.camera.fov) * 0.5)) if perspective else 68.0
	var look_target := focus + Vector3.UP * LOOK_HEIGHT
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var desired_position := look_target + offset
	# Raise the boom above intervening hills at low pitch.
	var required_lift := 0.0
	for i in range(1, 9):
		var t := float(i) / 8
		var p: Vector3 = focus.lerp(desired_position, t)
		var floor_y: float = world.board.layout.height_at(p.x, p.z) + 3
		if p.y < floor_y: required_lift = maxf(required_lift, (floor_y - p.y) / t)
	if not initialized or dt == 0:
		boom_height = required_lift
	else:
		# Zoom already smooths its distance. Filtering absolute Y again makes it
		# lag X/Z and rocks the lens; smooth only additional terrain clearance.
		boom_height = lerpf(boom_height, required_lift, 1.0 - exp(-10.0 * dt))
	# Clear a close hillside along the camera boom instead of lifting only Y.
	# Moving on the existing view ray keeps the pitch stable while zooming, so
	# terrain protection does not make the lens visibly rock.
	if boom_height > 0.0:
		desired_position += offset.normalized() * (boom_height / maxf(sin(pitch), 0.25))
	world.camera.position = desired_position
	world.camera.look_at(look_target)
	if not world.preferences.values.get("impact_motion", true): impact_strength = 0.0
	if not world.presentation_paused() and dt > 0:
		impact_clock += dt
		impact_strength *= exp(-12.0 * dt)
		# Short translation only: never retarget, change zoom or interrupt commands.
		world.camera.position += world.camera.global_basis.x * sin(impact_clock * 61.0) * impact_strength
		world.camera.position += world.camera.global_basis.y * sin(impact_clock * 47.0) * impact_strength * 0.6
