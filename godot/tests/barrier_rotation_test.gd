extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func new_world() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500, "standard")

func cell() -> Vector2i:
	for y in range(59,70):
		for x in range(59,71):
			var c := Vector2i(x,y)
			if world.board.can_build(c) and world.board.point(c).distance_to(world.hero.position)>2: return c
	return Vector2i(-1,-1)

func add_building(kind: String, angle: float = 0.0) -> Dictionary:
	var c := cell()
	expect(c.x >= 0, "Fixture uses legal free terrain")
	var b: Dictionary = world.session.build(kind,c,angle)
	expect(not b.is_empty(), "Fixture pays real building costs")
	if b.is_empty(): return b
	b.remaining = 0.0
	world.board.block_building(c,b.id)
	world.create_building_visual(b)
	return b

func run() -> void:
	Save.directory = "user://barrier_rotation_fixture"
	new_world()
	world.prepare_demo()
	world.session.wood = 1000
	world.session.gold = 1000
	add_building("generator")
	add_building("generator")
	for kind in ["shelter","gate"]:
		world.select_build(kind)
		world.hover_cell = cell()
		var revision: int = world.board.revision
		var stock := Vector2i(world.session.wood,world.session.gold)
		for i in range(4):
			world.rotate_building_preview()
			expect(is_equal_approx(world.build_rotation,fposmod((i+1)*PI*.5,TAU)), "Preview advances by a quarter turn")
			expect(world.barrier_preview.visible and world.barrier_preview.basis.is_equal_approx(Basis(Vector3.UP,world.build_rotation)), "Actual preview model follows selected orientation")
		expect(world.board.revision==revision and stock==Vector2i(world.session.wood,world.session.gold), "Preview never alters collision or stock")
		world.paused = true
		world.rotate_building_preview()
		expect(is_zero_approx(world.build_rotation), "Paused game ignores rotation")
		world.paused = false
		for i in range(4):
			var b := add_building(kind,i*PI*.5)
			if b.is_empty(): continue
			var node: Node3D = world.visuals[b.id]
			expect(node.basis.is_equal_approx(Basis(Vector3.UP,i*PI*.5)), "Built orientation matches requested orientation")
			expect(not world.board.is_open(b.cell), "Rotated barrier blocks its existing cell")
			if kind=="gate":
				world.toggle_gate(b)
				world.update_gate(b,5)
				expect(b.get("open",false) and world.board.is_open(b.cell), "Rotated gate opens a navigable passage")
				expect(is_equal_approx(node.get_node("Model/Leaf").rotation.y,-PI*.48), "Gate leaf swings in its own local coordinates")
				world.toggle_gate(b)
				world.update_gate(b,5)
				expect(not b.open and not world.board.is_open(b.cell), "Rotated gate closes passage")
				expect(node.basis.is_equal_approx(Basis(Vector3.UP,i*PI*.5)), "Opening does not overwrite building orientation")
	var gate: Dictionary = world.session.buildings.back()
	world.toggle_gate(gate)
	world.update_gate(gate,5)
	world.session.refit(gate.id,"brace")
	world.session.tick(12)
	world.update_buildings(0)
	expect(world.visuals[gate.id].basis.is_equal_approx(Basis(Vector3.UP,gate.rotation)), "Reinforcement preserves orientation")
	world.build_mode=""
	world.update_build_preview()
	expect(not world.barrier_preview.visible, "Cancel removes model preview")
	var snapshot := Save.snapshot(world)
	expect(Save.validate(snapshot).is_empty(), "All rotations validate in saves")
	expect(Save.write(world).is_empty(), "Rotated barriers save to disk")
	var slot := Save.read_slot("manual")
	expect(slot.has("data"), "Rotated barrier save can be read back")
	if slot.has("data"):
		snapshot = slot.data
		expect(is_equal_approx(snapshot.session.buildings.back().rotation,gate.rotation), "Serialization preserves the chosen orientation")
	for bad_value in ["north", -1.0, 0.4, TAU, INF, NAN, true]:
		var invalid := snapshot.duplicate(true)
		invalid.session.buildings.back().rotation=bad_value
		expect(not Save.validate(invalid).is_empty(), "Invalid save orientation rejected")
	var legacy := snapshot.duplicate(true)
	for b in legacy.session.buildings: b.erase("rotation")
	expect(Save.validate(legacy).is_empty(), "Old saves with no rotation remain valid")
	world.free()
	new_world()
	Save.apply(world,snapshot)
	for b in world.session.buildings:
		if b.kind not in ["gate","shelter"]: continue
		expect(world.visuals[b.id].basis.is_equal_approx(Basis(Vector3.UP,b.get("rotation",0.0))), "Reload restores barrier orientation")
		if b.kind=="gate" and b.get("open",false):
			expect(world.board.is_open(b.cell) and is_equal_approx(world.visuals[b.id].get_node("Model/Leaf").rotation.y,-PI*.48), "Reload restores open rotated gate and navigation")
	world.free()
	new_world()
	Save.apply(world,legacy)
	for b in world.session.buildings:
		if b.kind in ["gate","shelter"]: expect(world.visuals[b.id].basis.is_equal_approx(Basis.IDENTITY), "Legacy barrier defaults to original direction")
	world.free()
	print("BARRIER ROTATION: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
