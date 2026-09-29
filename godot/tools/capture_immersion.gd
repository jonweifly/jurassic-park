extends SceneTree
## Reproducible main-game fixtures, isolated from player saves and preferences.
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
var w: Node
var folder := "res://captures/immersion"

func _initialize() -> void: call_deferred("run")

func shot(title: String) -> void:
	w.update_lighting()
	w.update_camera(0)
	w.hud.refresh(0)
	w.encounter._process(0.01)
	for i in range(5): await process_frame
	RenderingServer.force_draw(false)
	print("IMMERSION CAPTURE ", title, " ", root.get_texture().get_image().save_png(folder.path_join(title + ".png")))

func run() -> void:
	Save.directory = "user://immersion_capture_fixture"
	Preferences.file_path = "user://immersion_capture_fixture/preferences.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.sound.set_process(false)
	w.encounter.set_process(false)
	w.start_session(1500, "standard")
	w.spawn_clocks.clear()
	w.preferences.values.perspective = true
	w.preferences.values.quality = 2
	w.preferences.apply(w, false)
	w.prepare_demo()
	w.camera_size = 21
	w.camera_rig.target_pitch = deg_to_rad(43)
	w.weather.preview_kind = 0
	w.update_lighting()
	w.update_buildings(0)
	var target: Dictionary
	for b in w.session.buildings:
		if b.kind == "tower": target = b; break
	var origin: Vector3 = w.board.point(target.cell)
	var boss: Node3D = w.spawn_dinosaur(origin + Vector3(2, 0, 0), "trex")
	boss.position.y = w.board.layout.height_at(boss.position.x, boss.position.z)
	w.dino_ai.engage(boss, {"kind":"building", "id":target.id, "position":origin})
	for offset in [Vector3(5, 0, -1), Vector3(3, 0, 3)]:
		var cell: Vector2i = w.board.cell_at(origin + offset)
		if w.trees.has(cell): w.clear_tree(cell)
		var small: Node3D = w.spawn_dinosaur(w.board.point(cell), "raptor")
		if small == null: continue
		w.dino_ai.engage(small, {"kind":"hero", "id":w.survivor_id(w.hero), "position":w.hero.position})
		small.visual.face(w.hero.position-small.position, 1)
		small.play_animation("walk", 0.2)
	w.camera_rig.center(false)
	w.camera_focus = origin + Vector3(0,0,2)
	w.vision.update()
	w.dino_ai.attack_if_close(boss)
	w.encounter.scan()
	await shot("01-defense-windup")
	w.dino_ai.resolve_strike(boss, 0.7)
	boss.play_animation("attack", 0.22)
	w.update_effects(0.1)
	w.encounter.update_dust(0.1)
	w.scenery.clock += 0.1
	w.scenery.update_building(w.visuals[target.id], target)
	await shot("02-defense-impact")
	# Choose a real reachable ledge with neighbouring geometry for a terrain view.
	var chosen := Vector2i(-1, -1)
	var best := 0
	for entry in w.scenery.terrain_relief.placements:
		var p: Vector3 = entry.transform.origin
		if p.length() > 95 or p.length() < 25: continue
		var density := 0
		for other in w.scenery.terrain_relief.placements:
			if p.distance_squared_to(other.transform.origin) < 64: density += 1
		if density <= best: continue
		for delta in [Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0), Vector2i(0,-1)]:
			var cell: Vector2i = entry.cell + delta
			if w.board.is_open(cell): chosen = cell; best = density; break
	if chosen.x >= 0:
		w.hero.position = w.board.point(chosen)
		w.camera_focus = w.hero.position
		w.camera_size = 24
		w.camera_rig.target_pitch = deg_to_rad(43)
		w.camera_rig.target_yaw = deg_to_rad(35)
		w.vision.update()
		w.encounter.scan()
		w.hud.hide()
		await shot("03-terrain-depth")
	w.free()
	quit()
