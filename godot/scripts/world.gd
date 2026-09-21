extends Node3D
const Preferences = preload("res://scripts/preferences.gd")
const Catalog = preload("res://scripts/catalog.gd")
const SaveStore = preload("res://scripts/save_store.gd")
const Expedition = preload("res://scripts/expedition.gd")
const Director = preload("res://scripts/session_director.gd")
const Session = preload("res://scripts/session.gd")
const Board = preload("res://scripts/board.gd")
const Regions = preload("res://scripts/regions.gd")
const Worker = preload("res://scripts/worker.gd")
const Vision = preload("res://scripts/vision.gd")
const DinosaurAI = preload("res://scripts/dinosaur_ai.gd")
const Pawn = preload("res://scripts/pawn.gd")
const HUD = preload("res://scripts/hud.gd")
const Sound = preload("res://scripts/sound.gd")
const PointerFeedback = preload("res://scripts/pointer_feedback.gd")
const CameraRig = preload("res://scripts/camera_rig.gd")
const Scenery = preload("res://scripts/scenery.gd")
const Weather = preload("res://scripts/weather.gd")
const ExtractionFeedback = preload("res://scripts/extraction_feedback.gd")
const BuildAccess = preload("res://scripts/build_access.gd")
const SurvivorScene = preload("res://scenes/models/survivor.tscn")
const DinoScene = preload("res://scenes/models/raptor.tscn")
const TrexScene = preload("res://scenes/models/trex.tscn")
const TreeScene = preload("res://scenes/models/tree.tscn")
const RockScene = preload("res://scenes/models/rock.tscn")
const FossilScene = preload("res://scenes/models/fossil.tscn")

var preferences = Preferences.new()
var session = Session.new()
var board = Board.new()
var worker: RefCounted
var build_access: RefCounted
var vision: RefCounted
var dino_ai: RefCounted
var hero: Node3D
var camera: Camera3D
var pointer_feedback: Control
var camera_rig: RefCounted
var scenery: RefCounted
var weather: RefCounted
var camera_focus := Vector3(0, 0, 0)
var camera_size := 36.0
var hud: CanvasLayer
var sound: Node
var sun: DirectionalLight3D
var environment: Environment
var rng := RandomNumberGenerator.new()
var trees: Dictionary = {}
var fossils: Array[Vector3] = []
var dinosaurs: Array[Node3D] = []
var visuals: Dictionary = {}
var model_cache: Dictionary = {}
var ghost: MeshInstance3D
var destination: MeshInstance3D
var hover_cell := Vector2i.ZERO
var build_mode := ""
var selected_id := -1
var paused := false
var night := false
var order := "idle"
var order_target := Vector3.ZERO
var hero_route_revision := -1
var spawn_clocks: Array[Dictionary] = []
var extraction := Vector3(1, 0, -31)
var extraction_marker: MeshInstance3D
var extraction_feedback: RefCounted
var effects: Array[Dictionary] = []
var frame_count := 0
var capture_path := ""
var demo_mode := false
var started := false
var director: RefCounted
var adventure: RefCounted
var autosave_clock := 0.0
var persistence_enabled := not ("--script" in OS.get_cmdline_args())
var save_status := "尚未存档"
var low_health_warned := false
var outage_warned := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	if persistence_enabled: preferences.load_file()
	rng.seed = 65065
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
		if arg == "--demo": demo_mode = true
		if arg == "--quick-session": session.duration = 480.0
	board.load_layout()
	extraction = board.point(Vector2i(64, 48))
	make_environment()
	if has_node("Island"): register_terrain()
	else: make_terrain()
	if "--bake-map" in OS.get_cmdline_user_args():
		bake_terrain()
		set_process(false)
		set_physics_process(false)
		get_tree().quit()
		return
	var raptor_interval := rng.randf_range(70, 90)
	spawn_clocks = [
		{"period": raptor_interval, "next": raptor_interval, "species": ["raptor", "raptor", "small_raptor"]},
		{"period": 160.0, "next": 160.0, "species": ["trex", "trex", "young_trex"]},
	]
	hero = SurvivorScene.instantiate()
	hero.name = "Survivor"
	hero.position = board.point(Vector2i(65, 62))
	hero.navigation = board
	add_child(hero)
	camera_focus = hero.position
	director = Director.new(self)
	worker = Worker.new(self)
	build_access = BuildAccess.new(self)
	vision = Vision.new(self)
	scenery = Scenery.new(self)
	dino_ai = DinosaurAI.new(self)
	adventure = Expedition.new(self)
	ghost = mesh_box(Vector3(1.96, 0.06, 1.96), Color(0.45, 0.8, 0.58, 0.55))
	ghost.visible = false
	destination = ring(0.42, Color("d8c885"))
	destination.visible = false
	extraction_marker = ring(2.7, Color("c9b575"))
	extraction_marker.position = extraction + Vector3(0, 0.08, 0)
	var landing_label := Label3D.new()
	landing_label.text = "H"
	landing_label.font_size = 150
	landing_label.pixel_size = 0.035
	landing_label.rotation_degrees.x = -90
	landing_label.position = extraction + Vector3(0, 0.11, 0)
	landing_label.modulate = Color("c0ad75")
	add_child(landing_label)
	extraction_feedback = ExtractionFeedback.new(self)
	sound = Sound.new()
	sound.world = self
	add_child(sound)
	weather = Weather.new(self)
	hud = HUD.new()
	hud.world = self
	add_child(hud)
	pointer_feedback = PointerFeedback.new()
	pointer_feedback.world = self
	hud.root.add_child(pointer_feedback)
	if demo_mode:
		prepare_demo()
		started = true
	else: paused = true
	if not SaveStore.pending.is_empty():
		var data: Dictionary = SaveStore.pending
		SaveStore.pending = {}
		SaveStore.apply(self, data)
		save_status = SaveStore.pending_message
		hud.toast(save_status + "；已暂停，准备好后继续。")
	preferences.apply(self, persistence_enabled)
	update_camera(0)
	vision.update()
	hud.refresh(0)
	if not capture_path.is_empty() and "--audio-panel" in OS.get_cmdline_user_args(): hud.sound_panel.show()

func make_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("52646a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("aab99a")
	environment.ambient_light_energy = 0.35
	# Contact occlusion gives the procedural terrain and imported assets a more
	# convincing sense of weight, especially at the close zoom levels.
	# SSAO is available only under Forward+; GL Compatibility uses the explicit
	# building contact shadows created by Scenery instead.
	environment.ssao_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	environment.ssao_radius = 2.2
	environment.ssao_intensity = 1.35
	environment.ssao_power = 1.15
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("819794")
	environment.fog_density = 0.0014
	var env := WorldEnvironment.new()
	env.environment = environment
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-53, -32, 0)
	sun.light_color = Color("fff0d6")
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 115
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.25
	sun.shadow_normal_bias = 1.0
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_size
	camera.far = 500
	add_child(camera)
	camera.current = true
	camera_rig = CameraRig.new(self)

func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.93
	if color.a < 1: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func mesh_box(dimensions: Vector3, color: Color, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	m.mesh = box
	m.material_override = material(color)
	m.position = pos
	add_child(m)
	return m

func ring(radius: float, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius
	torus.outer_radius = radius + 0.08
	torus.rings = 40
	torus.ring_segments = 6
	n.mesh = torus
	n.material_override = material(color)
	add_child(n)
	return n

func make_terrain() -> void:
	var before := get_children()
	mesh_box(Vector3(100, 1, 100), Color("354e35"), Vector3(0, -0.56, 0))
	# Geometry is an original blockout, not yet a reconstruction of war3map.w3e.
	var palettes := [Color("465c39"), Color("475d3a"), Color("495f3d"), Color("445b38"), Color("4b613e")]
	var terrain_root := Node3D.new()
	terrain_root.name = "Forest"
	add_child(terrain_root)
	var cells_by_color: Array = [[], [], [], [], []]
	for x in range(Board.SIDE):
		for y in range(Board.SIDE):
			var cell := Vector2i(x, y)
			var p: Vector3 = board.point(cell)
			var index := rng.randi_range(0, 4)
			cells_by_color[index].append(p)
			var river := p.x > 29.0 + sin(p.z * 0.09) * 3 and p.x < 35.0 + sin(p.z * 0.09) * 3
			if river:
				board.block_terrain(cell)
				var water_marker := Marker3D.new()
				water_marker.position = p
				water_marker.set_meta("navigation_blocker", true)
				terrain_root.add_child(water_marker)
				continue
			var radius := Vector2(p.x, p.z).length()
			var clearing := radius < 8.0 or absf(p.x - sin(p.z * 0.08) * 3) < 3.4 or absf(p.z - 5) < 2.6
			var landing := p.distance_to(extraction) < 5
			if clearing or landing: continue
			if rng.randf() < (0.58 if radius < 19 else 0.27):
				var tree := TreeScene.instantiate()
				tree.position = p
				tree.rotation.y = rng.randf() * TAU
				var size_factor := rng.randf_range(0.82, 1.3)
				tree.scale = Vector3.ONE * size_factor
				terrain_root.add_child(tree)
				tree.set_meta("harvest_tree", true)
				trees[cell] = {"node": tree, "wood": 20}
				board.block_terrain(cell)
			elif radius > 20 and rng.randf() < 0.08:
				var rock := RockScene.instantiate()
				rock.position = p
				rock.scale = Vector3.ONE * rng.randf_range(0.8, 1.9)
				terrain_root.add_child(rock)
				rock.set_meta("navigation_blocker", true)
				board.block_terrain(cell)
	for i in range(5):
		var ground := MultiMeshInstance3D.new()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		var tile := PlaneMesh.new()
		tile.size = Vector2(2.01, 2.01)
		tile.material = material(palettes[i])
		multi.mesh = tile
		multi.instance_count = cells_by_color[i].size()
		for j in range(cells_by_color[i].size()): multi.set_instance_transform(j, Transform3D(Basis.IDENTITY, cells_by_color[i][j]))
		ground.multimesh = multi
		add_child(ground)
	# A broad winding footpath joins the camp and the landing zone.
	for z in range(-42, 44, 2):
		var p := Vector3(sin(z * 0.08) * 3, 0.015, z)
		mesh_box(Vector3(3.8, 0.035, 2.1), Color("676346"), p)
		mesh_box(Vector3(5.4, 0.03, 2.05), Color("497d79"), Vector3(32 + sin(z * 0.09) * 3, 0.04, z))
	for p in [Vector3(-5, 0, 3), Vector3(13, 0, -17), Vector3(-15, 0, 21)]:
		var cell: Vector2i = board.cell_at(p)
		clear_tree(cell)
		var f := FossilScene.instantiate()
		f.position = board.point(cell)
		fossils.append(f.position)
		f.set_meta("fossil", true)
		board.block_terrain(cell)
		add_child(f)
	for i in range(16):
		var mountain := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0
		cone.bottom_radius = rng.randf_range(4, 8)
		cone.height = rng.randf_range(7, 15)
		cone.radial_segments = 5
		mountain.mesh = cone
		mountain.material_override = material(Color("717f69"))
		mountain.position = Vector3(-46 + i * 6, cone.height / 2 - 1, -49)
		add_child(mountain)
	var island := Node3D.new()
	island.name = "Island"
	add_child(island)
	for child in get_children():
		if child != island and child not in before: child.reparent(island)

func register_terrain() -> void:
	for n in $Island.find_children("*", "Node3D", true, false):
		var cell: Vector2i = board.cell_at(n.global_position)
		if n.has_meta("harvest_tree"):
			trees[cell] = {"node": n, "wood": 20}
			board.block_terrain(cell)
		if n.has_meta("navigation_blocker"): board.block_terrain(cell)
		if n.has_meta("fossil"):
			# Legacy preview deposits are replaced by player-built excavation fields.
			n.hide()

func bake_terrain() -> void:
	var island: Node3D = $Island
	assign_scene_owner(island, island)
	var scene := PackedScene.new()
	var error := scene.pack(island)
	if error == OK: error = ResourceSaver.save(scene, "res://scenes/island.tscn")
	print("BAKE MAP result=", error)

func assign_scene_owner(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion():
			child.free()
			continue
		if String(child.name).begins_with("@"):
			child.name = ("Tree" if child.has_meta("harvest_tree") else "Part") + "_%d" % child.get_index()
		child.owner = scene_root
		# Preserve ownership inside packed model instances, so the editor can link them.
		if child.scene_file_path.is_empty(): assign_scene_owner(child, scene_root)

func clear_tree(cell: Vector2i) -> void:
	if trees.has(cell):
		if scenery and scenery.forest: scenery.forest.remove_cell(cell)
		trees[cell].node.queue_free()
		trees.erase(cell)
	board.block_terrain(cell, false)

func update_camera(dt: float) -> void:
	camera_rig.update(dt)
	if scenery: scenery.update_view(dt)

func ground_at(screen: Vector2) -> Vector3:
	var ray := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(ray, ray + direction * 600, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else Vector3(10000, 0, 10000)

func _process(dt: float) -> void:
	if weather: weather.update()
	update_camera(dt)
	hover_cell = board.cell_at(ground_at(get_viewport().get_mouse_position()))
	update_build_preview()
	hud.refresh(dt)
	pointer_feedback.refresh(dt)
	extraction_feedback.update()
	frame_count += 1
	if frame_count == 30 and not capture_path.is_empty(): capture.call_deferred()

func update_build_preview() -> void:
	# Keep the world preview alive while the cursor is over a UI panel; the
	# panel consumes the click itself, and synthetic/native input can lag the
	# OS cursor position by one frame.
	ghost.visible = not build_mode.is_empty() and not paused
	if ghost.visible:
		ghost.position = board.point(hover_cell) + Vector3(0, 0.08, 0)
		var error := placement_error(hover_cell)
		ghost.material_override.albedo_color = Color(0.43, 0.9, 0.58, 0.6) if error.is_empty() else Color(0.9, 0.32, 0.23, 0.6)
		if error.is_empty() and not placement_warning(hover_cell).is_empty():
			ghost.material_override.albedo_color = Color(0.95, 0.68, 0.23, 0.65)

func _physics_process(dt: float) -> void:
	if paused: return
	if session.phase in ["won", "lost"]:
		if hero.health <= 0 and hero.death_clock > 0:
			hero.advance(dt)
			hero.death_clock -= dt
		return
	session.tick(dt)
	if session.survival_damage > 0.0:
		hero.health = maxf(0.0, hero.health - session.survival_damage)
		session.survival_damage = 0.0
	scenery.clock += dt
	hero.navigation = board
	hero.advance(dt)
	hero.position.y = board.layout.height_at(hero.position.x, hero.position.z)
	vision.tick(dt)
	update_order(dt)
	worker.update(dt)
	# A completed tent is also a safe rest point. Resting is automatic while idle
	# nearby, so the player does not need another modal interaction.
	if order == "idle" and near_completed_tent():
		session.rest(dt)
	adventure.update(dt)
	if paused: return
	update_buildings(dt)
	update_dinosaurs(dt)
	update_effects(dt)
	update_lighting()
	director.update()
	if hero.health < hero.max_health * 0.3 and not low_health_warned:
		low_health_warned = true
		hud.toast("生命危急！撤回帐篷，按 %s 花费黄金治疗。" % preferences.key_name("heal"))
		sound.play_ui("warning")
	if hero.health > hero.max_health * 0.5: low_health_warned = false
	var outage: bool = session.supply() < session.demand()
	if outage and not outage_warned:
		hud.toast("营地断电：防御与研究停止，请修复或补建发电站。")
		sound.play_ui("warning")
	outage_warned = outage
	if hero.health <= 0:
		session.phase = "lost"
		hud.toast("幸存者阵亡。调整基地选址与防线，再试一次。")
	if session.phase == "evacuate":
		if extraction_feedback.inside():
			if session.mode == "classic": session.phase = "won"
			else:
				session.boarding_progress += dt
				if session.boarding_progress >= Catalog.BOARDING_SECONDS: session.phase = "won"
		else: session.boarding_progress = maxf(0, session.boarding_progress - dt * 0.5)
	if persistence_enabled and started and session.phase in ["playing", "evacuate"]:
		autosave_clock += dt
		if autosave_clock >= 120:
			autosave_clock = 0
			save_game(true)

func _input(event: InputEvent) -> void:
	if hud and hud.preferences_panel and hud.preferences_panel.handle(event): get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if hud.confirmation.visible or hud.preferences_panel.panel.visible: return
	if hud.guide_panel.panel.visible:
		if event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or preferences.matches(event, "guide")): hud.guide_panel.close()
		return
	if preferences.matches(event, "settings"):
		hud.preferences_panel.open()
		return
	if preferences.matches(event, "guide"):
		hud.guide_panel.open()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if preferences.matches(event, "save"):
			save_game()
			return
		if preferences.matches(event, "load"):
			hud.request_load()
			return
	if hud.expedition_panel.panel.visible:
		if event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or preferences.matches(event, "journal")): hud.expedition_panel.close()
		return
	if hud.load_panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: hud.close_load()
		return
	if hud.tech_panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: hud.close_tech()
		return
	if not paused and started and session.phase in ["playing", "evacuate"] and camera_rig.handle(event): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if not build_mode.is_empty(): build_mode = ""
			else: toggle_pause()
			return
		if preferences.matches(event, "journal") and started:
			hud.expedition_panel.open()
			return
		if paused or session.phase in ["won", "lost"]: return
		for i in range(Catalog.ORDER.size()):
			if preferences.matches(event, "build_%d" % i): select_build(Catalog.ORDER[i])
		if preferences.matches(event, "upgrade"): research()
		if preferences.matches(event, "tech"): hud.open_tech()
		if preferences.matches(event, "heal"): heal()
		if preferences.matches(event, "kit"): use_medkit()
		if preferences.matches(event, "stop"): stop_order()
	if not event is InputEventMouseButton or not event.pressed: return
	if paused or session.phase in ["won", "lost"]: return
	var p := ground_at(event.position)
	if event.button_index == MOUSE_BUTTON_LEFT:
		if not build_mode.is_empty(): place_building(board.cell_at(p))
		else:
			selected_id = -1
			for b in session.buildings:
				if b.hp > 0 and board.point(b.cell).distance_to(p) < 1.5: selected_id = b.id
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if not build_mode.is_empty():
			build_mode = ""
			return
		command(p)

func select_build(kind: String) -> void:
	if paused or session.phase != "playing": return
	build_mode = kind
	hud.notification_time = 0

func placement_error(cell: Vector2i) -> String:
	if build_mode.is_empty(): return ""
	if not vision.is_visible(cell): return "需要先探索此处"
	if board.structures.has(cell) or not building_at(cell).is_empty(): return "此处已有建筑或设施"
	if not board.is_open(cell): return "此处被障碍、水域或陡坡阻挡"
	if not board.can_build(cell): return "坡地或地表不适合建造，请选择平坦区域"
	var p: Vector3 = board.point(cell)
	if p.distance_to(extraction) < 5: return "请保持撤离区畅通"
	if p.distance_to(hero.position) < 1.5: return "幸存者占据此位置"
	for d in dinosaurs:
		if d.health > 0 and p.distance_to(d.position) < 1.7: return "恐龙占据此位置"
	if board.route(hero.position, p, true).is_empty() and p.distance_to(hero.position) > 3: return "无法到达施工位置"
	if p.distance_to(hero.position) > 12: return "距离过远，请让幸存者靠近"
	return session.can_afford(build_mode)

func placement_warning(cell: Vector2i) -> String:
	if build_mode.is_empty(): return ""
	var warning: String = build_access.warning(cell)
	if not warning.is_empty() and build_mode == "gate": warning += "；电门施工完成并打开后可通行"
	return warning

func place_building(cell: Vector2i, accepted_risk: bool = false) -> void:
	if paused or not started: return
	var error := placement_error(cell)
	if not error.is_empty():
		hud.toast(error)
		sound.play_ui("warning")
		pointer_feedback.confirm({"kind": "blocked", "position": board.point(cell)}, false)
		return
	var warning := placement_warning(cell)
	if not warning.is_empty() and not accepted_risk:
		var kind := build_mode
		hud.confirm_discard(warning + "。\n建议换个位置或预留电门。仍要在此建造%s吗？\n确认前不扣资源；建成后也可拆除。" % Catalog.BUILDINGS[kind].name, func():
			paused = hud.confirmation_was_paused
			build_mode = kind
			place_building(cell,true))
		return
	var b: Dictionary = session.build(build_mode, cell)
	if b.is_empty(): return
	b.remaining = Regions.construction_remaining(b.kind, board.point(cell), b.remaining)
	board.block_building(cell, b.id)
	create_building_visual(b)
	selected_id = b.id
	worker.assign("build", board.point(cell), b.id)
	pointer_feedback.confirm({"kind": "build", "position": board.point(cell)})
	sound.play_ui("click")
	hud.toast("开始建造：" + Catalog.BUILDINGS[build_mode].name)
	if not Input.is_physical_key_pressed(KEY_SHIFT): build_mode = ""

func create_building_visual(b: Dictionary) -> void:
	if not model_cache.has(b.kind): model_cache[b.kind] = load("res://scenes/models/%s.tscn" % ("lab" if b.kind == "laboratory" else b.kind))
	var n: Node3D = model_cache[b.kind].instantiate()
	n.position = board.point(b.cell)
	add_child(n)
	if vision: vision.shade(n)
	scenery.prepare_building(n, b.kind)
	scenery.update_building(n, b)
	visuals[b.id] = n

func building_at(cell: Vector2i) -> Dictionary:
	for b in session.buildings:
		if b.cell == cell and b.hp > 0: return b
	return {}

func selected_building() -> Dictionary:
	for b in session.buildings:
		if b.id == selected_id and b.hp > 0: return b
	return {}

func demolish_building(id: int) -> void:
	if not started or paused or hero.health <= 0: return
	var b: Dictionary = session.building(id)
	var refund: Dictionary = session.demolish(id)
	if refund.is_empty(): return
	if board.structures.get(b.cell, -1) == id: board.remove_building(b.cell)
	if visuals.has(id):
		visuals[id].hide()
		visuals[id].queue_free()
		visuals.erase(id)
	var returning: bool = order == "return" and worker.target_id == id
	var using_target: bool = worker.target_id == id and order in ["build", "repair", "heal"]
	var mining_target: bool = order == "gold" and board.cell_at(worker.resource_target) == b.cell
	if using_target or mining_target or returning:
		stop_order()
		worker.target_id = -1
		if worker.cargo > 0: worker.begin_return()
	if selected_id == id: selected_id = -1
	build_mode = ""
	weather.update_roofs()
	vision.update()
	sound.play_at("hammer", board.point(b.cell), -4)
	work_impact(board.point(b.cell), Color("bfa47a"))
	hud.toast("已拆除%s，返还 %d 木材 / %d 黄金。" % [Catalog.BUILDINGS[b.kind].name, refund.wood, refund.gold])
	hud.refresh(0)

func go_to_extraction() -> void:
	if paused or not extraction_feedback.available(): return
	build_mode = ""
	command(extraction)

func context_at(p: Vector3) -> Dictionary:
	# Cursor and commands resolve the same target, without revealing hidden objects.
	var cell := board.cell_at(p)
	if not board.inside(cell): return {"kind": "blocked", "position": p}
	for d in dinosaurs:
		if d.health > 0 and d.visible and d.position.distance_to(p) < 1.8:
			return {"kind": "attack", "position": d.position, "id": d.get_instance_id()}
	var site: String = adventure.at_point(p)
	if not site.is_empty(): return {"kind": "inspect", "position": board.point(adventure.data().sites[site].cell), "site": site}
	var b := building_at(cell)
	var target := board.point(cell)
	if not b.is_empty():
		if b.remaining > 0 and not b.get("upgrading", false): return {"kind": "build", "position": target, "id": b.id}
		if b.remaining <= 0:
			if b.kind == "gate": return {"kind": "gate", "position": target, "id": b.id}
			if b.kind == "fossil": return {"kind": "gold", "position": target}
			if b.kind == "tent" and worker.cargo > 0: return {"kind": "return", "position": target}
			if b.hp < Catalog.BUILDINGS[b.kind].hp: return {"kind": "repair", "position": target, "id": b.id}
	if trees.has(cell) and vision.explored.has(cell): return {"kind": "wood", "position": target}
	return {"kind": "move", "position": target}

func command(p: Vector3) -> void:
	var target := context_at(p)
	var kind: String = target.kind
	if kind == "blocked":
		if pointer_feedback: pointer_feedback.confirm(target, false)
		return
	if kind == "inspect":
		hud.expedition_panel.open(target.site)
		return
	if kind == "gate":
		toggle_gate(session.building(target.id))
		if pointer_feedback: pointer_feedback.confirm(target)
		return
	adventure.cancel_job()
	selected_id = -1
	worker.recovery = 0
	destination.visible = false
	order_target = target.position
	match kind:
		"build", "repair": worker.assign(kind, target.position, target.id)
		"wood", "gold": worker.assign(kind, target.position)
		"return":
			worker.resource_kind = ""
			worker.begin_return()
		_:
			order = kind
			if kind == "attack": hero.target_id = target.id
			hero.route = board.route(hero.position, order_target, true) if kind == "attack" else worker.work_route("move", order_target)
			hero_route_revision = board.revision
			if hero.route.is_empty() and hero.position.distance_to(order_target) > 3:
				hud.toast("无法到达目标。清理树木或更换路线。")
				order = "idle"
			else:
				destination.position = (hero.route[-1] if not hero.route.is_empty() else order_target) + Vector3.UP * 0.12
				destination.visible = true
	if pointer_feedback: pointer_feedback.confirm(target, order != "idle")

func order_description() -> String:
	return {"idle": "等待命令", "move": "正在移动", "wood": "正在采集木材", "gold": "正在挖掘化石", "attack": "正在攻击恐龙", "build": "正在施工（右键工地可继续）", "repair": "正在修理", "return": "正在返送资源", "waiting_dropoff": "等待可用帐篷", "heal": "返回帐篷治疗（每秒 1 金，%s / %s）" % [preferences.key_name("heal"), preferences.key_name("stop")], "expedition": "前往设施调查（%s 可中断）" % preferences.key_name("stop")}.get(order, "等待命令")

func update_order(dt: float) -> void:
	var route_changed := false
	if hero_route_revision != board.revision and order not in ["idle", "waiting_dropoff"]:
		hero.route = worker.work_route(order, order_target)
		hero_route_revision = board.revision
		route_changed = true
	if order == "move" and hero.route.is_empty():
		if hero.movement_blocked:
			hero.route = worker.work_route("move",order_target)
			if not hero.route.is_empty() and hero.segment_open(hero.position,hero.route[0]): return
			hero.route.clear()
			hud.toast("通路受阻，移动已停止；可开门、拆除建筑或另选路线。")
		elif route_changed and hero.position.distance_to(order_target) > 3:
			hud.toast("路线已被阻断；可开门、拆除建筑或另选路线。")
		order = "idle"
		destination.visible = false
	if order == "attack":
		var target = instance_from_id(hero.target_id)
		if not is_instance_valid(target) or target.health <= 0 or not target.visible:
			stop_order()
			return
		order_target = target.position
		if hero.position.distance_to(order_target) > 9:
			if hero.path_cooldown <= 0:
				hero.route = board.route(hero.position, order_target, true)
				hero.path_cooldown = 0.7
		else:
			hero.route.clear()
			if hero.attack_cooldown <= 0:
				target.health -= session.survivor_damage()
				dino_ai.provoke(target, "hero", -1, hero.position)
				dino_ai.emit_noise(hero.position, 22.0, "hero")
				hero.attack_cooldown = 0.7
				hero.swing = 1
				hero.visual.face(target.position - hero.position, 1)
				hero.play_animation("attack", 0)
				sound.play_at("shot", hero.position)
				tracer(hero.position + Vector3.UP * 1.5, target.position + Vector3.UP, Color("e6cd8e"))

func update_buildings(dt: float) -> void:
	for b in session.buildings:
		if b.hp <= 0:
			if visuals.has(b.id):
				sound.play_at("collapse", board.point(b.cell))
				dino_ai.emit_noise(board.point(b.cell), 11.0)
				visuals[b.id].queue_free()
				visuals.erase(b.id)
				board.remove_building(b.cell)
				hud.toast(Catalog.BUILDINGS[b.kind].name + "被摧毁了！")
			continue
		var n: Node3D = visuals[b.id]
		scenery.update_building(n, b)
		if b.remaining > 0: continue
		if b.kind == "gate":
			update_gate(b, dt)
			if b.get("open", false): continue
		if b.kind not in ["tower", "shelter", "gate"] or session.supply() < session.demand(): continue
		b.cooldown -= dt
		var nearest: Node3D = null
		var best := 15.625 if b.kind == "tower" else 2.8
		for d in dinosaurs:
			var distance := n.position.distance_to(d.position)
			if d.health > 0 and d.visible and distance < best:
				best = distance
				nearest = d
		if nearest:
			var direction := nearest.position - n.position
			if b.kind == "tower": n.get_node("Model/Gun").rotation.y = atan2(direction.x, direction.z)
			if b.cooldown <= 0:
				b.cooldown = 1.0
				sound.play_at("bow" if b.kind == "tower" else "electric", n.position)
				nearest.health -= session.defense_multiplier() * (10 if b.kind == "tower" else 15) * (1.5 if Regions.at(n.position) == "mountain" else 1.0)
				dino_ai.provoke(nearest, "building", b.id, n.position)
				dino_ai.emit_noise(n.position, 14.0 if b.kind == "tower" else 8.0, "building", b.id)
				tracer(n.position + Vector3.UP * 2.1, nearest.position + Vector3.UP * 1.2, Color("f5d087"))

func spawn_dinosaur(at: Vector3 = Vector3(10000, 0, 0), species: String = "raptor") -> Node3D:
	var p := at
	if p.x > 1000:
		var found := false
		for attempt in range(50):
			p = board.point(Vector2i(rng.randi_range(2, Board.SIDE - 3), rng.randi_range(2, Board.SIDE - 3)))
			if dino_ai.safe_spawn(p) and board.body_open(p, Board.species_radius(species)):
				found = true
				break
		if not found: return null
	if not board.is_open(board.cell_at(p)): return null
	var d: Node3D = (TrexScene if species in ["trex", "young_trex"] else DinoScene).instantiate()
	d.is_dinosaur = true
	d.body_radius = Board.species_radius(species)
	d.set_meta("save_id", session.next_dinosaur_id)
	session.next_dinosaur_id += 1
	var spec: Array = {"raptor": [100.0, 350.0, 1.0, 12.0, 1.0], "small_raptor": [65.0, 320.0, 0.72, 6.0, 1.5], "trex": [1000.0, 280.0, 1.5, 20.0, 1.4], "young_trex": [350.0, 215.0, 1.2, 15.0, 1.2]}[species]
	d.health = spec[0]
	d.max_health = d.health
	d.speed = spec[1] / 64.0
	d.scale *= spec[2]
	d.attack_damage = spec[3]
	d.attack_interval = spec[4]
	d.set_meta("base_speed", d.speed)
	d.set_meta("base_interval", d.attack_interval)
	d.set_meta("species", species)
	d.position = p
	d.navigation = board
	add_child(d)
	dinosaurs.append(d)
	dino_ai.register(d, species)
	d.visible = vision.is_visible(board.cell_at(d.position))
	return d

func update_dinosaurs(dt: float) -> void:
	dino_ai.update(dt)

func tracer(a: Vector3, b: Vector3, color: Color) -> void:
	if a.distance_squared_to(b) < 0.000001: return
	var n := mesh_box(Vector3(0.045, 0.045, a.distance_to(b)), color, (a + b) / 2)
	var direction := (b - a).normalized()
	n.look_at(b, Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP)
	n.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	effects.append({"node": n, "remaining": 0.1})

func update_effects(dt: float) -> void:
	for fx in effects.duplicate():
		fx.remaining -= dt
		if fx.has("follow"):
			if is_instance_valid(fx.follow) and fx.follow.health > 0:
				fx.node.position = fx.follow.position + Vector3.UP * 0.12
				fx.node.visible = fx.follow.visible
			else: fx.remaining = 0
		if fx.has("velocity"):
			fx.velocity.y -= dt * 4
			fx.node.position += fx.velocity * dt
			fx.node.rotate_x(dt * 3)
			fx.node.scale = Vector3.ONE * clampf(fx.remaining / 0.25, 0, 1)
		if fx.remaining <= 0:
			fx.node.queue_free()
			effects.erase(fx)

func work_impact(at: Vector3, color: Color) -> void:
	var contact: Vector3 = hero.visual.work_tip() if hero.animation_state in ["chop", "mine", "build"] else hero.position.move_toward(at, 0.85) + Vector3.UP * 0.85
	for i in range(5):
		var angle: float = i * TAU / 5 + hero.age
		var chip := mesh_box(Vector3(0.06,0.045,0.09),color,contact)
		effects.append({"node":chip,"remaining":0.45,"velocity":Vector3(cos(angle)*0.7,0.6+i*0.12,sin(angle)*0.7)})

func research() -> void:
	if paused: return
	var result: String = session.research(selected_id)
	if result.is_empty():
		visuals[selected_id].queue_free()
		var b := selected_building()
		if Regions.at(board.point(b.cell)) == "swamp": b.remaining *= 0.3
		create_building_visual(b)
	hud.toast("开始升级实验室。" if result.is_empty() else result)

func toggle_pause() -> void:
	if not started: return
	if session.phase in ["won", "lost"]: return
	paused = not paused

func start_session(duration: float, mode: String = "classic", content_seed: int = 0, profession: String = "") -> void:
	session.mode = mode
	session.duration = duration
	if not profession.is_empty() and Session.PROFESSIONS.has(profession): session.profession = profession
	hero.speed = session.survivor_speed()
	hero.max_health = session.survivor_max_health()
	hero.health = hero.max_health
	if mode == "standard": director.configure()
	started = true
	paused = false
	camera_rig.center(true)
	adventure.initialize(content_seed)
	sound.play_ui("ready")

func prepare_demo() -> void:
	session.wood = 300
	session.gold = 250
	for entry in [["tent", Vector2i(63, 62)], ["fire", Vector2i(66, 63)], ["generator", Vector2i(67, 62)], ["shelter", Vector2i(63, 60)], ["tower", Vector2i(64, 61)], ["lab", Vector2i(62, 63)], ["fossil", Vector2i(63, 65)], ["gate", Vector2i(65, 60)]]:
		clear_tree(entry[1])
		var b: Dictionary = session.build(entry[0], entry[1])
		if b.is_empty(): continue
		b.remaining = 0.0
		board.block_building(b.cell, b.id)
		create_building_visual(b)
	var d := spawn_dinosaur(board.point(Vector2i(64, 58)))
	if d: d.visual.model.rotation.y = 0
	session.wood = 84
	session.gold = 52

func capture() -> void:
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(capture_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := picture.save_png(absolute)
	print("CAPTURE ", absolute, " result=", error)
	get_tree().quit(0 if error == OK else 1)

func toggle_gate(b: Dictionary) -> void:
	if b.get("gate_timer", 0.0) > 0: return
	b.gate_timer = 5.0
	dino_ai.emit_noise(board.point(b.cell), 6.0, "building", b.id)
	sound.play_at("gate", board.point(b.cell))
	hud.toast("电门将在 5 秒后" + ("关闭。" if b.get("open", false) else "打开。"))

func update_gate(b: Dictionary, dt: float) -> void:
	if b.get("gate_timer", 0.0) <= 0: return
	b.gate_timer = maxf(0, b.gate_timer - dt)
	if b.gate_timer > 0: return
	if b.get("open", false):
		if board.cell_at(hero.position) == b.cell:
			hud.toast("门口有人，无法关闭电门。")
			return
		for d in dinosaurs:
			if d.health > 0 and board.cell_at(d.position) == b.cell:
				hud.toast("门口有恐龙，无法关闭电门。")
				return
		b.open = false
		board.block_building(b.cell, b.id)
	else:
		b.open = true
		board.remove_building(b.cell)
	visuals[b.id].get_node("Model/Leaf").rotation.y = -PI * 0.48 if b.open else 0.0

func stop_order() -> void:
	if pointer_feedback: pointer_feedback.pulse_left = 0
	if adventure: adventure.cancel_job()
	order = "idle"
	hero.route.clear()
	hero.current_speed = 0
	hero.target_id = -1
	worker.recovery = 0
	worker.clock = 0
	worker.pose_clock = 0
	destination.visible = false

func heal() -> void:
	if paused or session.phase not in ["playing", "evacuate"]: return
	if hero.health >= hero.max_health:
		hud.toast("生命已满，无需治疗。")
		return
	if session.gold < 1:
		hud.toast("治疗需要黄金：每秒 1 金，恢复 %d 生命。" % (25 if session.technologies.has("medicine") else 10))
		return
	var nearest: Dictionary = {}
	var best := INF
	for b in session.buildings:
		if b.hp <= 0 or b.kind != "tent" or b.remaining > 0: continue
		var p: Vector3 = board.point(b.cell)
		var route: PackedVector3Array = board.route(hero.position, p, true)
		if route.is_empty() and hero.position.distance_to(p) > 3: continue
		if route.size() < best:
			best = route.size()
			nearest = b
	if nearest.is_empty():
		hud.toast("需要一座可到达、已完成的帐篷。")
		return
	worker.assign("heal", board.point(nearest.cell), nearest.id)
	hud.toast("返回帐篷治疗，每秒消耗 1 黄金。右键或 X 可中断。")

func near_completed_tent() -> bool:
	for b in session.buildings:
		if b.hp > 0 and b.kind == "tent" and b.remaining <= 0 and hero.position.distance_to(board.point(b.cell)) <= 2.8:
			return true
	return false

func eat_food() -> void:
	if paused or session.phase not in ["playing", "evacuate"]: return
	if session.eat_food():
		hud.toast("补充食物，饱腹度恢复。")
		sound.play_ui("ready")
	else:
		hud.toast("没有可食用的食物；可在营火烤制肉类。")

func cook_food() -> void:
	if paused or session.phase not in ["playing", "evacuate"]: return
	if session.cook_food():
		hud.toast("营火烤制完成，获得熟肉。")
		sound.play_ui("complete")
	else:
		hud.toast("需要生肉和已建成的营火。")

func begin_technology(tech: String) -> void:
	var error: String = session.begin_research(tech)
	hud.toast("开始研究：" + Catalog.TECH[tech].name if error.is_empty() else error)
	hud.refresh_tech()

func save_game(automatic: bool = false) -> void:
	if demo_mode: return
	var error: String = SaveStore.write(self, automatic)
	if error.is_empty():
		save_status = ("自动存档" if automatic else "手动存档") + " · " + Time.get_time_string_from_system()
		if not automatic: hud.toast("已保存。")
	else:
		save_status = error
		hud.toast("保存失败：" + error)
	hud.refresh_save_info()

func load_game(slot: String = "") -> void:
	var result: Dictionary = SaveStore.latest() if slot.is_empty() else SaveStore.read_slot(slot)
	if result.has("error"):
		hud.toast(result.error)
		return
	SaveStore.pending = result.data
	SaveStore.pending_message = "检测到损坏记录，已载入最近的完好存档" if result.get("recovered", false) else "已载入存档"
	var error := get_tree().reload_current_scene()
	if error != OK:
		SaveStore.pending = {}
		hud.toast("载入失败，当前游戏仍保留。")

func exit_game() -> void:
	if started and session.phase in ["playing", "evacuate"]:
		var error: String = SaveStore.write(self, true)
		if not error.is_empty():
			hud.toast("退出前保存失败：" + error + "。可选择直接退出。")
			hud.confirm_discard("保存失败，仍然退出？", func(): get_tree().quit())
			return
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(hud): exit_game()
	if persistence_enabled and what == NOTIFICATION_APPLICATION_FOCUS_OUT and started and session.phase in ["playing", "evacuate"]:
		paused = true

func update_lighting() -> void:
	var daylight := (cos(((session.elapsed + session.evacuation_elapsed) / Catalog.DAY_SECONDS) * TAU - 0.5) + 1.0) / 2.0
	night = daylight < 0.3
	sun.light_energy = lerpf(0.16, 0.82, daylight)
	sun.light_color = Color("849bc1").lerp(Color("fff0d6"), daylight)
	environment.ambient_light_energy = lerpf(0.28, 0.42, daylight)
	environment.ambient_light_color = Color("7790af").lerp(Color("b9c8bd"), daylight)
	environment.fog_light_color = Color("253d50").lerp(Color("819794"), daylight)
	if weather:
		weather.update()
		weather.apply_lighting()

func use_medkit() -> void:
	var error: String = adventure.use_kit()
	hud.toast("已使用急救包，恢复 50 生命。" if error.is_empty() else error)
