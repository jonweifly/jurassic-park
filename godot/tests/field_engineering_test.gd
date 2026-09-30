extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.sound.set_process(false)
	for index in range(4):
		w.hud.duration_select.select(index)
		for difficulty in range(2):
			w.hud.difficulty_select.select(difficulty)
			check(w.hud.selected_duration() == [1500,2700,3600,4800][index] and w.hud.selected_difficulty() == ["standard","hard"][difficulty],"Independent duration and difficulty combination")
	w.hud.duration_select.select(3)
	w.hud.difficulty_select.select(1)
	w.hud.standard_start_button.pressed.emit()
	check(w.session.duration == 4800 and w.session.mode == "hard","Start action honors 80-minute hard selection")
	check(w.board.body_open(w.extraction,5.5),"Landing zone has full static clearance")
	check(not w.board.route(w.hero.position,w.extraction,false,.3).is_empty(),"Landing center reachable from start")
	var relief := 0.0
	for x in range(-4,5):
		for z in range(-4,5): relief = maxf(relief,absf(w.board.layout.height_at(w.extraction.x+x,w.extraction.z+z)-w.extraction.y))
	check(relief < 1.2,"Landing zone no longer overlaps a mountain slope")
	print("LANDING ",w.extraction," relief=",relief)
	w.prepare_demo()
	# Simulation is driven explicitly; retain valid hard-mode clocks for save validation.
	w.session.wood = 500
	w.session.gold = 500
	var shop: Dictionary
	var generator: Dictionary
	var target: Dictionary
	for b in w.session.buildings:
		if b.kind == "lab": shop = b
		if b.kind == "generator": generator = b
		if b.kind == "tent": target = b
	w.selected_id = shop.id
	w.research("workshop")
	w.session.tick(15)
	w.outfit_action("craft",shop.id,"chainsaw")
	w.outfitting.update(25)
	w.outfit_action("collect",shop.id)
	for frame in range(3000):
		w.hero.advance(.05)
		w.outfitting.tick_actor(.05)
		if w.order != "field": break
	check(w.outfitting.saw_active(),"Crafting and walking to collect equips saw")
	var tree := Vector2i(-1,-1)
	for cell in w.trees:
		var path: PackedVector3Array = w.worker.work_route("wood",w.board.point(cell))
		if not path.is_empty():
			tree = cell
			w.hero.position = path[-1]
			break
	check(tree.x >= 0,"Saw fixture finds reachable tree")
	w.worker.cargo = 1
	w.worker.cargo_kind = "wood"
	w.worker.assign("wood",w.board.point(tree))
	check(w.order == "wood","Saw cuts even while carrying existing resources")
	for frame in range(100):
		w.hero.advance(.05)
		w.worker.update(.05)
		if not w.trees.has(tree): break
	check(not w.trees.has(tree) and w.order == "idle","One saw operation clears tree and leaves survivor ready to escape")
	check(w.worker.cargo == 1,"Saw does not grant or destroy carried resources")
	w.outfit_action("saw")
	check(not w.outfitting.saw_active(),"Normal harvesting can be restored")
	check(not w.outfitting.craft_error(shop.id,"repair_bot").is_empty(),"Robot locked until mechanical research")
	w.session.technologies.tools = true
	# Use the real research rules with a second completed laboratory.
	var laboratory: Dictionary = shop.duplicate(true)
	laboratory.id = w.session.next_id
	w.session.next_id += 1
	laboratory.kind = "laboratory"
	laboratory.invested_wood = 10
	laboratory.invested_gold = 10
	laboratory.cell += Vector2i(0,3)
	laboratory.hp = 100.0
	w.clear_tree(laboratory.cell)
	w.session.buildings.append(laboratory)
	w.board.block_building(laboratory.cell,laboratory.id)
	w.create_building_visual(laboratory)
	# Extra supply is a real generator building.
	var extra: Dictionary = generator.duplicate(true)
	extra.id = w.session.next_id
	w.session.next_id += 1
	extra.cell += Vector2i(0,4)
	w.clear_tree(extra.cell)
	w.session.buildings.append(extra)
	w.board.block_building(extra.cell,extra.id)
	w.create_building_visual(extra)
	check(w.session.begin_research("mechanical").is_empty(),"Mechanical engineering starts through research rules")
	w.session.tick(40)
	check(w.session.technologies.has("mechanical"),"Mechanical research finishes")
	w.outfit_action("craft",shop.id,"repair_bot")
	w.outfitting.update(35)
	check(w.outfitting.data().robots.size() == 1 and w.outfitting.data().jobs.is_empty(),"Finished robot deploys automatically")
	target.hp = 20.0
	var wood: int = w.session.wood
	for frame in range(1200): w.robots.update(.05)
	check(target.hp == 100 and w.session.wood == wood-10,"Robot travels to damaged tent and spends exactly ten wood repairing 80 HP")
	target.hp = 50.0
	w.session.wood = 0
	for frame in range(100): w.robots.update(.05)
	check(target.hp == 50,"Robot cannot repair without materials")
	w.session.wood = 100
	generator.hp = 0
	extra.hp = 0
	for frame in range(100): w.robots.update(.05)
	check(target.hp == 50 and w.session.wood == 100,"Power outage pauses robot repair and spending")
	generator.hp = 100
	extra.hp = 100
	var snapshot: Dictionary = Save.snapshot(w)
	check(Save.validate(snapshot).is_empty(),"New gear and deployed robots validate in save format")
	var old: Dictionary = snapshot.duplicate(true)
	old.session.outfitting.erase("robots")
	for actor in old.session.outfitting.actors.values():
		actor.erase("chainsaw")
		actor.erase("saw_enabled")
	check(Save.validate(old).is_empty(),"Existing equipment saves without new fields remain loadable")
	w.free()
	w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	Save.apply(w,snapshot)
	check(w.outfitting.actor().chainsaw == 1 and w.outfitting.data().robots.size() == 1,"Save restores chainsaw and robot")
	for frame in range(1200): w.robots.update(.05)
	check(w.session.building(target.id).hp == 100,"Restored robot replans and resumes repairs")
	var robot_packet: Dictionary = w.coop.replication.world_packet(true)
	check(robot_packet.session.outfitting.robots.size() == 1,"Host includes robots in shared world state")
	w.robots.deploy(w.session.building(shop.id))
	w.robots.deploy(w.session.building(shop.id))
	check(not w.outfitting.craft_error(shop.id,"repair_bot").is_empty(),"Camp robot limit blocks additional crafting")
	w.free()
	print("FIELD ENGINEERING: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
