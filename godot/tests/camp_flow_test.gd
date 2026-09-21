extends SceneTree
const Board = preload("res://scripts/board.gd")
const Access = preload("res://scripts/build_access.gd")
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func corridor() -> void:
	world.board = Board.new()
	world.hero.navigation = world.board
	world.build_access = Access.new(world)
	# Two enclosed rooms with a one-cell neck. No hidden path around the fixture.
	for y in range(128):
		for x in range(128):
			if not (Rect2i(58,58,5,5).has_point(Vector2i(x,y)) or Rect2i(64,58,5,5).has_point(Vector2i(x,y)) or Vector2i(x,y) == Vector2i(63,60)):
				world.board.block_terrain(Vector2i(x,y))
	world.hero.position = world.board.point(Vector2i(61,60))
	world.extraction = world.board.point(Vector2i(67,60))
	world.session.buildings.clear()
	world.session.wood = 100
	world.session.gold = 100
	world.build_mode = "tent"

func run() -> void:
	load("res://scripts/save_store.gd").directory = "user://camp_flow_fixture"
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	corridor()
	var neck := Vector2i(63,60)
	var revision: int = world.board.revision
	var rng: int = world.rng.state
	var grid: AStarGrid2D = world.board.grid
	expect(world.placement_warning(neck).contains("撤离"), "Preview detects the only extraction route being sealed")
	expect(world.placement_warning(Vector2i(59,59)).is_empty(), "Ordinary room construction has no modal warning")
	var evaluations: int = world.build_access.evaluations
	for i in range(100): world.placement_warning(neck)
	expect(world.build_access.evaluations == evaluations, "Repeated render/HUD/pointer queries use the cache")
	expect(world.board.revision == revision and world.board.grid == grid and world.board.is_open(neck) and world.rng.state == rng, "Preview never mutates navigation or gameplay RNG")
	var tent: Dictionary = world.session.build("tent",Vector2i(66,60))
	tent.remaining = 0.0
	world.board.block_building(tent.cell,tent.id)
	expect(world.placement_warning(neck).contains("返送"), "Last reachable tent receives a specific return-route warning")
	var other: Dictionary = world.session.build("tent",Vector2i(59,60))
	other.remaining = 0.0
	world.board.block_building(other.cell,other.id)
	expect(world.placement_warning(neck).contains("撤离"), "An alternative accessible tent prevents a false total drop-off warning")
	other.hp = 0.0
	expect(world.placement_warning(neck).contains("返送"), "Live tent availability is evaluated even with cached topology")
	world.board.block_terrain(Vector2i(63,59),false)
	expect(world.placement_warning(neck).is_empty(), "Opening a real alternative route invalidates the warning")
	world.board.block_terrain(Vector2i(63,59))
	world.hero.position = world.board.point(Vector2i(65,60))
	expect(not world.placement_warning(neck).contains("返送"), "Preview follows the survivor's side of the proposed wall")
	world.hero.position = world.board.point(Vector2i(61,60))
	world.build_mode = "gate"
	expect(world.placement_warning(neck).contains("施工完成"), "Gate warning explains temporary closure and opening")
	# Sealing a tent's only approach can lose a work target without splitting open space.
	world.session.buildings.clear()
	world.board = Board.new()
	world.build_access = Access.new(world)
	world.hero.navigation = world.board
	world.hero.position = world.board.point(Vector2i(60,60))
	var alcove: Dictionary = world.session.build("tent",Vector2i(63,60))
	alcove.remaining = 0.0
	world.board.block_building(alcove.cell,alcove.id)
	for step in [Vector2i.UP,Vector2i.DOWN,Vector2i.RIGHT]: world.board.block_terrain(alcove.cell+step)
	expect(world.placement_warning(Vector2i(62,60)).contains("返送"), "Sealing the only tent approach warns even without splitting walkable space")
	# A route saved before a new obstruction must recover via real pawn collision.
	world.board = Board.new()
	world.hero.navigation = world.board
	world.hero.position = world.board.point(Vector2i(60,60)) + Vector3(0.55,0,0.55)
	var destination: Vector3 = world.board.point(Vector2i(62,60))
	world.hero.route = PackedVector3Array([destination])
	world.board.block_building(Vector2i(61,60),999)
	world.hero_route_revision = world.board.revision
	world.order = "move"
	world.order_target = destination
	var encountered_collision := false
	for i in range(150):
		world.hero.advance(1.0/30)
		encountered_collision = encountered_collision or world.hero.movement_blocked
		world.update_order(1.0/30)
	expect(encountered_collision, "Fixture encounters a real newly blocked movement segment")
	expect(world.hero.position.distance_to(destination) < 0.05 and world.hero.route.is_empty(), "Collision recovery replans and reaches destination without teleporting")
	expect(world.order == "idle", "Recovered movement finishes normally")
	var home: Vector2i = world.board.cell_at(world.hero.position)
	for x in range(-1,2):
		for y in range(-1,2):
			if x != 0 or y != 0: world.board.block_terrain(home+Vector2i(x,y))
	world.hero_route_revision = world.board.revision-1
	world.order = "move"
	world.order_target = destination+Vector3(10,0,0)
	world.update_order(0)
	expect(world.order == "idle" and world.hud.tip.text.contains("阻断"), "Topology changes that remove every route explain why movement stopped")
	for x in range(-1,2):
		for y in range(-1,2):
			if x != 0 or y != 0: world.board.block_terrain(home+Vector2i(x,y),false)
	# Target loss should stop movement now, not only after reaching the old work site.
	world.hero.route = PackedVector3Array([destination + Vector3(8,0,0)])
	world.worker.target_id = 9999
	world.order = "repair"
	world.worker.update(0.01)
	expect(world.order == "idle" and world.hero.route.is_empty(), "Lost work target cancels travel immediately")
	var repair: Dictionary = world.session.build("tent", Vector2i(63,61))
	repair.remaining = 0.0
	repair.hp = 50.0
	world.hero.position = world.board.point(Vector2i(62,61))
	world.worker.target_id = repair.id
	world.order = "repair"
	world.order_target = world.board.point(repair.cell)
	world.session.wood = 0
	world.worker.update(1)
	expect(world.order == "idle" and repair.hp == 50 and world.hud.tip.text.contains("木材不足"), "Repair stops with a concrete resource explanation")
	world.session.wood = 1
	repair.hp = 99.0
	world.order = "repair"
	world.worker.update(1)
	expect(world.order == "idle" and repair.hp == 100 and world.session.wood == 0 and world.hud.tip.text.contains("修理完成"), "Final repair tick finishes immediately and charges once")
	world.worker.update(1)
	expect(world.session.wood == 0 and repair.hp == 100, "Completed repair cannot charge another tick")
	# Costs use real segment lengths, not diagonal/straight waypoint counts.
	world.hero.position = Vector3.ZERO
	expect(world.worker.route_length(PackedVector3Array([Vector3(2,0,0),Vector3(2,0,2)])) < world.worker.route_length(PackedVector3Array([Vector3(4,0,4)])), "Drop-off scoring compares travelled distance rather than waypoint count")
	world.free()
	print("CAMP FLOW: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
