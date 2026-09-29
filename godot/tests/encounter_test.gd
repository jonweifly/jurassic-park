extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var passed := true
	for scenario in [
		{"seed": 65065, "camp": false, "region": "center"},
		{"seed": 17, "camp": true, "region": "center"},
		{"seed": 80, "camp": true, "region": "center"},
		{"seed": 65, "camp": true, "region": "mountain"},
		{"seed": 65, "camp": true, "region": "ice"},
		{"seed": 65, "camp": true, "region": "swamp"},
		{"seed": 65, "camp": true, "region": "rainforest"},
	]:
		if "--swamp-only" in OS.get_cmdline_user_args() and scenario.region != "swamp": continue
		var result: bool = await run_scenario(scenario.seed, scenario.camp, scenario.region)
		passed = result and passed
	quit(0 if passed else 1)

func run_scenario(seed_value: int, with_camp: bool, region: String) -> bool:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(3600)
	# This fixture measures timed patrol waves. Field-site guards have their own
	# proximity trigger and can legitimately attack a remote camp before 60s.
	for site in world.outfitting.data().sites.values(): site.guarded = true
	world.rng.seed = seed_value
	world.hero.health = 100000
	var tent: Dictionary = {}
	if with_camp:
		var cell := Vector2i(63, 62)
		if region != "center":
			var positions := {"mountain": Vector3(55, 0, -55), "ice": Vector3(-55, 0, -55), "swamp": Vector3(55, 0, 55), "rainforest": Vector3(-55, 0, 55)}
			var center: Vector2i = world.board.cell_at(positions[region])
			var found := false
			for radius in range(15):
				if found: break
				for x in range(-radius, radius + 1):
					if found: break
					for y in range(-radius, radius + 1):
						var candidate := center + Vector2i(x, y)
						if not world.board.can_build(candidate): continue
						var route: PackedVector3Array = world.board.route(world.hero.position, world.board.point(candidate), true)
						if route.is_empty(): continue
						cell = candidate
						world.hero.position = route[-1]
						found = true
						break
			if not found:
				push_error("No reachable camp fixture in " + region)
				world.queue_free()
				await process_frame
				return false
		else: world.clear_tree(cell)
		tent = world.session.build("tent", cell)
		tent.remaining = 0
		world.board.block_building(cell, tent.id)
		world.create_building_visual(tent)
	world.camera_focus = world.hero.position
	world.vision.update()
	var encountered := false
	var hits: Array[float] = []
	for i in range(240 * 30):
		world._physics_process(1.0 / 30)
		for d in world.dinosaurs:
			if d.visible: encountered = true
		if world.hero.health < 100000 or (not tent.is_empty() and tent.hp < 100):
			hits.append(world.session.elapsed)
			if hits.size() == 2: break
			# Clear the entire first group so a second hit proves later spawns arrive.
			for d in world.dinosaurs: d.free()
			world.dinosaurs.clear()
			world.hero.health = 100000
			if not tent.is_empty(): tent.hp = 100
	print("ENCOUNTER seed=", seed_value, " region=", region, " camp=", with_camp, " visible=", encountered, " attacks_seconds=", hits)
	var passed: bool = encountered and hits.size() == 2 and hits[0] >= 60 and hits[0] <= 150 and hits[1] > hits[0] + 20 and hits[1] <= 240
	if not passed: push_error("Camp in " + region + " must receive first attack by 150s and a fresh group by 240s")
	world.queue_free()
	await create_timer(0.15).timeout
	return passed
