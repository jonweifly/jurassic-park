extends Node
## Visual adapter: gameplay never needs limb paths, skeleton names or clip prefixes.
@export_node_path("Node3D") var model_path := NodePath("../Model")
@export_node_path("AnimationPlayer") var animator_path := NodePath("../AnimationPlayer")
@export var work_equipment := false
@export_node_path("Skeleton3D") var contact_rig_path := NodePath("")
const SurvivorContact = preload("res://scripts/survivor_contact.gd")
const SurvivorMotion = preload("res://scripts/survivor_motion.gd")
const DinosaurDetail = preload("res://scripts/dinosaur_detail.gd")
var contact: RefCounted
var motion: RefCounted
var dinosaur_detail: Node3D
var rifle_sling: BoneAttachment3D
var rifle_grip: Node3D
var rifle_rest := Transform3D.IDENTITY
@export_node_path("Node3D") var hand_socket_path := NodePath("../Model/ArmR")
@export_node_path("Node3D") var cargo_socket_path := NodePath("../Model")
@export_node_path("Node3D") var rifle_path := NodePath("../Model/ArmR/Rifle")
@export var tool_grip := Vector3(0,-0.48,0)
@export var tool_rotation_degrees := Vector3.ZERO
@export var cargo_origin := Vector3(0,1.15,0.42)
@export var cargo_rotation_degrees := Vector3.ZERO
@export var clips: Dictionary = {}
@export var locomotion_stride := 1.36
@export var axe_scene: PackedScene
@export var pickaxe_scene: PackedScene
@export var hammer_scene: PackedScene
@export var wood_cargo_scene: PackedScene
@export var ore_cargo_scene: PackedScene
var model: Node3D
var player: AnimationPlayer
var chainsaw: Node3D
var saw_equipped := false
var axe: Node3D
var pickaxe: Node3D
var hammer: Node3D
var bundle: Node3D
var ore: Node3D
var rifle: Node3D
var state := ""

func _ready() -> void:
	model = get_node(model_path)
	player = get_node(animator_path)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if work_equipment: make_equipment()
	if get_parent().is_dinosaur:
		var dinosaur_rig := model.get_node_or_null("Rig/Skeleton3D") as Skeleton3D
		if dinosaur_rig:
			var kind := model.scene_file_path.get_file().get_basename().trim_suffix("_v2")
			dinosaur_detail = DinosaurDetail.attach(self, dinosaur_rig, kind)
	if not contact_rig_path.is_empty():
		var rig := get_node_or_null(contact_rig_path) as Skeleton3D
		if rig:
			contact = SurvivorContact.new(self, rig)
			if not contact.ready(): contact = null
			else: motion = SurvivorMotion.new(contact)

static func box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	mesh.material = mat
	piece.mesh = mesh
	piece.position = at
	parent.add_child(piece)
	return piece

static func axe_blade(parent: Node3D, outline: PackedVector2Array, color: Color) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for point in outline:
		# The poll is thick; the cutting edge tapers to a fine steel wedge.
		var thickness := lerpf(0.052, 0.007, clampf(point.x / 0.34, 0, 1))
		front.append(Vector3(point.x, thickness, point.y))
		back.append(Vector3(point.x, -thickness, point.y))
	var indices := Geometry2D.triangulate_polygon(outline)
	for index in indices: surface.add_vertex(front[index])
	indices.reverse()
	for index in indices: surface.add_vertex(back[index])
	for index in range(outline.size()):
		var next := (index + 1) % outline.size()
		for vertex in [front[index], back[index], back[next], front[index], back[next], front[next]]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.35
	material.roughness = 0.55
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.set_material(material)
	var blade := MeshInstance3D.new()
	blade.name = "AxeBlade"
	blade.mesh = surface.commit()
	parent.add_child(blade)

func attach(scene: PackedScene, socket: Node3D, title: String, origin: Vector3) -> Node3D:
	var prop: Node3D = scene.instantiate() if scene else Node3D.new()
	prop.name = title
	socket.add_child(prop)
	prop.position = origin
	return prop

func make_equipment() -> void:
	var hand: Node3D = get_node(hand_socket_path)
	var cargo: Node3D = get_node(cargo_socket_path)
	rifle = get_node_or_null(rifle_path)
	if rifle:
		rifle_grip = rifle.get_parent()
		rifle_rest = rifle.transform
		var rig := model.get_node_or_null("Rig/Skeleton3D") as Skeleton3D
		if rig:
			rifle_sling = BoneAttachment3D.new()
			rifle_sling.name = "RifleSling"
			rifle_sling.bone_name = "spine"
			rig.add_child(rifle_sling)
	# A single flared, tapered blade distinguishes the axe from the hammer.
	axe = attach(null,hand,"WorkAxe",tool_grip)
	box(axe,Vector3(0.065,0.065,0.84),Vector3(0,0,0.30),Color("825633"))
	box(axe,Vector3(0.075,0.078,0.19),Vector3(0,0,-0.015),Color("503822"))
	box(axe,Vector3(0.15,0.105,0.13),Vector3(-0.025,0,0.70),Color("657a7a"))
	axe_blade(axe, PackedVector2Array([Vector2(0,.64),Vector2(.285,.548),Vector2(.285,.852),Vector2(0,.76)]), Color("9eadad"))
	axe_blade(axe, PackedVector2Array([Vector2(.285,.548),Vector2(.29,.54),Vector2(.34,.59),Vector2(.34,.81),Vector2(.29,.86),Vector2(.285,.852)]), Color("e0e8df"))
	chainsaw = attach(null,hand,"Chainsaw",tool_grip)
	box(chainsaw,Vector3(.22,.22,.30),Vector3(0,0,.16),Color("bb813b"))
	box(chainsaw,Vector3(.065,.16,.63),Vector3(0,0,.57),Color("99aaa5"))
	for z in range(7): box(chainsaw,Vector3(.085,.20,.035),Vector3(0,0,.30+z*.09),Color("33453c"))
	box(chainsaw,Vector3(.30,.045,.12),Vector3(0,.16,.16),Color("263e33"))
	chainsaw.rotation_degrees = tool_rotation_degrees
	hammer = attach(hammer_scene,hand,"WorkHammer",tool_grip)
	if not hammer_scene:
		box(hammer,Vector3(0.07,0.07,0.65),Vector3(0,0,0.22),Color("785838"))
		box(hammer,Vector3(0.34,0.19,0.19),Vector3(0,0,0.53),Color("687877"))
	pickaxe = attach(pickaxe_scene,hand,"WorkPickaxe",tool_grip)
	if not pickaxe_scene:
		box(pickaxe,Vector3(0.065,0.065,0.85),Vector3(0,0,0.27),Color("785838"))
		box(pickaxe,Vector3(0.65,0.08,0.1),Vector3(0,0,0.64),Color("849492"))
	bundle = attach(wood_cargo_scene,cargo,"WoodCargo",cargo_origin)
	if not wood_cargo_scene:
		for i in range(3): box(bundle,Vector3(0.72,0.16,0.17),Vector3(0,-0.12+i*0.14,0),Color("89653f"))
		box(bundle,Vector3(0.09,0.48,0.2),Vector3(0,0.03,0),Color("b8a879"))
	ore = attach(ore_cargo_scene,cargo,"OreCargo",cargo_origin)
	if not ore_cargo_scene:
		box(ore,Vector3(0.6,0.12,0.34),Vector3(0,-0.15,0),Color("6d573c"))
		for x in [-0.28,0.28]: box(ore,Vector3(0.05,0.28,0.35),Vector3(x,-0.06,0),Color("8d7553"))
		for i in range(3):
			var rock := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.12
			mesh.height = 0.22
			mesh.radial_segments = 5
			mesh.rings = 2
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("b5aa83")
			mat.roughness = 0.95
			mesh.material = mat
			rock.mesh = mesh
			rock.position = Vector3(-0.18+i*0.18,0.03,0)
			ore.add_child(rock)
	for prop in [axe,pickaxe,hammer]: prop.rotation_degrees = tool_rotation_degrees
	for prop in [bundle,ore]: prop.rotation_degrees = cargo_rotation_degrees
	show_equipment("idle",false,"")

func show_equipment(action: String, carrying: bool, cargo_kind: String) -> void:
	if not work_equipment: return
	axe.visible = action == "chop" and not saw_equipped
	if action != "chop": axe.rotation_degrees = tool_rotation_degrees
	chainsaw.visible = action == "chop" and saw_equipped
	hammer.visible = action == "build"
	pickaxe.visible = action == "mine"
	var carrying_visible := carrying and action not in ["chop","build","mine","death"]
	bundle.visible = carrying_visible and cargo_kind != "gold"
	ore.visible = carrying_visible and cargo_kind == "gold"
	if rifle:
		var stowed := action != "attack" and rifle_sling != null
		var socket: Node3D = rifle_sling if stowed else rifle_grip
		if rifle.get_parent() != socket: rifle.reparent(socket, false)
		rifle.transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, -0.22)), Vector3(0.25, -0.07, -0.29)) if stowed else rifle_rest
		rifle.visible = action == "attack" or (not carrying and action in ["idle", "walk"])

func face(direction: Vector3, dt: float, sharpness: float = 14.0) -> void:
	if Vector2(direction.x,direction.z).is_zero_approx(): return
	var before := model.rotation.y
	var turn := angle_difference(before, atan2(direction.x,direction.z)) * (1.0-exp(-sharpness*dt))
	model.rotation.y = before + clampf(turn, -TAU * dt, TAU * dt)
	if motion and dt > 0.0: motion.turn_velocity = angle_difference(before, model.rotation.y) / dt

func play(action: String, dt: float) -> void:
	if contact: contact.clear()
	var clip: StringName = clips.get(action,action)
	if state != action:
		state = action
		if player.has_animation(clip): player.play(clip,0.08)
		else: push_warning("Visual is missing animation: " + str(clip))
	player.advance(dt)

func seek_work(action: String, phase: float, dt: float) -> void:
	play(action,dt)
	player.seek(phase,true)
	if action == "chop" and axe:
		# Add a clear wind-up and follow-through to the hand-authored arm clip.
		var progress := clampf(phase / 1.1, 0.0, 1.0)
		var swing := lerpf(-52.0, 28.0, smoothstep(0.0, 0.68, progress))
		if progress > 0.68: swing = lerpf(28.0, 8.0, smoothstep(0.68, 1.0, progress))
		axe.rotation_degrees = tool_rotation_degrees + Vector3(swing, 0, 0)
	elif action == "mine" and pickaxe:
		# Mining is an overhead strike with a shorter, heavier follow-through;
		# its arc stays visually distinct from the horizontal axe swing.
		var progress := clampf(phase / 1.1, 0.0, 1.0)
		var swing := lerpf(-68.0, 42.0, smoothstep(0.0, 0.70, progress))
		if progress > 0.70: swing = lerpf(42.0, 0.0, smoothstep(0.70, 1.0, progress))
		pickaxe.rotation_degrees = tool_rotation_degrees + Vector3(swing, 0, 0)
	elif action == "build" and hammer:
		var progress := clampf(phase / 0.9, 0.0, 1.0)
		var swing := lerpf(-38.0, 24.0, smoothstep(0.0, 0.66, progress))
		if progress > 0.66: swing = lerpf(24.0, 4.0, smoothstep(0.66, 1.0, progress))
		hammer.rotation_degrees = tool_rotation_degrees + Vector3(swing, 0, 0)
	else:
		if axe: axe.rotation_degrees = tool_rotation_degrees
		if pickaxe: pickaxe.rotation_degrees = tool_rotation_degrees
		if hammer: hammer.rotation_degrees = tool_rotation_degrees
	if motion: motion.work(action, phase)

func locomotion(speed: float, dt: float) -> void:
	if not motion: return
	var clip: StringName = clips.get(state, state)
	var cycle := player.current_animation_position / maxf(0.01, player.get_animation(clip).length) if player.has_animation(clip) else 0.0
	motion.locomotion(state, cycle, speed, dt)

func ground(layout: RefCounted) -> void:
	if contact: contact.ground(layout)

func correct_work(action: String, target: Vector3, phase: float) -> void:
	if contact: contact.work(action, target, phase)

func work_tip() -> Vector3:
	return contact.tip(state) if contact and state in ["chop", "mine", "build"] else get_parent().global_position + Vector3.UP

func locomotion_reference_speed(action: String) -> float:
	var clip: StringName = clips.get(action,action)
	if player.has_animation(clip): return locomotion_stride / maxf(0.01,player.get_animation(clip).length)
	return 2.5

var outfit_signature := ""
var outfit_parts: Array[Node3D] = []

func set_outfit(inventory: Dictionary) -> void:
	saw_equipped = inventory.get("chainsaw",0) > 0 and inventory.get("saw_enabled",true)
	if not contact: return
	var signature := "%d:%d:%d" % [inventory.boots, inventory.vest, inventory.rifle]
	if outfit_signature == signature: return
	outfit_signature = signature
	for part in outfit_parts: part.free()
	outfit_parts.clear()
	if inventory.vest > 0:
		var vest := outfit_attachment("spine")
		box(vest, Vector3(.46,.39,.13), Vector3(0,.10,.17), Color("42594b") if inventory.vest == 1 else Color("475763"))
		for x in [-.14,.14]: box(vest,Vector3(.12,.15,.06),Vector3(x,.05,.255),Color("8b8b68"))
	if inventory.boots > 0:
		for side in ["L", "R"]:
			var boot := outfit_attachment("foot" + side)
			box(boot, Vector3(.15,.055,.28), Vector3(0,-.065,.045),Color("343d32"))
	if inventory.rifle > 0 and rifle:
		var scope := Node3D.new()
		rifle.add_child(scope)
		outfit_parts.append(scope)
		box(scope,Vector3(.065,.075,.26),Vector3(0,.105,.24),Color("4a5b5c"))
		box(scope,Vector3(.07,.035,.06),Vector3(0,.07,.19),Color("a49b70"))
		if inventory.rifle > 1: box(scope,Vector3(.08,.07,.16),Vector3(0,0,.78),Color("778887"))

func outfit_attachment(bone: String) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	contact.skeleton.add_child(attachment)
	outfit_parts.append(attachment)
	return attachment
