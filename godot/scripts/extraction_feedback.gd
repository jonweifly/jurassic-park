extends RefCounted
## Cosmetic landing-zone feedback derived only from saved session state.
const Catalog = preload("res://scripts/catalog.gd")
const SEGMENTS := 64
var world: Node
var arc: MeshInstance3D
var geometry := ImmediateMesh.new()
var caption: Label3D
var last_segments := -1
var boundary_radii: Array[float] = []

func _init(owner: Node) -> void:
	world = owner
	make_landing_mark()
	# Match the existing 3-D distance rule even where the landing zone slopes.
	for i in range(SEGMENTS + 1):
		var angle := float(i) / SEGMENTS * TAU - PI / 2
		var low := 0.0
		var high: float = Catalog.EXTRACTION_RADIUS
		for step in range(12):
			var radius := (low + high) * 0.5
			var p: Vector3 = world.extraction + Vector3(cos(angle), 0, sin(angle)) * radius
			p.y = world.board.layout.height_at(p.x,p.z)
			if p.distance_to(world.extraction) < Catalog.EXTRACTION_RADIUS: low = radius
			else: high = radius
		boundary_radii.append(low)
	var outline := ImmediateMesh.new()
	fill_arc(outline, SEGMENTS, 0.985, 1.0)
	world.extraction_marker.mesh = outline
	world.extraction_marker.position = Vector3.ZERO
	world.extraction_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.extraction_marker.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	world.extraction_marker.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc = MeshInstance3D.new()
	arc.name = "BoardingProgress"
	arc.mesh = geometry
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("91cda9")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc.material_override = material
	world.add_child(arc)
	caption = Label3D.new()
	caption.name = "BoardingCaption"
	caption.font_size = 30
	caption.pixel_size = 0.012
	caption.modulate = Color("d4e2c2")
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.no_depth_test = true
	caption.position = world.extraction + Vector3.UP * 2.8
	world.add_child(caption)
	arc.hide()
	caption.hide()

func available() -> bool:
	var s = world.session
	return world.started and (s.phase == "evacuate" or (s.phase == "playing" and s.duration - s.elapsed <= 120))

func inside() -> bool:
	return world.hero.health > 0 and world.hero.position.distance_to(world.extraction) < Catalog.EXTRACTION_RADIUS

func status() -> String:
	var s = world.session
	if s.phase != "evacuate": return "救援即将抵达 · 可提前查看路线"
	if world.coop.active and inside() and not world.coop.all_inside(): return "等待存活队友进入 H 圈，共同撤离"
	if s.mode == "classic": return "进入 H 圈即可撤离"
	if inside(): return "正在登机 · 留在 H 圈内"
	if s.boarding_progress > 0: return "已离开 H 圈 · 登机进度缓慢回退"
	return "抵达后留在 H 圈内准备登机"

func point(index: int, fraction: float) -> Vector3:
	var angle := float(index) / SEGMENTS * TAU - PI / 2
	var radius := boundary_radii[index] * fraction
	var p: Vector3 = world.extraction + Vector3(cos(angle), 0, sin(angle)) * radius
	p.y = world.board.layout.height_at(p.x, p.z) + 0.10
	return p

func update() -> void:
	var s = world.session
	var active: bool = s.phase == "evacuate" and world.started
	var visible: bool = world.vision.is_visible(world.board.cell_at(world.extraction))
	caption.visible = active and visible
	arc.visible = active and visible and s.mode in ["standard", "hard"]
	world.extraction_marker.scale = Vector3.ONE
	world.extraction_marker.material_override.albedo_color = Color("a2c9a6") if active else Color("c9b575")
	if not active: return
	caption.text = ("登机 %.1f / %.0f 秒" % [s.boarding_progress, Catalog.BOARDING_SECONDS]) if s.mode in ["standard", "hard"] else "救援已抵达"
	var count := clampi(floori(s.boarding_progress / Catalog.BOARDING_SECONDS * SEGMENTS), 0, SEGMENTS)
	if count == last_segments: return
	last_segments = count
	fill_arc(geometry,count,0.93,0.98)

func fill_arc(mesh: ImmediateMesh, count: int, inner: float, outer: float) -> void:
	mesh.clear_surfaces()
	if count == 0: return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(count):
		var inner_a := point(i,inner)
		var outer_a := point(i,outer)
		var inner_b := point(i+1,inner)
		var outer_b := point(i+1,outer)
		for vertex in [inner_a, outer_a, outer_b, inner_a, outer_b, inner_b]: mesh.surface_add_vertex(vertex)
	mesh.surface_end()

func make_landing_mark() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect in [Rect2(-1.05,-1.6,.4,3.2),Rect2(.65,-1.6,.4,3.2),Rect2(-.65,-.2,1.3,.4)]:
		var steps := 16
		for i in range(steps):
			var low: float = rect.position.y + rect.size.y*float(i)/steps
			var high: float = rect.position.y + rect.size.y*float(i+1)/steps
			var points := [Vector2(rect.position.x,low),Vector2(rect.end.x,low),Vector2(rect.end.x,high),Vector2(rect.position.x,high)]
			for index in [0,2,1,0,3,2]:
				var p: Vector3 = world.extraction+Vector3(points[index].x,0,points[index].y)
				p.y = world.board.layout.height_at(p.x,p.z)+.12
				mesh.surface_add_vertex(p)
	mesh.surface_end()
	var mark := MeshInstance3D.new()
	mark.name = "LandingH"
	mark.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("dbc58e")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mark.material_override = material
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mark)
