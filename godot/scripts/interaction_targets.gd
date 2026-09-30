extends RefCounted
## Render-space picking and presentation, independent of navigation occupancy.
const HOVER_COLOR := Color("b5b8a1", 0.48)
const SELECTED_COLOR := Color("d8c38d", 0.85)
const BLOCKED_COLOR := Color("ff8978", 0.8)
const CLICK_SECONDS := 0.24
const CHUNK := 16.0
var world: Node
var chunks := {}
var faces := {}
var hover_target := {}
var layers := {}
var clicked_node: Node3D
var click_left := 0.0

func _init(owner_world: Node) -> void:
	world = owner_world
	# Forest batching hides source meshes; retain their transforms for picking and
	# retain accurate model picking without changing their materials.
	for cell in world.trees:
		var node: Node3D = world.trees[cell].node
		var parts: Array = []
		var bounds := AABB()
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null: continue
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if parts.is_empty() else bounds.merge(box)
			parts.append(mesh)
		if parts.is_empty(): continue
		var key := Vector2i(floori(node.global_position.x / CHUNK), floori(node.global_position.z / CHUNK))
		if not chunks.has(key): chunks[key] = {"bounds": bounds, "trees": []}
		else: chunks[key].bounds = chunks[key].bounds.merge(bounds)
		chunks[key].trees.append({"cell": cell, "bounds": bounds, "parts": parts})
	for key in ["hover", "order", "selected"]:
		var holder := Node3D.new()
		holder.name = "Target_" + key
		world.add_child(holder)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ring := MeshInstance3D.new()
		ring.material_override = mat
		holder.add_child(ring)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		layers[key] = {"root": holder, "ring": ring, "material": mat, "node": null, "anchor": Vector3.ZERO, "radius": 0.85, "drawn_radius": -1.0, "center": Vector3.INF}
		holder.hide()

func mesh_hit(mesh: MeshInstance3D, origin: Vector3, direction: Vector3, precise: bool) -> float:
	var inverse := mesh.global_transform.affine_inverse()
	var start := inverse * origin
	var ray := inverse.basis * direction
	var hit: Variant = mesh.get_aabb().intersects_ray(start, ray)
	if hit == null: return INF
	if not precise: return origin.distance_squared_to(mesh.global_transform * hit)
	var id := mesh.mesh.get_instance_id()
	if not faces.has(id): faces[id] = mesh.mesh.get_faces()
	var vertices: PackedVector3Array = faces[id]
	var nearest := INF
	for i in range(0, vertices.size(), 3):
		hit = Geometry3D.ray_intersects_triangle(start, ray, vertices[i], vertices[i+1], vertices[i+2])
		if hit != null: nearest = minf(nearest, origin.distance_squared_to(mesh.global_transform * hit))
	return nearest

func action_point(screen: Vector2, ground: Vector3) -> Vector3:
	var origin: Vector3 = world.camera.project_ray_origin(screen)
	var direction: Vector3 = world.camera.project_ray_normal(screen)
	var nearest := origin.distance_squared_to(ground) + 0.05
	var chosen := ground
	var found := false
	for chunk in chunks.values():
		if chunk.bounds.intersects_ray(origin, direction) == null: continue
		for tree in chunk.trees:
			if not world.trees.has(tree.cell) or not world.vision.explored.has(tree.cell): continue
			if tree.bounds.intersects_ray(origin, direction) == null: continue
			for mesh in tree.parts:
				var distance := mesh_hit(mesh, origin, direction, true)
				if distance < nearest:
					nearest = distance
					chosen = world.board.point(tree.cell)
					found = true
	# Depth ordering keeps a foreground tree clickable beside/above a building.
	for b in world.session.buildings:
		if b.hp <= 0 or not world.visuals.has(b.id) or not world.vision.explored.has(b.cell): continue
		for mesh in world.visuals[b.id].get_node("Model").find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
			var distance := mesh_hit(mesh, origin, direction, true)
			if distance < nearest:
				nearest = distance
				chosen = world.board.point(b.cell)
				found = true
	for d in world.dinosaurs:
		if d.health <= 0 or not d.is_visible_in_tree(): continue
		for mesh in d.get_node("Model").find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
			var distance := mesh_hit(mesh, origin, direction, false)
			if distance < nearest:
				nearest = distance
				chosen = d.position
				found = true
	for system in [world.outfitting, world.adventure]:
		for node in system.visuals.values():
			if not node.is_visible_in_tree(): continue
			for mesh in node.find_children("*", "MeshInstance3D", true, false):
				if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
				var distance := mesh_hit(mesh, origin, direction, true)
				if distance < nearest:
					nearest = distance
					chosen = node.position
					found = true
	if found: return chosen
	# Preserve forgiving ground footprints for foundations and empty frames.
	var footprint_distance := 1.5
	for b in world.session.buildings:
		if b.hp <= 0 or not world.vision.explored.has(b.cell): continue
		var point: Vector3 = world.board.point(b.cell)
		var distance := point.distance_to(ground)
		if distance < footprint_distance:
			footprint_distance = distance
			chosen = point
	return chosen

func target_node(target: Dictionary) -> Node3D:
	if target.is_empty(): return null
	match str(target.kind):
		"wood":
			return world.trees.get(world.board.cell_at(target.position), {}).get("node")
		"attack":
			for d in world.dinosaurs:
				if d.get_instance_id() == target.get("id", -1) and d.health > 0 and d.visible: return d.get_node("Model")
		"field_site": return world.outfitting.visuals.get(target.get("site", ""))
		"inspect": return world.adventure.visuals.get(target.get("site", ""))
		_:
			var b: Dictionary = world.session.building(target.get("id", -1))
			if not b.is_empty() and b.hp > 0 and world.visuals.has(b.id): return world.visuals[b.id].get_node("Model")
	return null

func current_order() -> Dictionary:
	match world.order:
		"wood":
			if world.trees.has(world.board.cell_at(world.order_target)): return {"kind": "wood", "position": world.order_target}
		"attack": return {"kind": "attack", "id": world.hero.target_id}
		"build", "repair", "return", "heal": return {"kind": world.order, "id": world.worker.target_id}
		"gold":
			var b: Dictionary = world.building_at(world.board.cell_at(world.order_target))
			if not b.is_empty(): return {"kind": "gold", "id": b.id}
		"field":
			var actor: Dictionary = world.outfitting.actor()
			return {"kind": "field_site", "site": actor.site} if actor.task == "explore" else {"kind": "select", "id": actor.target}
		"expedition": return {"kind": "inspect", "site": world.adventure.data().get("job", {}).get("id", "")}
	return {}

func confirm(target: Dictionary, accepted: bool) -> void:
	clicked_node = target_node(target) if accepted else null
	click_left = CLICK_SECONDS if is_instance_valid(clicked_node) else 0.0

func ground_ring(center: Vector3, radius: float) -> ArrayMesh:
	# A thin, empty-centred ribbon follows the actual terrain, including slopes.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(64):
		var points: Array[Vector3] = []
		for angle in [i * TAU / 64.0, (i + 1) * TAU / 64.0]:
			for r in [radius - 0.025, radius + 0.025]:
				var p := center + Vector3(cos(angle) * r, 0, sin(angle) * r)
				p.y = world.board.layout.height_at(p.x, p.z) if world.board.layout else center.y
				points.append(p + Vector3.UP * 0.055)
		for index in [0, 1, 2, 1, 3, 2]: surface.add_vertex(points[index])
	surface.generate_normals()
	return surface.commit()

func footprint(node: Node3D, tree: bool) -> Dictionary:
	var parts := node.find_children("*", "MeshInstance3D", true, false)
	var bases: Array[Node] = []
	for part in parts:
		if (tree and "Trunk" in str(part.name)) or (not tree and "Foundation" in str(part.name)):
			bases.append(part)
	var bounds := AABB()
	var first := true
	for source in (bases if not bases.is_empty() else parts):
		# Batched forest source meshes are hidden but retain the rendered transforms.
		if source.mesh == null or (not tree and not source.is_visible_in_tree()): continue
		var box: AABB = source.global_transform * source.get_aabb()
		if tree and not bases.is_empty():
			# Only the trunk foot defines the anchor; leaning branches/canopies do not.
			var local_box: AABB = source.get_aabb()
			var cutoff: float = local_box.position.y + minf(0.2, local_box.size.y * 0.1)
			var id: int = source.mesh.get_instance_id()
			if not faces.has(id): faces[id] = source.mesh.get_faces()
			var base_first := true
			for vertex in faces[id]:
				if vertex.y > cutoff: continue
				var point: Vector3 = source.global_transform * vertex
				box = AABB(point, Vector3.ZERO) if base_first else box.expand(point)
				base_first = false
		bounds = box if first else bounds.merge(box)
		first = false
	var center := node.global_position if first else bounds.get_center()
	center.y = node.global_position.y
	var radius := 0.85 if tree else clampf(maxf(bounds.size.x, bounds.size.z) * 0.55, 0.85, 3.8)
	if "body_radius" in node.get_parent():
		center = node.global_position
		radius = maxf(0.8, float(node.get_parent().body_radius) + 0.25)
	return {"anchor": node.to_local(center), "radius": radius}

func show_layer(key: String, node: Node3D, color: Color, tree: bool = false) -> void:
	var layer: Dictionary = layers[key]
	layer.root.visible = is_instance_valid(node) and node.is_visible_in_tree()
	if not layer.root.visible: return
	if not is_instance_valid(layer.node) or layer.node != node:
		layer.node = node
		layer.center = Vector3.INF
		var base := footprint(node, tree or node.has_meta("harvest_tree"))
		layer.anchor = base.anchor
		layer.radius = base.radius
	var radius: float = layer.radius
	if is_instance_valid(clicked_node) and node == clicked_node and click_left > 0:
		var progress := 1.0 - click_left / CLICK_SECONDS
		radius *= 1.0 + 0.13 * pow(1.0 - progress, 3.0)
	var center := node.to_global(layer.anchor)
	if layer.center != center or not is_equal_approx(layer.drawn_radius, radius):
		layer.center = center
		layer.drawn_radius = radius
		layer.ring.mesh = ground_ring(center, radius)
	layer.material.albedo_color = color

func refresh(allow_hover: bool, blocked: bool = false, dt: float = 0.0) -> void:
	if not world.presentation_paused(): click_left = maxf(0, click_left - dt)
	if not world.started or world.paused or world.session.phase not in ["playing", "evacuate"] or not world.build_mode.is_empty():
		for layer in layers.values(): layer.root.hide()
		return
	var hover: Node3D = target_node(hover_target) if allow_hover else null
	var order := current_order()
	var working: Node3D = target_node(order)
	var selected: Node3D = target_node({"kind": "select", "id": world.selected_id})
	# Hover must not replace an active gold ring or add another ring to it.
	var hover_color := BLOCKED_COLOR if blocked else (SELECTED_COLOR if hover != null and (hover == working or hover == selected) else HOVER_COLOR)
	show_layer("hover", hover, hover_color, hover_target.get("kind") == "wood")
	show_layer("order", working if working != hover else null, SELECTED_COLOR, order.get("kind") == "wood")
	show_layer("selected", selected if selected != hover and selected != working else null, SELECTED_COLOR)
