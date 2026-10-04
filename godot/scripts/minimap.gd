extends Control
const Board = preload("res://scripts/board.gd")
const Features = preload("res://scripts/feature_policy.gd")
const EXTENT = Board.SIDE * Board.CELL
var world: Node

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		world.camera_rig.following = false
		world.camera_focus = Vector3((event.position.x / size.x - 0.5) * EXTENT, 0, (event.position.y / size.y - 0.5) * EXTENT)
		accept_event()

func project(p: Vector3) -> Vector2:
	return Vector2(p.x / EXTENT + 0.5, p.z / EXTENT + 0.5) * size

func _draw() -> void:
	if not is_instance_valid(world): return
	draw_rect(Rect2(Vector2.ZERO, size), Color("070e0c"))
	for cell in world.vision.explored:
		var p: Vector2 = project(world.board.point(cell))
		var tile := size / float(Board.SIDE)
		draw_rect(Rect2(p - tile * 0.5, tile + Vector2.ONE), Color("3a543b") if world.vision.is_visible(cell) else Color("203027"))
	for cell in world.board.terrain:
		if not world.vision.explored.has(cell): continue
		var p: Vector2 = project(world.board.point(cell))
		draw_rect(Rect2(p - Vector2.ONE, Vector2(3, 3)), Color("416443"))
	if not world.board.layout.free_fossil_placement:
		for zone in world.board.layout.gold_zones:
			var coords: Array = zone.world
			var point := Vector3(float(coords[0]), 0, float(coords[1]))
			if not world.vision.explored.has(world.board.cell_at(point)): continue
			var tint := Color("d7b75e") if int(world.session.deposit_reserves.get(str(zone.id), 0)) > 0 else Color("69736a")
			draw_circle(project(point), 3.5, tint, false, 1.5)
	for b in world.session.buildings:
		if b.hp > 0: draw_rect(Rect2(project(world.board.point(b.cell)) - Vector2(2, 2), Vector2(4, 4)), Color("d6bf79"))
	for b in world.session.buildings:
		if world.outfitting.recent_hits.has(b.id): draw_circle(project(world.board.point(b.cell)), 5.0 + sin(Time.get_ticks_msec() * .01), Color("ff8060"), false, 1.5)
	for id in world.outfitting.data().sites:
		var site: Dictionary = world.outfitting.data().sites[id]
		var at: Vector2 = project(world.board.point(site.cell))
		draw_rect(Rect2(at - Vector2(2,2), Vector2(4,4)), Color("d7bb76") if site.status == "known" else Color("718f78"), false, 1.2)
	for d in world.dinosaurs:
		if is_instance_valid(d) and d.health > 0 and world.vision.is_visible(world.board.cell_at(d.position)): draw_circle(project(d.position), 2.0, Color("dc8069"))
	for id in world.session.adventure.get("sites", {}):
		if not Features.peripheral_enabled: break
		var site: Dictionary = world.session.adventure.sites[id]
		if site.status == "hidden": continue
		var at: Vector2 = project(world.board.point(site.cell))
		var color := Color("8ba88b") if site.status == "completed" else Color("efd17f")
		draw_rect(Rect2(at - Vector2(2.5, 2.5), Vector2(5, 5)), color, false, 1.2)
		if world.session.adventure.get("tracked", "") == id: draw_circle(at, 5.5, Color("fff0b2"), false, 1)
	draw_circle(project(world.hero.position), 3.5, Color("c7f4d6"))
	for survivor in world.survivors():
		if survivor != world.hero: draw_circle(project(survivor.position),3.5,Color("83c9f1"))
	draw_circle(project(world.extraction), 4.0, Color("c4ac6b"), false, 1.5)
	var corners := PackedVector2Array()
	var viewport_size: Vector2 = world.get_viewport().get_visible_rect().size
	var plane := Plane(Vector3.UP, world.camera_rig.focus.y)
	for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]:
		var screen: Vector2 = uv * viewport_size
		var hit = plane.intersects_ray(world.camera.project_ray_origin(screen), world.camera.project_ray_normal(screen))
		if hit != null: corners.append(project(hit).clamp(Vector2.ZERO, size))
	if corners.size() == 5: draw_polyline(corners, Color("9cae91"), 1.0, true)
