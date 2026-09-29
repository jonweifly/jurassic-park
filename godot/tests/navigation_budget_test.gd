extends SceneTree
const Board = preload("res://scripts/board.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var board := Board.new()
	# Two large disconnected regions reproduce late-wave searches for inaccessible targets.
	for y in range(Board.SIDE): board.block_building(Vector2i(64,y),y+1)
	for radius in [0.48,1.12,1.28]:
		var start := board.point(Vector2i(90,38))
		var target := board.point(Vector2i(47,49))
		expect(board.route(start,target,true,radius).is_empty(), "Sealed barrier stays impassable for body radius " + str(radius))
		var t := Time.get_ticks_usec()
		for i in range(56):
			expect(board.route(start+Vector3(0,0,i%4*2),target,true,radius).is_empty(), "Crowd cannot cross sealed barrier")
		var ms := (Time.get_ticks_usec()-t)/1000.0
		print("NAVIGATION BUDGET radius=",radius," 56 unreachable requests=",ms," ms")
		expect(ms < 100, "Cached unreachable crowd requests fit 100 ms batch budget (was %.1f ms)" % ms)
	# Gate/obstacle changes invalidate reachability for both small and large bodies.
	for y in range(37,42): board.remove_building(Vector2i(64,y))
	for radius in [0.48,1.12,1.28]:
		expect(not board.route(board.point(Vector2i(90,38)),board.point(Vector2i(47,49)),true,radius).is_empty(), "Opening gate immediately restores reachable route")
	for y in range(37,42): board.block_building(Vector2i(64,y),y+1)
	expect(board.route(board.point(Vector2i(90,38)),board.point(Vector2i(47,49)),true,1.12).is_empty(), "Closing gate invalidates open route")
	var source := Vector2i(70,70)
	board.block_building(source,1000)
	expect(not board.route(board.point(source),board.point(Vector2i(75,70)),false,.48).is_empty(), "Actor restored into a newly blocked cell can still depart")
	expect(not board.is_open(source), "Departure leaves blocked source collision intact")
	var gate := Vector2i(64,38)
	expect(not board.route(board.point(gate),board.point(Vector2i(75,38))).is_empty(), "Blocked gate occupant can depart into either component")
	expect(board.route(board.point(Vector2i(75,38)),board.point(Vector2i(55,38))).is_empty(), "Temporary departure does not join cached components through a closed gate")
	board.remove_building(gate)
	board.block_terrain(gate)
	expect(board.route(board.point(Vector2i(75,38)),board.point(Vector2i(55,38))).is_empty(), "Terrain still closes an opening after demolition")
	board.block_terrain(gate, false)
	expect(not board.route(board.point(Vector2i(75,38)),board.point(Vector2i(55,38))).is_empty(), "Clearing terrain invalidates unreachable component cache")
	var corner := Board.new()
	for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]: corner.block_terrain(source + offset)
	expect(corner.route(corner.point(source),corner.point(source+Vector2i(2,2))).is_empty(), "An open diagonal cannot cut blocked corners")
	print("NAVIGATION BUDGET: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
