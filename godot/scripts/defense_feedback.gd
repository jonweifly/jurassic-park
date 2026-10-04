extends Control
const Catalog = preload("res://scripts/catalog.gd")
var world: Node
var range_node: MeshInstance3D
var range_key := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	range_node = MeshInstance3D.new()
	range_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.56, 0.70, 0.62, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	range_node.material_override = mat
	world.add_child(range_node)
	world.vision.shade(range_node)

func _process(_dt: float) -> void:
	var b: Dictionary = world.selected_building()
	var preview: bool = world.build_mode in ["tower", "shelter", "gate"]
	if not world.build_mode.is_empty():
		b = {"id": -1, "kind": world.build_mode, "cell": world.hover_cell, "remaining": 0.0} if preview else {}
	var show_range: bool = world.started and not world.paused and not b.is_empty() and b.kind in ["tower", "shelter", "gate"] and b.remaining <= 0
	# Keep the tactical range visible while the player is choosing a plot.  The
	# HUD consumes clicks over its own controls, but hiding the world preview
	# there leaves the player without feedback for a plot already under the
	# cursor (and makes keyboard/controller hover state inconsistent with mouse).
	if preview: show_range = show_range and world.board.inside(world.hover_cell)
	range_node.visible = show_range
	if show_range:
		var key := "%d:%s:%s:%s" % [b.id, b.kind, b.cell, b.get("refit", "")]
		range_node.material_override.albedo_color = Color(0.85, 0.4, 0.3, 0.65) if preview and not world.placement_error(b.cell).is_empty() else Color(0.56, 0.70, 0.62, 0.55)
		if range_key != key:
			range_key = key
			var mesh := ImmediateMesh.new()
			mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			var center: Vector3 = world.board.point(b.cell)
			var radius := Catalog.attack_range(b)
			for i in range(96):
				if i % 3 == 2: continue
				for j in [i, i + 1]:
					var angle: float = TAU * j / 96.0
					var p := center + Vector3(cos(angle), 0, sin(angle)) * radius
					p.y = world.board.layout.height_at(p.x, p.z) + 0.10
					mesh.surface_add_vertex(p)
			mesh.surface_end()
			range_node.mesh = mesh
	queue_redraw()

func _draw() -> void:
	if not world.started or world.paused: return
	var marked: Node3D = world.defense.focused()
	if marked != null and marked.visible:
		var position: Vector3 = marked.position + Vector3.UP * 2.8
		if not world.camera.is_position_behind(position):
			var point: Vector2 = world.camera.unproject_position(position)
			if get_viewport_rect().has_point(point) and not world.hud.covers(point):
				draw_arc(point, 12, 0, TAU, 32, Color("efb16c"), 2, true)
				for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]: draw_line(point + direction * 8, point + direction * 17, Color("efb16c"), 2, true)
	for b in world.session.buildings:
		var maximum := Catalog.max_health(b)
		if b.hp <= 0 or b.hp >= maximum or not world.vision.is_visible(b.cell): continue
		var p: Vector3 = world.board.point(b.cell) + Vector3.UP * (3.8 if b.kind == "tower" else 2.5)
		if world.camera.is_position_behind(p): continue
		var screen: Vector2 = world.camera.unproject_position(p)
		if not get_viewport_rect().has_point(screen) or world.hud.covers(screen): continue
		var rect := Rect2(screen - Vector2(22, 3), Vector2(44, 6))
		draw_rect(rect.grow(1), Color("15231f"))
		rect.size.x *= clampf(b.hp / maximum, 0.0, 1.0)
		draw_rect(rect, Color("df846a") if b.hp < maximum * 0.35 else Color("c9b16e"))
