extends "res://tests/defense_tactics_test.gd"
const Visuals = preload("res://scripts/tower_visuals.gd")

func run() -> void:
	Save.directory = "user://tower_upgrade_fixture"
	w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.sound.set_process(false)
	w.start_session(1500, "standard")
	w.prepare_demo()
	w.session.wood = 1000
	w.session.gold = 1000
	var tower: Dictionary
	var lab: Dictionary
	var gate: Dictionary
	for b in w.session.buildings:
		if b.kind == "tower": tower = b
		if b.kind == "lab": lab = b
		if b.kind == "gate": gate = b
	for option in ["range", "rapid", "heavy"]:
		var stock := Vector2i(w.session.wood,w.session.gold)
		expect(w.session.refit(tower.id,option).contains("箭塔工程"), "Tech prerequisite blocks " + option)
		expect(Vector2i(w.session.wood,w.session.gold) == stock and tower.get("refit", "").is_empty(), "Locked request has no side effects")
	expect(w.session.refit_error(gate.id,"brace").is_empty(), "Fence reinforcement does not require new tower tech")
	expect(not w.session.begin_research("tower_engineering").is_empty(), "Basic laboratory foundation cannot research")
	expect(w.session.research(lab.id).is_empty(), "Normal laboratory upgrade works")
	expect(not w.session.begin_research("tower_engineering").is_empty(), "Unfinished lab cannot research")
	w.session.work(lab.id,10)
	# Replace the upgraded lab model through the real world path.
	w.visuals[lab.id].free()
	w.visuals.erase(lab.id)
	w.create_building_visual(lab)
	var stock := Vector2i(w.session.wood,w.session.gold)
	expect(w.session.begin_research("tower_engineering").is_empty(), "Completed powered lab can research")
	expect(Vector2i(w.session.wood,w.session.gold) == stock-Vector2i(20,15), "Research charges advertised cost exactly once")
	expect(not w.session.begin_research("tower_engineering").is_empty(), "No duplicate research")
	var generator: Dictionary
	for b in w.session.buildings:
		if b.kind == "generator": generator = b
	generator.hp = 0
	w.session.tick(5)
	expect(w.session.research_job.remaining == 25, "Unpowered research pauses")
	generator.hp = 100
	w.session.tick(24)
	expect(not w.session.refit_error(tower.id,"range").is_empty(), "Pending research does not unlock towers early")
	var pending := Save.snapshot(w)
	expect(Save.validate(pending).is_empty(), "Pending new technology is save compatible")
	Save.apply(w,pending)
	w.session.tick(1)
	expect(w.session.technologies.has("tower_engineering"), "Research completes using game time")
	tower = w.session.building(tower.id)
	for option in ["range", "rapid", "heavy"]:
		tower.erase("refit")
		tower.invested_wood = 15
		tower.invested_gold = 15
		tower.remaining = 0
		w.scenery.update_building(w.visuals[tower.id],tower)
		var basic_id: int = w.visuals[tower.id].get_node("Model").get_instance_id()
		expect(w.session.refit(tower.id,option).is_empty(), "Researched upgrade allowed: " + option)
		w.update_buildings(0)
		expect(w.visuals[tower.id].get_node("Model").get_instance_id() == basic_id, "Construction retains basic tower until ready")
		w.session.tick(Catalog.REFITS[option].time)
		w.update_buildings(0)
		var node: Node3D = w.visuals[tower.id]
		expect(node.get_meta("tower_variant") == option and node.has_node("Model/Gun/Recoil/Muzzle"), "Completed upgrade installs independent model and muzzle: " + option)
		expect(not node.get_node("CampDressing").visible, "Old deck dressing does not intersect the new model")
		var model_id: int = node.get_node("Model").get_instance_id()
		w.update_buildings(.1)
		expect(node.get_node("Model").get_instance_id() == model_id, "Update reuses geometry")
		expect(w.board.structures.get(tower.cell, -1) == tower.id, "Upgrade keeps existing navigation footprint")
		var muzzle := Visuals.fire(node,w.scenery.clock)
		expect(muzzle.y > node.global_position.y+1.5, "Projectile origin follows weapon height")
		if option == "rapid": expect(muzzle.distance_to(Visuals.fire(node,w.scenery.clock)) > .7, "Twin bows alternate muzzle positions")
		w.scenery.update_building(node,tower)
		expect(node.get_node("Model/Gun/Recoil").position.z < 0, "Shot produces weapon recoil")
		w.scenery.clock += .3
		w.scenery.update_building(node,tower)
		expect(is_zero_approx(node.get_node("Model/Gun/Recoil").position.z), "Recoil recovers without drift")
		stock = Vector2i(w.session.wood,w.session.gold)
		expect(not w.session.refit(tower.id,option).is_empty() and Vector2i(w.session.wood,w.session.gold)==stock, "Repeat clicks do not spend resources")
	# Legacy towers without the new tech retain their model and combat role.
	w.session.technologies.erase("tower_engineering")
	var legacy := Save.snapshot(w)
	expect(Save.validate(legacy).is_empty(), "Legacy upgraded tower still validates")
	Save.apply(w,legacy)
	tower = w.session.building(tower.id)
	w.update_buildings(0)
	expect(tower.refit == "heavy" and Catalog.attack_damage(tower)==36 and w.visuals[tower.id].get_meta("tower_variant")=="heavy", "Old upgraded tower survives load without retroactive tech lock")
	w.free()
	print("TOWER UPGRADE: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
