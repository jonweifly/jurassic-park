extends RefCounted
## Keep editable source trees and gameplay cells, batch only their runtime rendering.
const CHUNK_SIZE := 16.0
var world: Node
var batches: Array[Dictionary] = []
var cells := {}
var source_parts := 0
var root: Node3D
var lod_sources := {}

func _init(owner_world: Node, enabled: bool = true, cinematic: bool = false) -> void:
	world = owner_world
	if not enabled: return
	root = Node3D.new()
	root.name = "ForestBatches"
	world.get_node("Island").add_child(root)
	var groups := {}
	var families := ["broadleaf","tree","snow_tree","canopy_tree","split_tree","palm_tree","wind_pine"]
	if cinematic: families.append("cinematic_tree")
	for family in families:
		var asset_root := "res://assets/cinematic/gameplay/rainforest_tree" if family == "cinematic_tree" else "res://assets/models/%s" % family
		var lod_path := "res://assets/cinematic/gameplay/rainforest_tree_lod.glb" if family == "cinematic_tree" else "res://assets/models/%s_lod.glb" % family
		var source: Node3D = load(lod_path).instantiate()
		var meshes := {}
		for part in source.find_children("*","MeshInstance3D",true,false): meshes[str(part.name)] = part.mesh
		lod_sources[asset_root + ".glb"] = meshes
		source.free()
	for cell in world.trees:
		var tree: Node3D = world.trees[cell].node
		# Animated imported trees keep their regular renderer until explicitly baked.
		if not tree.find_children("*", "AnimationPlayer", true, false).is_empty(): continue
		for part in tree.find_children("*", "MeshInstance3D", true, false):
			if not part.mesh or not part.is_visible_in_tree(): continue
			if part.skin or (part.mesh is ArrayMesh and part.mesh.get_blend_shape_count() > 0): continue
			var chunk := Vector2i(floori(part.global_position.x / CHUNK_SIZE), floori(part.global_position.z / CHUNK_SIZE))
			var override_id: int = part.material_override.get_instance_id() if part.material_override else 0
			var overlay_id: int = part.material_overlay.get_instance_id() if part.material_overlay else 0
			var key := "%s:%d:%d:%d:%d" % [chunk,part.mesh.get_instance_id(),override_id,overlay_id,part.cast_shadow]
			if not groups.has(key):
				var lod: Mesh = lod_sources.get(part.get_parent().scene_file_path,{}).get(str(part.name),part.mesh)
				groups[key] = {"chunk":chunk,"parts":[],"cells":[],"lod":lod}
			groups[key].parts.append(part)
			groups[key].cells.append(cell)
	for group in groups.values(): create_batch(group)

func create_batch(group: Dictionary) -> void:
	var original: MeshInstance3D = group.parts[0]
	var node := MultiMeshInstance3D.new()
	node.name = "Trees_%d" % batches.size()
	node.position = Vector3((group.chunk.x+0.5)*CHUNK_SIZE,0,(group.chunk.y+0.5)*CHUNK_SIZE)
	node.material_override = original.material_override
	node.material_overlay = original.material_overlay
	node.cast_shadow = original.cast_shadow
	root.add_child(node)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = original.mesh
	multi.instance_count = group.parts.size()
	multi.visible_instance_count = multi.instance_count
	node.multimesh = multi
	var batch_id := batches.size()
	var entries: Array[Dictionary] = []
	var inverse := node.global_transform.affine_inverse()
	for i in range(group.parts.size()):
		var part: MeshInstance3D = group.parts[i]
		multi.set_instance_transform(i,inverse * part.global_transform)
		var cell: Vector2i = group.cells[i]
		var slot := {"batch":batch_id,"index":i,"cell":cell}
		entries.append(slot)
		if not cells.has(cell): cells[cell] = []
		cells[cell].append(slot)
		part.hide()
		source_parts += 1
	batches.append({"node":node,"multi":multi,"entries":entries,"high":original.mesh,"low":group.lod,"detail":true})

func remove_cell(cell: Vector2i) -> void:
	if not cells.has(cell): return
	# Dense swap-removal avoids zero-scale matrices and keeps culled instances out
	# of the vertex workload. Slots are shared so later harvests see updated indices.
	for slot in cells[cell]:
		var batch: Dictionary = batches[slot.batch]
		var entries: Array = batch.entries
		var last := entries.size() - 1
		var index: int = slot.index
		if index != last:
			batch.multi.set_instance_transform(index,batch.multi.get_instance_transform(last))
			var moved: Dictionary = entries[last]
			moved.index = index
			entries[index] = moved
		entries.remove_at(last)
		batch.multi.visible_instance_count = entries.size()
		batch.node.visible = not entries.is_empty()
	cells.erase(cell)

func live_parts() -> int:
	var count := 0
	for batch in batches: count += batch.entries.size()
	return count

func update_lod(focus: Vector3, zoom: float) -> void:
	# Measure distance on the playfield; orthographic camera boom is always 68 m away.
	for batch in batches:
		var distance := Vector2(batch.node.position.x-focus.x,batch.node.position.z-focus.z).length()
		var detail: bool = batch.detail
		if detail and (distance > 30 or zoom > 49): detail = false
		elif not detail and distance < 24 and zoom < 45: detail = true
		if detail != batch.detail:
			batch.multi.mesh = batch.high if detail else batch.low
			batch.detail = detail
		batch.node.visible = batch.multi.visible_instance_count > 0 and distance < zoom * 1.1 + 42
