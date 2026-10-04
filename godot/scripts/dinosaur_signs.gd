extends RefCounted
## Short-lived environmental traces left by visible dinosaurs.
## This layer is presentation-only: it never changes navigation, AI or saves.
const MAX_MARKS := 48
var world: Node
var root: Node3D
var clocks: Dictionary = {}
var last_positions: Dictionary = {}
var marks: Array[Dictionary] = []

func _init(owner_world: Node) -> void:
	world = owner_world
	if DisplayServer.get_name() == "headless": return
	root = Node3D.new()
	root.name = "DinosaurSigns"
	world.add_child(root)
	world.vision.shade(root)

func update(dt: float) -> void:
	if root == null or not world.started or world.presentation_paused(): return
	for d in world.dinosaurs:
		if not is_instance_valid(d) or d.health <= 0: continue
		var id: int = int(d.get_meta("save_id", d.get_instance_id()))
		var previous: Vector3 = last_positions.get(id, d.position)
		var moved := Vector2(d.position.x - previous.x, d.position.z - previous.z).length()
		last_positions[id] = d.position
		clocks[id] = maxf(0.0, float(clocks.get(id, 0.0)) - dt)
		if moved < 0.03 or d.current_speed < 0.45 or clocks[id] > 0.0: continue
		if not d.visible or not world.vision.is_visible(world.board.cell_at(d.position)): continue
		if d.position.distance_to(world.camera_rig.focus) > 30.0: continue
		var heavy: bool = d.get_meta("species", "raptor") in ["young_trex", "trex", "alpha_trex"]
		leave_track(d, previous, d.position, heavy)
		clocks[id] = 0.52 if heavy else 0.72
	update_marks(dt)
	for id in last_positions.keys().duplicate():
		if not world.dinosaurs.any(func(d): return is_instance_valid(d) and int(d.get_meta("save_id", -1)) == id):
			last_positions.erase(id)
			clocks.erase(id)

func leave_track(d: Node3D, previous: Vector3, current: Vector3, heavy: bool) -> void:
	if marks.size() >= MAX_MARKS:
		var old: Dictionary = marks.pop_front()
		if is_instance_valid(old.node): old.node.queue_free()
	var heading := Vector2(current.x - previous.x, current.z - previous.z)
	if heading.length_squared() < 0.0001: return
	heading = heading.normalized()
	var side := Vector2(-heading.y, heading.x)
	var center := (previous + current) * 0.5
	var tint := Color("4e493d") if heavy else Color("405043")
	var scale := 1.35 if heavy else 0.88
	for offset in [-0.22, 0.22]:
		var at := center + Vector3(side.x * offset, 0.0, side.y * offset)
		var mark := MeshInstance3D.new()
		mark.name = "DinosaurTrack"
		var mesh := SphereMesh.new()
		mesh.radius = 0.13 * scale
		mesh.height = 0.055 * scale
		mesh.radial_segments = 8
		mesh.rings = 3
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(tint, 0.52 if heavy else 0.34)
		material.roughness = 1.0
		mesh.material = material
		mark.mesh = mesh
		mark.scale = Vector3(1.0, 0.22, 1.55)
		mark.rotation.y = atan2(heading.x, heading.y)
		mark.position = at
		mark.position.y = world.board.layout.height_at(at.x, at.z) + 0.028
		root.add_child(mark)
		world.vision.shade(mark)
		marks.append({"node": mark, "age": 0.0, "lifetime": 7.5 if heavy else 5.5, "material": material})

func update_marks(dt: float) -> void:
	for item in marks.duplicate():
		item.age += dt
		var node: Node3D = item.node
		if not is_instance_valid(node) or item.age >= item.lifetime:
			if is_instance_valid(node): node.queue_free()
			marks.erase(item)
			continue
		var material: StandardMaterial3D = item.material
		var fade: float = 1.0 - item.age / item.lifetime
		var color := material.albedo_color
		color.a = fade * (0.52 if item.lifetime > 6.0 else 0.34)
		material.albedo_color = color
		node.visible = world.vision.is_visible(world.board.cell_at(node.position))

func _exit_tree() -> void:
	for item in marks:
		if is_instance_valid(item.node): item.node.queue_free()
