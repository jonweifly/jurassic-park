extends SceneTree
const Pawn = preload("res://scripts/pawn.gd")
const Visual = preload("res://scripts/pawn_visual.gd")
var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func skeleton_fixture() -> Node3D:
	var pawn := Pawn.new()
	var body := Node3D.new()
	body.name = "Body"
	pawn.add_child(body)
	var rig := Skeleton3D.new()
	rig.name = "Rig"
	rig.add_bone("root")
	rig.add_bone("right_hand")
	rig.set_bone_parent(1,0)
	rig.set_bone_rest(1,Transform3D(Basis.IDENTITY,Vector3(0.4,1.4,0)))
	body.add_child(rig)
	var hand := BoneAttachment3D.new()
	hand.name = "Grip"
	hand.bone_name = "right_hand"
	rig.add_child(hand)
	var cargo := Marker3D.new()
	cargo.name = "Load"
	body.add_child(cargo)
	var animator := AnimationPlayer.new()
	animator.name = "Motion"
	var library := AnimationLibrary.new()
	for name in ["Rest","Walk","Work","Carry","Dead"]:
		var clip := Animation.new()
		clip.length = 1.35
		var track := clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(track,NodePath("Body:position:y"))
		clip.track_insert_key(track,0,0.0)
		clip.track_insert_key(track,1.35,0.03)
		library.add_animation(name,clip)
	animator.add_animation_library("Imported",library)
	pawn.add_child(animator)
	var visual := Visual.new()
	visual.name = "Visual"
	visual.model_path = NodePath("../Body")
	visual.animator_path = NodePath("../Motion")
	visual.hand_socket_path = NodePath("../Body/Rig/Grip")
	visual.cargo_socket_path = NodePath("../Body/Load")
	visual.rifle_path = NodePath("../NoRifle")
	visual.tool_grip = Vector3.ZERO
	visual.cargo_origin = Vector3.ZERO
	visual.work_equipment = true
	visual.clips = {"idle":"Imported/Rest","walk":"Imported/Walk","chop":"Imported/Work","mine":"Imported/Work","build":"Imported/Work","carry_idle":"Imported/Carry","death":"Imported/Dead"}
	pawn.add_child(visual)
	return pawn

func run() -> void:
	var pawn := skeleton_fixture()
	root.add_child(pawn)
	pawn.advance(0.1)
	expect(pawn.animation_state == "idle" and pawn.visual.player.current_animation == "Imported/Rest", "Logical actions must map to imported animation-library names")
	pawn.work_pose("mine",Vector3(4,0,0),1.1,0.1)
	expect(pawn.visual.pickaxe.visible and not pawn.visual.hammer.visible and not pawn.visual.axe.visible, "Mining must use a separate pickaxe")
	expect(pawn.visual.pickaxe.get_parent() is BoneAttachment3D, "Equipment must attach to a configured skeleton socket without primitive limb names")
	expect(pawn.visual.model.rotation.y > 0.5, "Facing must rotate the configured model root")
	expect(absf(pawn.visual.player.current_animation_position-1.1) < 0.001, "Work impact seeking must reach the imported clip at the gameplay contact time")
	pawn.carrying = true
	pawn.cargo_kind = "gold"
	pawn.advance(0.2)
	expect(pawn.visual.ore.visible and not pawn.visual.bundle.visible, "Mineral cargo must use its own prop")
	pawn.cargo_kind = "wood"
	pawn.advance(0.1)
	expect(pawn.visual.bundle.visible and not pawn.visual.ore.visible, "Wood cargo must switch back without duplicating props")
	pawn.health = 0
	pawn.advance(0.1)
	expect(pawn.animation_state == "death" and not pawn.visual.bundle.visible and not pawn.visual.pickaxe.visible, "Death must release work and carry equipment")
	pawn.free()
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	var forest: RefCounted = world.scenery.forest
	expect(forest.source_parts > 10000 and forest.batches.size() < forest.source_parts / 4, "Original forest must use substantially fewer spatial render batches")
	expect(forest.cells.size() == world.trees.size(), "Each harvestable cell must own render slots")
	if forest.cells.size() != world.trees.size():
		world.queue_free()
		await process_frame
		quit(1)
		return
	var snapshots := []
	var originals_hidden := true
	for cell in world.trees:
		for part in world.trees[cell].node.find_children("*","MeshInstance3D",true,false): originals_hidden = originals_hidden and not part.visible
		for slot in forest.cells[cell]: snapshots.append({"slot":slot,"transform":forest.batches[slot.batch].multi.get_instance_transform(slot.index)})
	expect(originals_hidden, "Editable source trees must not render twice")
	var initial_count: int = forest.live_parts()
	var removed := {}
	var removed_count := 0
	var cells: Array = world.trees.keys()
	# Spread removals across many batches, including cells with several trees.
	for i in range(0,cells.size(),19):
		var cell: Vector2i = cells[i]
		removed_count += forest.cells[cell].size()
		removed[cell] = true
		world.clear_tree(cell)
	expect(forest.live_parts() == initial_count-removed_count, "Harvesting must remove every component exactly once")
	var preserved := true
	for record in snapshots:
		var slot: Dictionary = record.slot
		if removed.has(slot.cell): continue
		var batch: Dictionary = forest.batches[slot.batch]
		preserved = preserved and slot.index < batch.multi.visible_instance_count and batch.multi.get_instance_transform(slot.index).is_equal_approx(record.transform)
	expect(preserved, "Swap-removal must preserve all surviving tree transforms and updated indices")
	for cell in world.trees.keys(): world.clear_tree(cell)
	expect(forest.live_parts() == 0 and forest.cells.is_empty(), "Repeated harvests must eventually empty all render batches")
	expect(forest.batches.all(func(b): return b.multi.visible_instance_count == 0 and not b.node.visible), "Empty batches must stop rendering and casting shadows")
	world.hero.position += Vector3(2,0,0)
	world.update_camera(0.1)
	var leaf: ShaderMaterial = world.scenery.foliage_cache.values()[0]
	expect(leaf.get_shader_parameter("actor_focus") == world.scenery.leaf_fog.get_shader_parameter("actor_focus"), "Canopy and fog must cut out around the same survivor position")
	expect(leaf.get_shader_parameter("camera_axis").is_equal_approx(world.camera.global_basis.z.normalized()), "Canopy cutout must follow camera rotation")
	world.hero.health = 0
	world.update_camera(0.1)
	expect(leaf.get_shader_parameter("cutout_enabled") == 0.0, "Dead survivor must not leave an active canopy cutout")
	world.queue_free()
	await process_frame
	print("VISUAL PIPELINE: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
