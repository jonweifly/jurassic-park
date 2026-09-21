extends Control
## Presentation-only pointer, target and route feedback. Commands own the simulation.
const CURSOR_SIZE := Vector2(32, 32)
const CURSOR_HOTSPOT := Vector2(2, 2) * (32.0 / 44.0)
const LABELS = {"move": "", "wood": "右键砍树", "gold": "右键采金", "build": "右键继续施工", "repair": "右键修理", "attack": "右键攻击", "return": "右键返送资源", "gate": "右键开关电门", "inspect": "右键调查", "blocked": "无法到达", "heal": "返回帐篷治疗"}
const COLORS = {"move": Color("a8e6b2"), "wood": Color("bde3a0"), "gold": Color("f2d386"), "attack": Color("ffa594"), "blocked": Color("f5988b")}
var world: Node
var icons: Dictionary = {}
var target_icons: Dictionary = {}
var cursor_kind := "move"
var cursor_text := ""
var pointer := Vector2.ZERO
var active := false
var clock := 0.0
var pulse_left := 0.0
var pulse_position := Vector3.ZERO
var pulse_kind := "move"
var cached_key := ""
var cached_until := 0.0
var cached_reachable := true
var owns_cursor := false
var tooltip_box: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tooltip_box = StyleBoxFlat.new()
	tooltip_box.bg_color = Color(0.035, 0.075, 0.06, 0.94)
	tooltip_box.set_corner_radius_all(4)
	for kind in LABELS:
		icons[kind] = load("res://assets/cursors/%s.svg" % kind)
		if kind != "move": target_icons[kind] = load("res://assets/interaction_icons/%s.svg" % kind)

func _exit_tree() -> void:
	release_cursor()

func release_cursor() -> void:
	if owns_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		owns_cursor = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_MOUSE_EXIT:
		active = false
		release_cursor()
		queue_redraw()

func confirm(target: Dictionary, accepted: bool = true) -> void:
	pulse_position = target.position
	pulse_kind = target.kind if accepted else "blocked"
	pulse_left = 0.85

func reachable(target: Dictionary) -> bool:
	if target.kind in ["blocked", "gate", "inspect", "return"]: return target.kind != "blocked"
	var cell: Vector2i = world.board.cell_at(target.position)
	var key := "%s:%s:%s:%d" % [target.kind, cell, world.board.cell_at(world.hero.position), world.board.revision]
	if key != cached_key or clock >= cached_until:
		cached_key = key
		cached_until = clock + 0.15
		var route: PackedVector3Array = world.board.route(world.hero.position, target.position, target.kind != "move")
		cached_reachable = not route.is_empty() or world.hero.position.distance_to(target.position) <= 3
	return cached_reachable

func update_hover(screen: Vector2, point: Vector3) -> void:
	pointer = screen
	var target: Dictionary = world.context_at(point)
	cursor_kind = target.kind
	cursor_text = LABELS[cursor_kind]
	if not world.build_mode.is_empty():
		var error: String = world.placement_error(world.board.cell_at(point))
		cursor_kind = "build" if error.is_empty() else "blocked"
		cursor_text = "左键建造 · 右键取消" if error.is_empty() else error
		if error.is_empty():
			var warning: String = world.placement_warning(world.board.cell_at(point))
			if not warning.is_empty(): cursor_text = "注意：" + warning
	elif not reachable(target):
		cursor_kind = "blocked"
		cursor_text = "无法到达 · 清理道路或另选位置"

func refresh(dt: float) -> void:
	clock += dt
	if not world.paused: pulse_left = maxf(0, pulse_left - dt)
	pointer = get_viewport().get_mouse_position()
	var in_window := get_viewport_rect().has_point(pointer) and DisplayServer.window_is_focused()
	active = in_window and world.started and not world.paused and world.session.phase in ["playing", "evacuate"] and not world.hud.covers(pointer) and not world.camera_rig.dragging
	if active:
		update_hover(pointer, world.ground_at(pointer))
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		owns_cursor = true
	else: release_cursor()
	queue_redraw()

func screen_point(point: Vector3) -> Vector2:
	if world.camera.is_position_behind(point): return Vector2(-10000, -10000)
	return world.camera.unproject_position(point + Vector3.UP * 0.15)

func clear_screen(p: Vector2) -> bool:
	return get_viewport_rect().grow(-12).has_point(p) and not world.hud.covers(p)

func draw_target(point: Vector3, kind: String, alpha: float, radius: float, show_icon: bool = true) -> void:
	var p := screen_point(point)
	if not clear_screen(p): return
	var color: Color = COLORS.get(kind, Color("e4cf8e"))
	color.a = alpha
	draw_arc(p, radius, 0, TAU, 40, Color(0.03, 0.09, 0.06, alpha * 0.8), 5, true)
	draw_arc(p, radius, 0, TAU, 40, color, 2, true)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(p + direction * (radius + 4), p + direction * (radius + 9), color, 2, true)
	if show_icon and target_icons.has(kind): draw_texture_rect(target_icons[kind], Rect2(p + Vector2(-12, -36 - sin(clock * 4)), Vector2(24, 24)), false, Color(1, 1, 1, alpha))

func _draw() -> void:
	if not world.started or world.paused or world.session.phase not in ["playing", "evacuate"]: return
	var kind: String = world.order
	if kind in ["move", "wood", "gold", "build", "repair", "return", "attack", "heal", "expedition"]:
		# Route dots come from the pawn's actual current route, including replans.
		for i in range(mini(24, world.hero.route.size()) if world.preferences.values.route_dots else 0):
			var point: Vector3 = world.hero.route[i]
			if not world.vision.explored.has(world.board.cell_at(point)): continue
			var p := screen_point(point)
			if clear_screen(p):
				draw_circle(p, 3.0, Color(0.03, 0.09, 0.06, 0.65))
				draw_circle(p, 1.7, Color(0.72, 0.87, 0.63, 0.75))
		var target: Vector3 = world.order_target
		if kind == "move" and not world.hero.route.is_empty(): target = world.hero.route[-1]
		draw_target(target, "inspect" if kind == "expedition" else kind, 0.9, 12 + sin(clock * 4) * 1.5)
	if pulse_left > 0:
		draw_target(pulse_position, pulse_kind, minf(1, pulse_left * 2.0), 13 + (0.85 - pulse_left) * 22, false)
	if active and icons.has(cursor_kind):
		draw_texture_rect(icons[cursor_kind], Rect2(pointer - CURSOR_HOTSPOT, CURSOR_SIZE), false)
		if cursor_text.is_empty(): return
		var font: Font = world.hud.font
		var size := font.get_string_size(cursor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13) + Vector2(12, 8)
		var origin := pointer + Vector2(16, 29)
		origin.x = minf(origin.x, get_viewport_rect().size.x - size.x - 8)
		origin.y = minf(origin.y, get_viewport_rect().size.y - size.y - 8)
		if world.hud.covers(origin) or world.hud.covers(origin + size): origin.y = maxf(8, pointer.y - size.y - 12)
		draw_style_box(tooltip_box, Rect2(origin, size))
		draw_string(font, origin + Vector2(6, 16), cursor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLORS.get(cursor_kind, Color("e4edcf")))
