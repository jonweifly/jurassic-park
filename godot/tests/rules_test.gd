extends SceneTree
const Session = preload("res://scripts/session.gd")
const Board = preload("res://scripts/board.gd")
var failures := 0
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var s = Session.new()
	expect(s.gold == 10, "6.5 opening gold is 10")
	var before := Vector2i(s.wood, s.gold)
	expect(s.build("tower", Vector2i(1, 1)).is_empty(), "Unpowered tower must be refused")
	expect(Vector2i(s.wood, s.gold) == before, "Refused construction must not charge resources")
	var tent: Dictionary = s.build("tent", Vector2i.ZERO)
	expect(not tent.is_empty() and s.gold == 10 and s.wood == 0, "Initial tent is free")
	s.tick(10)
	expect(tent.remaining == 10, "A construction site must not progress without its worker")
	s.work(tent.id, 10)
	s.wood = 10
	var generator: Dictionary = s.build("generator", Vector2i(2, 2))
	expect(not generator.is_empty(), "Starter resources must allow a generator")
	expect(s.supply() == 0, "Unfinished generator must not supply electricity")
	s.work(generator.id, 10.0)
	expect(s.supply() == 5, "Completed generator must supply electricity")
	s.wood = 1000
	s.gold = 1000
	for i in range(5): expect(not s.build("tower", Vector2i(i + 3, 2)).is_empty(), "Available electricity should allow tower")
	expect(s.demand() == 5, "Unfinished consumers reserve electricity")
	expect(s.build("tower", Vector2i(15, 2)).is_empty(), "Reserved electricity cannot be spent twice")
	generator.hp = 0
	expect(s.supply() == 0 and s.demand() == 5, "Destroyed generator must cause a real outage")
	expect(not s.build("generator", Vector2i(2, 3)).is_empty(), "Player must be able to recover from an outage")
	s.tick(10)
	s.buildings[2].hp = 0
	expect(s.demand() == 4, "Destroyed consumer must release electricity")
	var poor = Session.new()
	poor.build("tent", Vector2i.ZERO)
	poor.work(poor.buildings[0].id, 10)
	poor.wood = 0
	expect(poor.build("fire", Vector2i(1, 0)).is_empty(), "Unaffordable construction refused")
	expect(not poor.research().is_empty(), "Upgrade requires a selected completed basic building")
	s.elapsed = s.duration - 1
	s.tick(2)
	expect(s.phase == "evacuate", "Survival timer unlocks evacuation, not an automatic victory")
	expect(s.build("fire", Vector2i(1, 2)).is_empty(), "No construction after evacuation begins")
	s.tick(300)
	expect(s.phase == "lost", "Missing the 5 minute extraction window loses the game")
	var board = Board.new()
	var a: Vector3 = board.point(Vector2i(4, 4))
	var b: Vector3 = board.point(Vector2i(8, 4))
	expect(board.cell_at(a) == Vector2i(4, 4), "Grid coordinates must round trip")
	for y in range(Board.SIDE): board.block_terrain(Vector2i(6, y))
	expect(board.route(a, b).is_empty(), "Impassable terrain must stop paths")
	board.block_terrain(Vector2i(6, 4), false)
	expect(not board.route(a, b).is_empty(), "Cutting a tree opens a route")
	board.block_building(Vector2i(6, 4), 1)
	expect(board.route(a, b).is_empty(), "A building must seal a choke point")
	board.remove_building(Vector2i(6, 4))
	expect(not board.route(a, b).is_empty(), "Destroyed building reopens a route")
	board.block_terrain(Vector2i(8, 4))
	var adjacent: PackedVector3Array = board.route(a, b, true)
	expect(not adjacent.is_empty(), "Harvest command must route to blocked resource's neighbor")
	for p in adjacent: expect(board.is_open(board.cell_at(p)), "A route must not contain blocked cells")
	var Regions = load("res://scripts/regions.gd")
	expect(Regions.at(Vector3(50, 0, -50)) == "mountain", "Warcraft north must map to negative Godot Z")
	# The approved organic v3 map intentionally ships three authored biomes;
	# northwest remains rainforest instead of importing the old reference ice.
	expect(Regions.at(Vector3(-50, 0, -50)) == "rainforest", "Northwest remains rainforest on the organic map")
	expect(Regions.at(Vector3(-50, 0, 50)) == "rainforest", "Southwest is rainforest")
	expect(Regions.at(Vector3(50, 0, 50)) == "swamp", "Southeast is swamp")
	expect(Regions.at(Vector3.ZERO) == "center", "Central gaps must not be filled with quadrant bonuses")
	expect(Regions.construction_remaining("tent", Vector3(50, 0, 50), 10) == 3, "Swamp begins eligible construction at 70 percent")
	expect(Regions.construction_remaining("tower", Vector3(50, 0, 50), 18) == 18, "Swamp bonus must respect original building whitelist")
	print("RULES: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
