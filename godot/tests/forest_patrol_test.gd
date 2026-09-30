extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.start_session(4800,"standard")
	w.rng.seed = 80
	for i in range(16):
		var d: Node3D = w.dino_ai.spawn_patrol(["raptor","young_trex","trex"][i%3])
		check(d != null and w.dino_ai.state(d) == "patrol","Mixed pack receives a reachable forest patrol")
	var arrived := {}
	var max_turn := 0.0
	for frame in range(1800):
		w.crowd.rebuild(w.survivors()+w.dinosaurs)
		w.crowd.separate(1.0/30)
		for d in w.dinosaurs:
			var before: float = d.visual.model.rotation.y
			d.set_meta("ai_sense_clock",999.0)
			w.dino_ai.update_one(d,1.0/30)
			max_turn = maxf(max_turn,absf(angle_difference(before,d.visual.model.rotation.y)))
			if d.position.distance_to(w.hero.position) < 10: arrived[d.get_instance_id()] = true
	print("FOREST arrived=",arrived.size(),"/16 max turn/frame=",rad_to_deg(max_turn))
	check(arrived.size() >= 12,"Forest and crowd collisions must not strand most of the incoming pack")
	check(max_turn <= deg_to_rad(12.01),"Crowded forest patrols retain bounded facing")
	for d in w.dinosaurs: d.free()
	w.dinosaurs.clear()
	for i in range(36):
		var d: Node3D = w.spawn_dinosaur(w.hero.position,"raptor")
		d.set_meta("ai_state","idle")
	w.director.spawn_group(["raptor","raptor"])
	check(w.dinosaurs.size() == 36,"Full population does not exceed cap")
	check(w.dinosaurs.any(func(d): return w.dino_ai.state(d) == "patrol"),"Standard mode reuses idle animals when population is full")
	# Real tree-clear action opens static navigation; buildings stay intact.
	var layout: RefCounted = w.board.layout
	w.board = preload("res://scripts/board.gd").new()
	w.board.layout = layout
	w.trees = {}
	var tree_cell := Vector2i(64,64)
	var tree_node := Node3D.new()
	w.add_child(tree_node)
	w.trees[tree_cell] = {"node":tree_node,"wood":20}
	w.board.block_terrain(tree_cell)
	w.board.block_building(Vector2i(67,64),999)
	var breaker: Node3D = w.spawn_dinosaur(Vector3(-1.2,layout.height_at(-1.2,1),1),"trex")
	breaker.route = PackedVector3Array([w.board.point(Vector2i(66,64))])
	check(w.dino_ai.forest.clearing(breaker,.6) and w.trees.has(tree_cell),"Heavy dinosaur spends time breaking the tree at contact")
	w.dino_ai.forest.clearing(breaker,.6)
	check(not w.trees.has(tree_cell) and w.board.is_open(tree_cell),"Completed tree break releases actual navigation")
	check(not w.board.is_open(Vector2i(67,64)),"Tree break does not remove building collision")
	w.free()
	print("FOREST PATROL failures=",failures)
	quit(1 if failures else 0)
