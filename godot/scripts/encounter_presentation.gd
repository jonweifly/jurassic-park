extends Control
## Local presentation reads only revealed combat. It never alters the encounter budget.
const Dinosaurs = preload("res://scripts/dinosaur_catalog.gd")
var world: Node
var tension := 0.0
var desired_tension := 0.0
var scan_clock := 0.0
var clock := 0.0
var impact_cooldown := 0.0
var alert_cooldown := 0.0
var count := 0
var largest: Node3D
var dust: Array[Dictionary] = []
var hit_marks: Dictionary = {}
var banner: Label
var banner_rect := Rect2()
var dust_mesh: SphereMesh
var dust_material: StandardMaterial3D
var event_title: Label
var event_detail: Label
var event_clock := 0.0
var event_cooldown := 0.0
var event_color := Color("efc493")
var seen_species := {}
var previous_phase := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner = Label.new()
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_font_size_override("font_size", 16)
	banner.add_theme_color_override("font_color", Color("efc493"))
	add_child(banner)
	event_title = Label.new()
	event_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_title.add_theme_font_size_override("font_size", 26)
	event_title.add_theme_color_override("font_color", event_color)
	add_child(event_title)
	event_detail = Label.new()
	event_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_detail.add_theme_font_size_override("font_size", 14)
	event_detail.add_theme_color_override("font_color", Color("d8e1cf"))
	add_child(event_detail)
	event_title.visible = false
	event_detail.visible = false
	dust_mesh = SphereMesh.new()
	dust_mesh.radius = 0.5
	dust_mesh.height = 1.0
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 3
	dust_material = StandardMaterial3D.new()
	dust_material.albedo_color = Color("99846b")
	dust_material.roughness = 1.0
	dust_material.vertex_color_use_as_albedo = true
	dust_mesh.material = dust_material

func scan() -> void:
	count = 0
	largest = null
	var pressure := 0.0
	var best := 0.0
	for d in world.dinosaurs:
		if not is_instance_valid(d) or d.health <= 0 or not d.visible: continue
		if not world.vision.is_visible(world.board.cell_at(d.position)): continue
		if d.get_meta("ai_target_kind", "") not in ["hero", "building"]: continue
		if d.position.distance_to(world.camera_rig.focus) > 30.0: continue
		count += 1
		var species: String = d.get_meta("species", "raptor")
		if not seen_species.has(species) and world.started and world.session.phase in ["playing", "evacuate"]:
			seen_species[species] = true
			var spec := Dinosaurs.spec(species)
			show_event("首次发现 · " + spec.name, "保持距离，观察它的移动方向。", Color("e8c879") if species in ["trex", "young_trex", "alpha_trex"] else Color("b8d39b"))
		var weight := 0.6 if species == "alpha_trex" else (0.4 if species in ["trex", "young_trex"] else 0.16)
		pressure += weight
		if weight > best:
			best = weight
			largest = d
	desired_tension = clampf(pressure, 0.0, 1.0)
	if count > 0 and tension < 0.12 and alert_cooldown <= 0.0:
		world.sound.play_ui("warning")
		alert_cooldown = 25.0

func _process(dt: float) -> void:
	var active: bool = world.started and not world.presentation_paused() and world.session.phase in ["playing", "evacuate"]
	visible = active
	if not active: return
	clock += dt
	event_cooldown = maxf(0.0, event_cooldown - dt)
	event_clock = maxf(0.0, event_clock - dt)
	if previous_phase != world.session.phase:
		previous_phase = world.session.phase
		if world.session.phase == "evacuate": show_event("救援已抵达", "前往北侧 H 停机坪，撤离阶段仍会有恐龙接近。", Color("e9c778"))
		elif world.session.phase == "won": show_event("撤离成功", "幸存者已经离开这座岛。", Color("9ed5ae"))
		elif world.session.phase == "lost": show_event("营地失守", "回看防线、供电和撤离准备，再试一次。", Color("e58d78"))
	if event_clock <= 0.0:
		event_title.visible = false
		event_detail.visible = false
	impact_cooldown = maxf(0.0, impact_cooldown - dt)
	alert_cooldown = maxf(0.0, alert_cooldown - dt)
	scan_clock -= dt
	if scan_clock <= 0.0:
		scan_clock = 0.2
		scan()
	tension = lerpf(tension, desired_tension, 1.0 - exp(-dt * (3.0 if desired_tension > tension else 1.2)))
	for id in hit_marks.keys():
		hit_marks[id] -= dt
		if hit_marks[id] <= 0.0: hit_marks.erase(id)
	update_dust(dt)
	banner.visible = count > 0
	banner.text = "防线接敌  ·  %d 只恐龙" % count
	if is_instance_valid(largest) and largest.get_meta("species", "") in ["trex", "alpha_trex"]:
		banner.text = "大型恐龙逼近  ·  集火保护防线"
	layout_messages()
	queue_redraw()

func layout_messages() -> void:
	# Co-op owns the two center-top actions. Read their rendered bounds so the
	# encounter warning and temporary event titles never cover those buttons.
	var top := 18.0
	if world.coop and world.coop.ui:
		for control in [world.coop.ui.room_button, world.coop.ui.revive_button]:
			if control.is_visible_in_tree():
				top = maxf(top, control.get_global_rect().end.y - global_position.y + 8.0)
	banner_rect = Rect2(Vector2(size.x * 0.5 - 183.0, top), Vector2(366.0, 42.0))
	banner.position = Vector2(size.x * 0.5 - 170.0, top + 4.0)
	banner.size = Vector2(340.0, 32.0)
	# An inactive warning reserves no extra row; single-player positions stay unchanged.
	var event_top := top + 50.0 if count > 0 else maxf(68.0, top)
	event_title.position = Vector2(size.x * 0.5 - 300.0, event_top)
	event_title.size = Vector2(600.0, 36.0)
	event_detail.position = Vector2(size.x * 0.5 - 320.0, event_top + 36.0)
	event_detail.size = Vector2(640.0, 26.0)

func show_event(title: String, detail: String, color: Color = Color("efc493")) -> void:
	if event_cooldown > 0.0 and event_clock > 0.0: return
	event_color = color
	event_title.add_theme_color_override("font_color", color)
	event_title.text = title
	event_detail.text = detail
	event_clock = 3.8
	event_cooldown = 1.0
	event_title.visible = true
	event_detail.visible = true
	layout_messages()
	queue_redraw()

func weather_event(kind: int) -> void:
	match kind:
		1: show_event("天气转坏", "大风会压低环境声，先确认电力和围栏状态。", Color("d3c38d"))
		2: show_event("阵雨开始", "地面变湿，树冠和营地灯光会更明显。", Color("9ec9d2"))
		3: show_event("雷雨来临", "短暂闪电后会有雷声，留在防线附近更安全。", Color("b7c6e4"))
		_: show_event("天气放晴", "雨水正在退去，岛屿能见度逐步恢复。", Color("d5d19c"))

func building_hit(b: Dictionary, amount: float) -> void:
	var at: Vector3 = world.board.point(b.cell)
	if not world.vision.is_visible(b.cell): return
	hit_marks[b.id] = 0.5
	impact(at, amount >= 32.0)

func impact(at: Vector3, heavy: bool = true) -> void:
	if world.presentation_paused() or not world.vision.is_visible(world.board.cell_at(at)): return
	if at.distance_to(world.camera_rig.focus) > 30.0 or impact_cooldown > 0.0: return
	impact_cooldown = 0.18
	if heavy: world.camera_rig.impact(at, 0.14)
	if world.preferences.values.quality == 0 or dust.size() >= 6: return
	var node := MultiMeshInstance3D.new()
	node.name = "ImpactDebris"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = dust_mesh
	mm.instance_count = 10 if heavy else 5
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(node)
	node.position = at
	world.vision.shade(node)
	dust.append({"node": node, "age": 0.0, "strength": 1.0 if heavy else 0.5})
	update_dust(0.0)

func update_dust(dt: float) -> void:
	for fx in dust.duplicate():
		fx.age += dt
		if fx.age >= 0.6:
			fx.node.queue_free()
			dust.erase(fx)
			continue
		var node: MultiMeshInstance3D = fx.node
		node.visible = world.vision.is_visible(world.board.cell_at(node.position))
		for i in range(node.multimesh.instance_count):
			var angle := TAU * float(i) / node.multimesh.instance_count + 0.4
			var travel: float = (0.12 + fx.age * 2.8) * fx.strength
			var p := Vector3(cos(angle) * travel, 0.0, sin(angle) * travel)
			p.y = world.board.layout.height_at(node.position.x + p.x, node.position.z + p.z) - node.position.y + 0.1 + sin(fx.age / 0.6 * PI) * 0.38
			var radius: float = (0.11 + float(i % 3) * 0.04) * (1.0 - fx.age / 0.6)
			node.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), p))
			node.multimesh.set_instance_color(i, Color.WHITE.lerp(Color("6b5641"), float(i % 3) * 0.15))

func _draw() -> void:
	if not visible: return
	if event_clock > 0.0:
		var fade := minf(1.0, event_clock / 0.55) * minf(1.0, (3.8 - event_clock) / 0.35 + 0.75)
		draw_rect(Rect2(0, 0, size.x, 4), Color(event_color, 0.55 * fade))
		draw_rect(Rect2(0, size.y - 4, size.x, 4), Color(event_color, 0.28 * fade))
	if count > 0:
		draw_rect(banner_rect, Color(0.12, 0.08, 0.045, 0.86))
		draw_line(banner_rect.position, banner_rect.position + Vector2(banner_rect.size.x, 0), Color(0.86, 0.47, 0.21, 0.6 + 0.2 * sin(clock * 3.0)), 2.0)
	for id in hit_marks:
		var b: Dictionary = world.session.building(id)
		if b.is_empty() or not world.vision.is_visible(b.cell): continue
		var p: Vector3 = world.board.point(b.cell) + Vector3.UP * 0.9
		if world.camera.is_position_behind(p): continue
		var screen: Vector2 = world.camera.unproject_position(p)
		if world.hud.covers(screen): continue
		draw_arc(screen, 16.0 + (0.5 - hit_marks[id]) * 24.0, 0, TAU, 32, Color(0.95, 0.65, 0.3, hit_marks[id]), 1.5, true)

func _exit_tree() -> void:
	for fx in dust:
		if is_instance_valid(fx.node): fx.node.queue_free()
