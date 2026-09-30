extends SceneTree
const Board = preload("res://scripts/board.gd")
const Pawn = preload("res://scenes/models/survivor.tscn")
const Data = preload("res://scripts/terrain_data.gd")
var checks := 0
var failures := 0

class Slope extends RefCounted:
	func height_at(x: float, z: float) -> float: return x * 0.20 + z * 0.08

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var board := Board.new()
	var start := Vector3(1,0,1)
	var end := Vector3(1,0,11)
	for z in range(-3, 9):
		for x in [-1, 1]: board.block_terrain(board.cell_at(Vector3(1+x*2,0,1+z*2)))
	expect(board.body_open(start, 0.48) and not board.body_open(start, 1.12), "Raptor fits a 2m corridor; adult tyrannosaur does not")
	expect(not board.route(start,end,false,0.48).is_empty(), "Small dinosaurs retain narrow-corridor routes")
	expect(board.route(start,end,false,1.12).is_empty(), "Large actors cannot be routed through undersized corridor")
	board = Board.new()
	var obstacle := board.cell_at(Vector3(5,0,1))
	board.block_building(obstacle, 1)
	var path := board.route(start,Vector3(11,0,1),false,1.12)
	expect(not path.is_empty(), "Adult can detour around an isolated building")
	var previous := start
	var clear_path := true
	for point in path:
		clear_path = clear_path and board.body_segment_open(previous,point,1.12)
		previous = point
	expect(clear_path, "Every large-body detour segment clears the building corners")
	var bite := board.route(start,Vector3(5,0,1),true,1.12)
	expect(not bite.is_empty() and bite[-1].distance_to(Vector3(5,0,1)) <= 3, "Body clearance still permits reaching the existing bite range")
	var revision := board.revision
	board.remove_building(obstacle)
	expect(board.revision > revision and board.route(start,Vector3(11,0,1),false,1.12).size() < path.size(), "Opening a gate invalidates inflated navigation cache")
	board.block_building(obstacle, 1)
	expect(not board.body_segment_open(Vector3(3.8,0,-1),Vector3(3.8,0,3),0.3), "Swept body stops a centerline that clips a wall edge")
	expect(board.body_segment_open(Vector3(3,0,1),Vector3(2.7,0,1),1.12), "Old overlapping saves may move out of a clearance overlap")
	expect(not board.body_segment_open(Vector3(3,0,1),Vector3(3.2,0,1),1.12), "Old overlaps cannot move deeper into obstacles")
	var pawn: Node3D = Pawn.instantiate()
	root.add_child(pawn)
	pawn.navigation = Board.new()
	pawn.navigation.layout = Slope.new()
	pawn.advance(0.1)
	var contact = pawn.visual.contact
	for side in ["L", "R"]:
		var foot: Vector3 = contact.skeleton.to_global(contact.pose("foot"+side).origin)
		var ground: float = pawn.navigation.layout.height_at(foot.x, foot.z)
		expect(absf(foot.y - ground - 0.15) < 0.025, "Slope IK plants " + side + " foot at terrain height")
		var shin: Transform3D = contact.pose("shin"+side)
		var rest: Vector3 = contact.skeleton.get_bone_rest(contact.bones["foot"+side]).origin
		expect((shin*rest).distance_to(contact.pose("foot"+side).origin) < 0.001, "Slope IK preserves connected lower leg " + side)
	expect(pawn.position == Vector3.ZERO, "Grounding never moves gameplay position")
	for heading in [0.0, PI/2, PI, PI*1.5]:
		pawn.visual.model.rotation.y = heading
		var planted := true
		var joined := true
		for frame in range(25):
			pawn.visual.play("walk",0)
			pawn.visual.player.seek(float(frame)/30,true)
			pawn.visual.ground(pawn.navigation.layout)
			var lowest := INF
			for side in ["L","R"]:
				var foot: Vector3 = contact.skeleton.to_global(contact.pose("foot"+side).origin)
				lowest = minf(lowest,foot.y-pawn.navigation.layout.height_at(foot.x,foot.z))
				var rest: Vector3 = contact.skeleton.get_bone_rest(contact.bones["foot"+side]).origin
				joined = joined and (contact.pose("shin"+side)*rest).distance_to(contact.pose("foot"+side).origin) < 0.001
			planted = planted and absf(lowest-0.146) < 0.035
		expect(planted, "Slope walk keeps a support foot for the full stride at heading " + str(heading))
		expect(joined, "Slope walk keeps both lower legs connected at heading " + str(heading))
	pawn.navigation.layout = null
	pawn.visual.model.rotation.y = 0
	pawn.visual.model.position.y = 0
	for fixture in [["chop",1.34,1.1,Vector3(0,1.25,1.04)], ["mine",1.5,1.1,Vector3(0,0.34,0.85)], ["build",1.7,0.65,Vector3(0,1.15,0.85)]]:
		pawn.work_pose(fixture[0],Vector3(0,0,fixture[1]),fixture[2],1)
		var tip: Vector3 = pawn.visual.work_tip()
		expect(tip.distance_to(fixture[3]) < 0.12, fixture[0] + " tool head meets the calibrated near surface")
		for chain in [["upper_armR","forearmR"],["forearmR","handR"]]:
			var rest: Vector3 = contact.skeleton.get_bone_rest(contact.bones[chain[1]]).origin
			expect((contact.pose(chain[0])*rest).distance_to(contact.pose(chain[1]).origin) < 0.001, fixture[0] + " IK does not stretch or disconnect arm bones")
		pawn.work_pose(fixture[0],Vector3(0,0,fixture[1]),fixture[2],1)
		expect(pawn.visual.work_tip().distance_to(tip) < 0.001, "Repeated animation evaluation must not accumulate correction")
	for action in ["chop", "mine", "build"]:
		pawn.visual.show_equipment(action, false, "")
		expect(pawn.visual.axe.visible == (action == "chop") and pawn.visual.pickaxe.visible == (action == "mine") and pawn.visual.hammer.visible == (action == "build") and not pawn.visual.chainsaw.visible, action + " shows only its matching tool")
	pawn.visual.saw_equipped = true
	pawn.work_pose("chop",Vector3(0,0,1.36),1.1,1)
	expect(pawn.visual.chainsaw.visible and not pawn.visual.axe.visible and not pawn.visual.hammer.visible, "Equipped chainsaw replaces the axe without a duplicate tool")
	var actual_saw_tip: Vector3 = contact.skeleton.to_global(contact.pose("handR") * pawn.visual.get_node(pawn.visual.hand_socket_path).transform * pawn.visual.chainsaw.transform * Vector3(0,0,.88))
	expect(actual_saw_tip.distance_to(pawn.visual.work_tip()) < .001, "Chainsaw impact follows its own cutting bar rather than the hidden axe")
	pawn.visual.saw_equipped = false
	pawn.advance(0.3)
	expect(pawn.animation_state == "idle" and not pawn.visual.axe.visible, "Work corrections release with the work state")
	pawn.free()
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500,"standard")
	var effects: int = world.effects.size()
	world.tracer(Vector3.ZERO,Vector3.ZERO,Color.WHITE)
	expect(world.effects.size() == effects, "Zero-length impact tracer produces no invalid geometry")
	world.tracer(Vector3.ZERO,Vector3.UP,Color.WHITE)
	expect(world.effects[-1].node.transform.basis.is_finite(), "Vertical contact tracer has a stable orientation")
	var rock_meshes: int = world.scenery.obstructions.meshes
	expect(rock_meshes > 0, "Imported island rocks register for camera occlusion")
	var b: Dictionary = world.session.build("tent", Vector2i(63,62))
	b.remaining = 0
	world.board.block_building(b.cell,b.id)
	world.create_building_visual(b)
	var converted := 0
	for mesh in world.visuals[b.id].find_children("*","MeshInstance3D",true,false):
		if mesh.get_active_material(0) is ShaderMaterial and mesh.get_active_material(0).shader == world.scenery.obstructions.ShaderSource:
			converted += 1
			expect(mesh.material_overlay == null, "Fog overlay cannot fill camera aperture")
	expect(converted > 0 and world.scenery.obstructions.meshes > rock_meshes, "Buildings use integrated fog and camera cutout")
	world.update_camera(0)
	for mat in world.scenery.obstructions.materials.values():
		expect(mat.get_shader_parameter("visibility_map") == world.vision.texture, "Cutout retains real visibility texture")
		break
	# A real adult attacks a barrier after taking a width-aware path, without changing bite reach.
	world.board = Board.new()
	world.board.layout = Data.new()
	world.board.layout.heights.fill(0)
	world.board.layout.rebuild_surface()
	world.trees.clear()
	world.session.buildings.clear()
	world.hero.position = Vector3(81,0,81)
	world.hero.navigation = world.board
	world.session.wood = 1000
	world.session.gold = 1000
	b = world.session.build("tent",world.board.cell_at(Vector3(9,0,1)))
	b.remaining = 0
	world.board.block_building(b.cell,b.id)
	var d: Node3D = world.spawn_dinosaur(Vector3(1,0,1),"trex")
	world.dino_ai.provoke(d,"building",b.id,world.board.point(b.cell))
	var hp: float = b.hp
	for i in range(300): world.dino_ai.update(1.0/30)
	expect(b.hp < hp, "Adult still reaches and damages a blocking camp building")
	expect(world.board.body_open(d.position,d.body_radius), "Adult attacks without penetrating the structure footprint")
	world.free()
	print("CONTACT CHECKS ",checks,"; ",failures," failures")
	quit(0 if failures == 0 else 1)
