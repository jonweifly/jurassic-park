extends SceneTree
const Save = preload("res://scripts/save_store.gd")
const Gear = preload("res://scripts/outfitting_catalog.gd")
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func finish_trip() -> void:
	for frame in range(3000):
		world.hero.advance(.05)
		world.update_order(.05)
		world.outfitting.tick_actor(.05)
		if world.order != "field": return
	expect(false, "Field trip must finish on real navigation within 150 seconds")

func reload_world(snapshot: Dictionary) -> void:
	world.free()
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	Save.apply(world, snapshot)
	world.paused = false

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500, "standard")
	world.spawn_clocks.clear()
	world.prepare_demo()
	world.session.wood = 500
	world.session.gold = 500
	var gear: RefCounted = world.outfitting
	expect(gear.data().sites.size() == 3, "Three reachable field sites initialize in the core game")
	for id in gear.data().sites:
		var site: Dictionary = gear.data().sites[id]
		expect(world.board.structures[site.cell] < -100 and not world.board.route(world.hero.position, world.board.point(site.cell), true).is_empty(), id + " reserves a real reachable landmark")
		site.guarded = true # Isolate economic/route tests from active AI.
	var foundation: Dictionary
	var generator: Dictionary
	for b in world.session.buildings:
		if b.kind == "lab": foundation = b
		if b.kind == "generator": generator = b
	world.selected_id = foundation.id
	var before := Vector2i(world.session.wood, world.session.gold)
	world.research("workshop")
	expect(foundation.kind == "workshop" and foundation.remaining == 15 and Vector2i(world.session.wood,world.session.gold) == before - Vector2i(10,8), "Selected foundation upgrades into a workshop and charges once")
	expect(not gear.craft_error(foundation.id,"boots").is_empty(), "Incomplete workshop cannot craft")
	world.session.tick(15)
	world.outfit_action("craft", foundation.id, "boots")
	before = Vector2i(world.session.wood,world.session.gold)
	world.outfit_action("craft", foundation.id, "boots")
	expect(Vector2i(world.session.wood,world.session.gold) == before, "Duplicate craft cannot charge twice")
	generator.hp = 0
	gear.update(10)
	expect(gear.data().jobs[str(foundation.id)].remaining == 18, "Outage pauses actual workshop production")
	generator.hp = 100
	gear.update(18)
	expect(gear.actor().boots == 0 and gear.data().jobs[str(foundation.id)].remaining == 0, "Finished equipment remains at workshop until collected")
	world.outfit_action("collect", foundation.id)
	finish_trip()
	expect(gear.actor().boots == 1 and is_equal_approx(world.hero.speed, 6.16), "Walking to collect equips boots and changes real movement speed")
	expect(gear.data().jobs.is_empty() and not gear.craft_error(foundation.id,"boots").is_empty(), "Equipment has no repeat stacking or duplicate pickup")
	for item in ["vest", "rifle", "medkit"]:
		world.outfit_action("craft", foundation.id, item)
		gear.update(Gear.ITEMS[item].time)
		world.outfit_action("collect", foundation.id)
		finish_trip()
	expect(is_equal_approx(gear.incoming_damage(world.hero, 20), 17) and gear.incoming_damage(world.hero, 20, false) == 20, "Vest reduces direct attacks but cannot negate acid")
	expect(gear.damage_multiplier(world.hero) == 1.25 and world.hero.visual.outfit_parts.size() >= 4, "Rifle modifies damage and worn gear has bone-attached visuals")
	var kits: int = gear.actor().kits
	world.outfit_action("kit")
	expect(gear.actor().kits == kits, "Full-health medkit does not consume inventory")
	world.hero.health = 50
	world.outfit_action("kit")
	expect(world.hero.health == 100 and gear.actor().kits == kits - 1, "Real kit action restores 50 HP and consumes one")
	gear.actor().kits = 3
	world.outfit_action("kit")
	expect(world.hero.health == 100 and gear.actor().kits == 3, "Cooldown prevents repeated healing")
	expect(not gear.craft_error(foundation.id,"medkit").is_empty(), "Carry cap prevents excess medkit production")
	expect(not gear.craft_error(foundation.id,"boots_2").is_empty(), "Advanced recipe is locked before recovered blueprint")
	for id in ["supplies", "ranger", "arsenal"]:
		world.outfit_action("explore", -1, id)
		# Save midway, before arrival: task/order and reserved landmark must round-trip.
		var snapshot := Save.snapshot(world)
		expect(Save.validate(snapshot).is_empty(), "Active field trip validates for save: " + id)
		if id == "supplies":
			reload_world(snapshot)
			gear = world.outfitting
			expect(world.order == "field" and gear.actor().site == id, "Reload resumes actual outbound field route")
		finish_trip()
		expect(gear.data().sites[id].status == "carried" and id in gear.actor().cargo, id + " is carried physically before camp reward")
		if id == "supplies":
			reload_world(Save.snapshot(world))
			gear = world.outfitting
			expect(id in gear.actor().cargo, "Reload preserves unreturned physical cargo")
		if id != "supplies": expect(id not in gear.data().blueprints, "Unreturned blueprint cannot unlock recipes")
		before = Vector2i(world.session.wood,world.session.gold)
		world.outfit_action("return")
		finish_trip()
		expect(gear.data().sites[id].status == "completed" and gear.actor().cargo.is_empty(), "Returning to tent settles " + id)
		expect(Vector2i(world.session.wood,world.session.gold) == before + Vector2i(Gear.SITES[id].wood,Gear.SITES[id].gold), "Exact one-time reward for " + id)
		gear.tick_actor(1)
		expect(Vector2i(world.session.wood,world.session.gold) == before + Vector2i(Gear.SITES[id].wood,Gear.SITES[id].gold), "Repeated tent ticks cannot duplicate rewards")
	expect(gear.actor().kits == 3 and gear.data().reserve_kits == 1, "Full bag keeps recovered spare kit in camp storage")
	expect(not gear.craft_error(foundation.id,"boots_2").is_empty(), "Blueprint still requires laboratory technology")
	world.session.technologies.field_equipment = true
	world.outfit_action("craft", foundation.id, "boots_2")
	gear.update(25)
	world.outfit_action("collect", foundation.id)
	finish_trip()
	expect(gear.actor().boots == 2 and is_equal_approx(world.hero.speed, 6.44), "Advanced boots replace old ones without additive stacking")
	world.outfit_action("craft", foundation.id, "rifle_2")
	gear.update(3)
	var saved := Save.snapshot(world)
	expect(Save.validate(saved).is_empty(), "Equipment, blueprints and pending craft validate together")
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt.session.outfitting.actors["1"].kits = 99
	expect(not Save.validate(corrupt).is_empty(), "Save rejects invalid medkit count")
	corrupt = saved.duplicate(true)
	corrupt.session.outfitting.jobs[str(foundation.id)].item = "cheat"
	expect(not Save.validate(corrupt).is_empty(), "Save rejects unknown recipes")
	var legacy := saved.duplicate(true)
	legacy.session.erase("outfitting")
	expect(Save.validate(legacy).is_empty(), "Existing version-four saves remain compatible")
	world.free()
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	Save.apply(world, saved)
	gear = world.outfitting
	expect(gear.actor().boots == 2 and gear.data().jobs[str(foundation.id)].remaining == 32, "Reload preserves equipped gear and exact craft progress")
	expect(gear.data().blueprints.size() == 2 and gear.actor().cargo.is_empty(), "Reload preserves completed exploration without redraw or rewards")
	world.paused = false
	world.session.building(foundation.id).hp = 0
	gear.update(1)
	expect(gear.data().jobs.is_empty() and gear.actor().boots == 2, "Destroyed workshop loses pending items but not worn gear")
	var partner: Node3D = load("res://scenes/models/survivor.tscn").instantiate()
	partner.set_meta("coop_slot", 2)
	world.add_child(partner)
	expect(gear.actor(partner).boots == 0 and gear.actor(partner).kits == 0, "Second survivor has independent equipment and consumables")
	var tent: Dictionary = world.session.buildings[0]
	world.damage_building(tent, 2)
	var order: String = world.order
	gear.view_camp()
	expect(gear.recent_hits.has(tent.id) and not world.camera_rig.following and world.camera_focus == world.board.point(tent.cell) and world.order == order, "Camp hit warning centers camera without issuing a character command")
	world.session.elapsed += 9
	gear.sync_visuals()
	expect(gear.recent_hits.is_empty(), "Camp alert expires through client presentation refresh without host simulation")
	# Re-enable encounters for the threat checks after the isolated route/economy checks.
	world.spawn_clocks.append({"period": 90.0, "next": 90.0, "species": ["raptor"]})
	# Real map placement must produce the advertised threats, once per site.
	for id in ["ranger", "arsenal"]:
		var site: Dictionary = gear.data().sites[id]
		site.status = "known"
		site.progress = 0.0
		site.guarded = false
		world.hero.position = world.board.point(site.cell) + Vector3(2,0,0)
		var count: int = world.dinosaurs.size()
		gear.update(1)
		expect(world.dinosaurs.size() == count + Gear.SITES[id].guards.size(), id + " spawns all advertised guards on actual navigable terrain")
		gear.update(1)
		expect(world.dinosaurs.size() == count + Gear.SITES[id].guards.size(), "Returning to a site does not duplicate its guard spawn")
		world.outfit_action("explore", -1, id)
		world.hero.route.clear()
		gear.tick_actor(1)
		expect(site.progress == 0, "Nearby living guards interrupt searching")
	# A pre-equipment save can put the survivor inside a closed camp. New field
	# landmarks must still initialize, without moving them or opening defenses.
	var chamber := Vector2i(-1,-1)
	for x in range(76,96):
		for y in range(48,72):
			var clear := true
			for dx in range(-1,2):
				for dy in range(-1,2):
					if not world.board.can_build(Vector2i(x+dx,y+dy)): clear = false
			if clear:
				chamber = Vector2i(x,y)
				break
		if chamber.x >= 0: break
	expect(chamber.x >= 0, "Real terrain has space for a legacy enclosed-camp fixture")
	if chamber.x >= 0:
		legacy.hero.position = world.board.point(chamber)
		legacy.hero.route = PackedVector3Array()
		legacy.order = "idle"
		legacy.order_target = legacy.hero.position
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			legacy.session.buildings.append({"id":legacy.session.next_id, "kind":"gate", "cell":chamber+offset, "hp":300.0, "remaining":0.0, "cooldown":0.0, "open":false})
			legacy.session.next_id += 1
		expect(Save.validate(legacy).is_empty(), "Enclosed legacy fixture is a valid old save")
		reload_world(legacy)
		gear = world.outfitting
		expect(gear.data().sites.size() == 3, "Loading an enclosed old camp still creates all three field sites")
		expect(world.hero.position == legacy.hero.position and world.session.buildings == legacy.session.buildings, "Legacy initialization preserves survivor position and every existing defense")
		for id in gear.data().sites:
			var destination: Vector3 = world.board.point(gear.data().sites[id].cell)
			expect(world.board.route(world.hero.position,destination,true).is_empty(), "Closed camp stays impassable after adding field sites")
			expect(not world.board.route(world.board.point(Vector2i(65,62)),destination,true).is_empty(), "Fallback field site remains reachable from the island entry")
		expect(Save.validate(Save.snapshot(world)).is_empty(), "Migrated enclosed camp can be saved again")
	world.free()
	print("OUTFITTING: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
