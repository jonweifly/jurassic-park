extends SceneTree
const Board = preload("res://scripts/board.gd")
const Pawn = preload("res://scenes/models/survivor.tscn")
var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func move_fixture(dt: float) -> Node3D:
	var pawn = Pawn.instantiate()
	root.add_child(pawn)
	pawn.navigation = Board.new()
	pawn.position = Vector3(1,0,1)
	pawn.route = PackedVector3Array([Vector3(3,0,1),Vector3(5,0,1),Vector3(7,0,1),Vector3(9,0,1)])
	for i in range(roundi(1.0/dt)): pawn.advance(dt)
	return pawn

func run() -> void:
	var slow := move_fixture(1.0/30)
	var fast := move_fixture(1.0/120)
	expect(slow.position.distance_to(fast.position) < 0.005, "Waypoint traversal must retain leftover distance independently of tick rate")
	expect(slow.position.x > 5.5 and slow.position.x < 6, "Short acceleration must preserve expected travel speed")
	var before_slowdown: float = fast.position.x
	fast.speed = 3
	fast.advance(0.05)
	expect(fast.position.x - before_slowdown > 0.15 and fast.position.x - before_slowdown < 0.25, "A region speed reduction must integrate positive deceleration time")
	for i in range(120): slow.advance(1.0/30)
	expect(slow.position.distance_to(Vector3(9,0,1)) < 0.001 and slow.route.is_empty(), "Final waypoint must stop without overshoot")
	slow.position = Vector3(1,0,1)
	slow.current_speed = 5
	slow.route = PackedVector3Array([Vector3(9,0,1)])
	slow.navigation.block_terrain(slow.navigation.cell_at(Vector3(3,0,1)))
	slow.advance(1)
	expect(slow.position.x < 2 and slow.route.is_empty(), "A long tick cannot tunnel through a newly blocked cell")
	slow.navigation = Board.new()
	slow.navigation.block_terrain(slow.navigation.cell_at(Vector3(3,0,1)))
	expect(not slow.segment_open(Vector3(1,0,1),Vector3(3,0,3)), "Diagonal movement cannot clip the blocked corner")
	slow.speed = 0
	slow.route = PackedVector3Array([Vector3(9,0,1)])
	slow.advance(1)
	expect(slow.position == Vector3(1,0,1), "Stationary units remain stationary")
	slow.work_pose("chop",Vector3(1,0,3),0.85,0.1)
	var skeleton: Skeleton3D = slow.get_node("Model/Rig/Skeleton3D")
	var raised: Quaternion = skeleton.get_bone_pose_rotation(skeleton.find_bone("upper_armR"))
	slow.work_pose("chop",Vector3(1,0,3),1.1,0.1)
	expect(raised.angle_to(skeleton.get_bone_pose_rotation(skeleton.find_bone("upper_armR"))) > 1, "Chop must have distinct windup and impact poses")
	expect(slow.visual.axe.visible and not slow.visual.hammer.visible and not slow.visual.rifle.visible, "Work tool must replace the rifle")
	slow.work_pose("build",Vector3(1,0,3),0.65,0.1)
	expect(slow.visual.hammer.visible and not slow.visual.axe.visible, "Construction must use a hammer")
	slow.route.clear()
	slow.carrying = true
	slow.advance(0.2)
	expect(slow.animation_state == "carry_idle" and slow.visual.bundle.visible and not slow.visual.hammer.visible, "Work must release to a carrying pose without leaving tools active")
	slow.free()
	fast.free()
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(3600)
	world.spawn_clocks.clear()
	world.camera_rig.center(false) # This section measures free-camera panning.
	var initial: Vector3 = world.camera_rig.focus
	world.camera_focus += Vector3(16,0,0)
	for i in range(30): world.update_camera(1.0/30)
	var at_30: Vector3 = world.camera.position
	world.camera_focus = initial
	world.update_camera(0)
	world.camera_focus += Vector3(16,0,0)
	for i in range(120): world.update_camera(1.0/120)
	expect(world.camera.position.distance_to(at_30) < 0.01, "Camera smoothing must be independent of frame rate")
	world.camera_rig.center(true)
	world.hero.position.x += 2
	world.hero.position.y = world.board.layout.height_at(world.hero.position.x,world.hero.position.z)
	world.update_camera(0.1)
	expect(world.camera_focus.x == world.hero.position.x, "Follow must track the moving survivor")
	world.camera_rig.pan(Vector2.RIGHT,0.1)
	expect(not world.camera_rig.following, "Manual pan must release follow")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	for i in range(100): world.camera_rig.handle(wheel)
	expect(world.camera_size == 18, "Zoom-in must have a useful finite limit")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for i in range(100): world.camera_rig.handle(wheel)
	expect(world.camera_size == 68, "Zoom-out must have a finite limit")
	world.camera_rig.target_yaw += PI/2
	world.camera_rig.target_pitch = deg_to_rad(38)
	world.update_camera(0)
	await physics_frame
	var hit: Vector3 = world.ground_at(world.camera.unproject_position(world.hero.position))
	expect(hit.distance_to(world.hero.position) < 0.15, "Rotated low-angle camera must still pick actual terrain")
	world.camera_rig.reset()
	world.update_camera(0)
	expect(world.camera_size == 36 and is_equal_approx(world.camera_rig.yaw,PI/4), "Reset must restore predictable framing")
	var leaves: Array = world.get_node("Island").find_children("Crown","MeshInstance3D",true,false)
	expect(not leaves.is_empty(), "Leaf shader fixtures must exist")
	if not leaves.is_empty():
		expect(leaves[0].material_overlay.get_shader_parameter("visibility_map") == world.vision.texture and is_equal_approx(leaves[0].material_overlay.get_shader_parameter("strength"), leaves[0].material_override.get_shader_parameter("strength")), "Animated foliage visibility must use matching wind displacement")
	expect(world.get_node("Island/GroundCover").get_child_count() > 0, "Ground cover must be batched into visible spatial chunks")
	# A real gathering cycle: no cargo before contact, recovery before departure.
	world.camera_rig.center()
	var found := false
	for cell in world.trees:
		var target: Vector3 = world.board.point(cell)
		# A generic adjacent route may legitimately end at the current cell when
		# the tree is enclosed by terrain.  Use the worker's real cardinal
		# contact route so this fixture only selects trees the player can harvest.
		var route: PackedVector3Array = world.worker.wood_route(target)
		if route.is_empty() or route.size() > 8: continue
		world.hero.position = route[route.size()-1]
		world.hero.route.clear()
		world.worker.assign("wood",target)
		world.hero.route.clear()
		world.worker.update(0.8)
		expect(world.worker.cargo == 0 and world.hero.animation_state == "chop", "Gathering must wind up before crediting carried resources")
		world.worker.update(0.31)
		expect(world.worker.cargo == 1 and world.worker.recovery > 0 and world.order == "wood", "Resource contact must happen once and retain recovery pose")
		world.worker.update(0.1)
		expect(world.worker.cargo == 1, "Recovery cannot duplicate resource collection")
		world.worker.update(0.2)
		expect(world.order == "waiting_dropoff" and world.worker.cargo == 1, "Completed recovery must preserve cargo when no tent exists")
		found = true
		break
	expect(found,"Reachable harvesting fixture must exist")
	world.queue_free()
	await process_frame
	print("POLISH: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
