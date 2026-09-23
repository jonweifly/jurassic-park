extends RefCounted
const Features = preload("res://scripts/feature_policy.gd")
## Shared vision data drives world shading, enemy rendering, targeting and minimap.
const Board = preload("res://scripts/board.gd")
var world: Node
var visible_cells: Dictionary = {}
var explored: Dictionary = {}
var image: Image
var texture: ImageTexture
var overlay: ShaderMaterial
var countdown := 0.0

func _init(owner_world: Node) -> void:
	world = owner_world
	image = Image.create(Board.SIDE, Board.SIDE, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	texture = ImageTexture.create_from_image(image)
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never;
uniform sampler2D visibility_map : filter_linear, repeat_disable;
uniform float extent;
varying vec2 map_uv;
void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_uv = p.xz / extent + vec2(0.5);
}
void fragment() {
	float sight = texture(visibility_map, map_uv).r;
	ALBEDO = vec3(mix(0.035, 1.0, sight));
	ALPHA = 1.0;
}
"""
	overlay = ShaderMaterial.new()
	overlay.shader = shader
	overlay.set_shader_parameter("visibility_map", texture)
	overlay.set_shader_parameter("extent", Board.SIDE * Board.CELL)
	if world.has_node("Island"): shade(world.get_node("Island"))

func shade(root: Node) -> void:
	if root is GeometryInstance3D: root.material_overlay = overlay
	for child in root.get_children(): shade(child)

func is_visible(cell: Vector2i) -> bool:
	return visible_cells.has(cell)

func clear_line(a: Vector2i, b: Vector2i) -> bool:
	var delta := b - a
	var steps := maxi(absi(delta.x), absi(delta.y))
	for i in range(1, steps):
		var c := Vector2i(Vector2(a).lerp(Vector2(b), float(i) / steps).round())
		if world.trees.has(c): return false
		var ray_height: float = lerpf(world.board.point(a).y + 2.5, world.board.point(b).y + 1.0, float(i) / maxf(steps, 1))
		if world.board.point(c).y > ray_height: return false
	return true

func reveal(point: Vector3, radius: float) -> void:
	var origin: Vector2i = world.board.cell_at(point)
	var cells := ceili(radius / Board.CELL)
	for x in range(-cells, cells + 1):
		for y in range(-cells, cells + 1):
			var c := origin + Vector2i(x, y)
			if not world.board.inside(c) or Vector2(x, y).length() > cells: continue
			if not clear_line(origin, c): continue
			visible_cells[c] = true
			explored[c] = true

func tick(dt: float) -> void:
	countdown -= dt
	if countdown <= 0:
		countdown = 0.25
		update()

func update() -> void:
	visible_cells.clear()
	# Sight radii are provisional, shared by rendering and combat.
	if world.hero.health > 0: reveal(world.hero.position, 22.0 if Features.peripheral_enabled and world.session.game_time() < world.session.adventure.get("scan_until", 0.0) else (9.0 if world.night else 15.0))
	for b in world.session.buildings:
		if b.hp <= 0 or b.remaining > 0: continue
		var radius := 6.0
		if b.kind == "tent": radius = 10.0
		if b.kind == "fire": radius = 14.0
		if b.kind == "tower" and world.session.supply() >= world.session.demand(): radius = maxf(16.0, world.Catalog.attack_range(b))
		reveal(world.board.point(b.cell), radius)
	image.fill(Color.BLACK)
	for c in explored: image.set_pixel(c.x, c.y, Color(0.28, 0.28, 0.28))
	for c in visible_cells: image.set_pixel(c.x, c.y, Color.WHITE)
	texture.update(image)
	for d in world.dinosaurs:
		if is_instance_valid(d): d.visible = is_visible(world.board.cell_at(d.position))
