extends SceneTree
const Save = preload("res://scripts/save_store.gd")
const Session = preload("res://scripts/session.gd")
const Dinosaurs = preload("res://scripts/dinosaur_catalog.gd")
var checks := 0
var failures := 0
var world: Node

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func make_world() -> Node:
	var w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.sound.set_process(false)
	w.start_session(1500, "hard")
	return w

func build(kind: String, cell: Vector2i) -> Dictionary:
	var b: Dictionary = world.session.build(kind, cell)
	b.remaining = 0.0
	world.board.block_building(cell, b.id)
	world.create_building_visual(b)
	return b

func run() -> void:
	Save.directory = "user://kill_stats_%d" % Time.get_ticks_usec()
	world = make_world()
	expect(world.session.kills == 0 and world.session.kills_by_species.is_empty(), "A new run starts with no kills")
	for species in Dinosaurs.SPECIES:
		var d: Node3D = world.spawn_dinosaur(world.hero.position, species)
		expect(d != null, "Species can spawn: " + species)
		if d == null: continue
		d.health = 0.0
		world.dino_ai.update_death(d, 0.1)
		world.dino_ai.update_death(d, 0.1)
		expect(world.session.kills_by_species.get(species) == 1, "Death animation records once: " + species)
	expect(world.session.kills == 7 and world.session.gold == 31, "Species statistics preserve total kills and exactly-once rewards")
	var saved := Save.snapshot(world)
	expect(Save.validate(saved).is_empty(), "Save including seven species and corpses validates: " + Save.validate(saved))
	expect(Save.write(world).is_empty(), "Statistics write to disk")
	var disk := Save.read_slot("manual")
	expect(disk.has("data") and disk.data.session.kills_by_species == saved.session.kills_by_species, "Disk read preserves per-species counts")
	world.free()
	world = make_world()
	Save.apply(world, saved)
	for d in world.dinosaurs.duplicate(): world.dino_ai.update_death(d, 0.1)
	expect(world.session.kills == 7 and world.session.kills_by_species.size() == 7 and world.session.gold == 31, "Loaded corpses do not duplicate counts or rewards")
	world.session.record_kill("raptor")
	expect(saved.session.kills_by_species.raptor == 1 and world.session.kills_by_species.raptor == 2, "Loaded statistics are independent of the saved snapshot")
	world.free()
	var legacy := saved.duplicate(true)
	legacy.session.erase("kills_by_species")
	expect(Save.validate(legacy).is_empty(), "Old saves without species history remain valid")
	world = make_world()
	Save.apply(world, legacy)
	for d in world.dinosaurs.duplicate(): world.dino_ai.update_death(d, 1.0)
	expect(world.session.kills == 7 and world.session.unclassified_kills() == 7 and world.session.kills_by_species.is_empty(), "Legacy totals stay unclassified; saved corpses cannot reconstruct missing history")
	var new_enemy: Node3D = world.spawn_dinosaur(world.hero.position, "spitter")
	new_enemy.health = 0.0
	world.dino_ai.update_death(new_enemy, 1.0)
	expect(world.session.kills == 8 and world.session.kills_by_species.spitter == 1 and world.session.unclassified_kills() == 7, "New kills after loading a legacy run are classified")
	expect(Save.validate(Save.snapshot(world)).is_empty(), "Legacy plus new statistics can save again")
	world.free()
	for stats in [[], {"raptor": -1}, {"raptor": 0.5}, {"unknown": 1}, {"raptor": 8}, {"raptor": 7, "trex": 1}]:
		var bad := saved.duplicate(true)
		bad.session.kills_by_species = stats
		expect(not Save.validate(bad).is_empty(), "Reject invalid stats: " + str(stats))
	var negative := saved.duplicate(true)
	negative.session.kills = -1
	expect(not Save.validate(negative).is_empty(), "Reject negative total kills")
	# Verify both actual combat sources feed the same death accounting.
	world = make_world()
	world.session.wood = 1000
	world.session.gold = 1000
	for x in range(56, 70):
		for y in range(77, 87): world.clear_tree(Vector2i(x, y))
	build("tent", Vector2i(60,81))
	build("generator", Vector2i(59,79))
	var tower := build("tower", Vector2i(64,81))
	var fence := build("shelter", Vector2i(62,83))
	var at: Vector3 = world.board.point(Vector2i(64,83))
	var prey: Node3D = world.spawn_dinosaur(at, "raptor")
	prey.health = 1.0
	prey.visible = true
	world.update_buildings(0.1)
	world.update_dinosaurs(0.1)
	expect(world.session.kills_by_species.get("raptor") == 1, "Real tower kill appears in species stats")
	tower.remaining = 20.0
	prey = world.spawn_dinosaur(world.board.point(fence.cell) + Vector3(0,0,2), "small_raptor")
	prey.health = 1.0
	prey.visible = true
	world.update_buildings(0.1)
	world.update_dinosaurs(0.1)
	expect(world.session.kills_by_species.get("small_raptor") == 1, "Real electric fence kill appears in species stats")
	prey = world.spawn_dinosaur(at, "spitter")
	prey.health = 1.0
	prey.visible = true
	world.hero.position = world.board.point(Vector2i(65,83))
	world.hero.target_id = prey.get_instance_id()
	world.order = "attack"
	world.hero_route_revision = world.board.revision
	world.update_order(0.1)
	world.update_dinosaurs(0.1)
	expect(world.session.kills_by_species.get("spitter") == 1 and world.session.kills == 3, "Real survivor kill joins defense kills in the same run")
	world.free()
	var fresh := Session.new()
	expect(fresh.kills == 0 and fresh.kills_by_species.is_empty(), "A fresh session never inherits previous statistics")
	var folder := DirAccess.open(Save.directory)
	if folder:
		for file in folder.get_files(): folder.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.directory))
	print("KILL STATS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
