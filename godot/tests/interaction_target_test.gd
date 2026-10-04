extends SceneTree
## Projected model surfaces must resolve to the same target as hover and commands.
var w: Node
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	preload("res://scripts/preferences.gd").file_path = "user://interaction_target_fixture/preferences.cfg"
	w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.start_session(1500, "standard")
	w.paused = false
	check_ring_alignment()
	# Use a real batched tree near the survivor, with a projected upper trunk.
	var cells: Array = w.trees.keys()
	cells.sort_custom(func(a,b): return w.board.point(a).distance_squared_to(w.hero.position) < w.board.point(b).distance_squared_to(w.hero.position))
	var cell: Vector2i = cells[0]
	var tree: Node3D
	var screen := Vector2.ZERO
	var ground := Vector3.ZERO
	var sampled := false
	for candidate in cells.slice(0, 32):
		tree = w.trees[candidate].node
		w.vision.explored[candidate] = true
		w.camera_rig.following = false
		w.camera_focus = w.board.point(candidate)
		w.camera_rig.target_pitch = deg_to_rad(38)
		w.camera_size = 18
		w.update_camera(0)
		await process_frame
		await physics_frame
		w.paused = false
		for mesh in tree.find_children("*", "MeshInstance3D", true, false):
			if not "Trunk" in str(mesh.name): continue
			var vertices: PackedVector3Array = mesh.mesh.get_faces()
			for i in range(0, vertices.size(), 3):
				var surface: Vector3 = mesh.global_transform * ((vertices[i] + vertices[i+1] + vertices[i+2]) / 3.0)
				if surface.y < w.board.point(candidate).y + 1.0: continue
				screen = w.camera.unproject_position(surface)
				ground = w.ground_at(screen)
				if w.board.cell_at(ground) == candidate: continue
				cell = candidate
				sampled = true
				break
			if sampled: break
		if sampled: break
	expect(sampled, "Visible trunk surface projects away from its ground cell")
	var target: Dictionary = w.context_at(w.action_point(screen, ground))
	expect(target.kind == "wood" and w.board.cell_at(target.position) == cell, "Clicking the upper trunk selects this tree, not the ground behind it")
	w.pointer_feedback.update_hover(screen, ground)
	expect(w.pointer_feedback.cursor_kind == "wood", "Hovering the visible trunk displays its axe")
	var start := Time.get_ticks_usec()
	for i in range(60): w.action_point(screen + Vector2(i % 6, i % 5), ground)
	print("PICK average ms: ", (Time.get_ticks_usec() - start) / 60000.0)
	w.interaction_targets.refresh(true)
	var hover: Dictionary = w.interaction_targets.layers.hover
	expect(hover.root.visible and hover.node == tree and hover.root.get_child_count() == 1 and hover.ring.is_visible_in_tree(), "Hovered batched tree gets only a ground ring")
	var click := InputEventMouseButton.new()
	click.position = screen
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	w._unhandled_input(click)
	expect(w.order == "wood" and w.board.cell_at(w.order_target) == cell, "Left click dispatches work on the exact highlighted trunk")
	w.interaction_targets.refresh(false)
	expect(not hover.root.visible and w.interaction_targets.layers.order.root.visible, "Working tree remains highlighted after the mouse leaves")
	if "--capture-targets" in OS.get_cmdline_user_args(): await shot("01-working-tree")
	w.interaction_targets.refresh(true, true)
	expect(hover.material.albedo_color == w.interaction_targets.BLOCKED_COLOR, "Unreachable hovered objects are visibly red")
	w.build_mode = "tent"
	w.interaction_targets.refresh(true)
	expect(not hover.root.visible and not w.interaction_targets.layers.order.root.visible, "Placement hides unrelated object highlights")
	w.build_mode = ""
	w.vision.explored.erase(cell)
	var unknown: Dictionary = w.context_at(w.action_point(screen, ground))
	expect(unknown.kind != "wood" or w.board.cell_at(unknown.position) != cell, "Unknown trees cannot be disclosed by model picking")
	w.vision.explored[cell] = true
	w.stop_order()
	w.interaction_targets.refresh(false)
	expect(not w.interaction_targets.layers.order.root.visible, "Stopping clears the work target")
	w.prepare_demo()
	for b in w.session.buildings:
		w.camera_focus = w.board.point(b.cell)
		w.update_camera(0)
		var p: Vector3 = w.board.point(b.cell)
		w.interaction_targets.hover_target = w.context_at(p)
		w.interaction_targets.refresh(true)
		expect(hover.root.visible and hover.node == w.visuals[b.id].get_node("Model"), "Building highlight: " + b.kind)
		if b.kind == "fossil":
			if "--capture-targets" in OS.get_cmdline_user_args(): await shot("02-excavation-hover")
			w.order = "gold"
			w.order_target = p
			w.interaction_targets.refresh(false)
			expect(w.interaction_targets.layers.order.node == w.visuals[b.id].get_node("Model"), "Mining keeps the excavation field highlighted")
			if "--capture-targets" in OS.get_cmdline_user_args(): await shot("02-excavation")
			w.stop_order()
			w.selected_id = b.id
			w.interaction_targets.refresh(false)
			expect(w.interaction_targets.layers.selected.root.visible, "Selected building remains highlighted")
			w.selected_id = -1
		if b.kind == "tent":
			for kind in ["build", "repair", "return", "heal"]:
				w.order = kind
				w.worker.target_id = b.id
				w.interaction_targets.refresh(false)
				expect(w.interaction_targets.layers.order.node == w.visuals[b.id].get_node("Model"), "Action highlight: " + kind)
	w.stop_order()
	var d: Node3D = w.spawn_dinosaur(w.hero.position, "raptor")
	d.visible = true
	w.order = "attack"
	w.hero.target_id = d.get_instance_id()
	w.camera_focus = d.position
	w.update_camera(0)
	w.interaction_targets.refresh(false)
	expect(w.interaction_targets.layers.order.root.visible, "Attacked dinosaur has a persistent ground ring")
	if "--capture-targets" in OS.get_cmdline_user_args(): await shot("03-attack")
	d.visible = false
	w.interaction_targets.refresh(false)
	expect(not w.interaction_targets.layers.order.root.visible, "A dinosaur leaving vision loses its highlight")
	w.order = "wood"
	w.order_target = w.board.point(cell)
	w.interaction_targets.hover_target = {"kind": "wood", "position": w.order_target}
	w.clear_tree(cell)
	await process_frame
	w.interaction_targets.refresh(true)
	expect(not hover.root.visible and not w.interaction_targets.layers.order.root.visible, "Harvested tree leaves no stale highlight")
	w.paused = true
	w.interaction_targets.refresh(true)
	for layer in w.interaction_targets.layers.values(): expect(not layer.root.visible, "Pause hides all target effects")
	# A building must remain pickable while its render model is hidden during a
	# vision/cinematic update; otherwise a repair click falls through to movement.
	var repair_building: Dictionary = w.session.buildings[0]
	repair_building.hp = maxf(1.0, w.Catalog.max_health(repair_building) * 0.5)
	w.vision.explored[repair_building.cell] = true
	var repair_visual: Node3D = w.visuals[repair_building.id]
	repair_visual.hide()
	w.paused = false
	w.camera_focus = w.board.point(repair_building.cell)
	w.camera_size = 18
	w.update_camera(0)
	await process_frame
	var repair_screen: Vector2 = w.camera.unproject_position(w.board.point(repair_building.cell) + Vector3.UP * 2.0)
	var repair_ground: Vector3 = w.ground_at(repair_screen)
	var repair_target: Dictionary = w.context_at(w.action_point(repair_screen, repair_ground))
	expect(repair_target.kind == "repair" and repair_target.id == repair_building.id, "Hidden damaged building keeps a stable repair selection target")
	repair_visual.show()
	w.free()
	print("INTERACTION TARGET: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)

func shot(label: String) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	w.vision.update()
	w.scenery.update_view(0)
	w.hud.refresh(0)
	for i in range(5): await process_frame
	RenderingServer.force_draw(false)
	var folder := "res://captures/interaction-targets"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func check_ring_alignment() -> void:
	var fixture := Node3D.new()
	w.add_child(fixture)
	fixture.position = Vector3(5, 0, -3)
	fixture.rotation.y = 0.6
	fixture.scale = Vector3(1.4, 1, 0.8)
	var model := Node3D.new()
	fixture.add_child(model)
	model.position = Vector3(1.2, 0, -0.7)
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = BoxMesh.new()
	trunk.mesh.size = Vector3(0.4, 3, 0.4)
	model.add_child(trunk)
	trunk.position = Vector3(0.3, 1.5, 0.2)
	trunk.hide()
	var canopy := MeshInstance3D.new()
	canopy.name = "Foliage"
	canopy.mesh = BoxMesh.new()
	model.add_child(canopy)
	canopy.position = Vector3(4, 5, 3)
	var expected := model.to_global(Vector3(0.3, 0, 0.2))
	var targets = w.interaction_targets
	targets.show_layer("hover", fixture, targets.HOVER_COLOR, true)
	var layer: Dictionary = targets.layers.hover
	expect(Vector2(layer.center.x, layer.center.z).distance_to(Vector2(expected.x, expected.z)) < 0.001, "Hidden batched trunk foot centers the ring through nested offset, rotation and scale")
	var ring_center: Vector3 = layer.ring.mesh.get_aabb().get_center()
	expect(Vector2(ring_center.x, ring_center.z).distance_to(Vector2(expected.x, expected.z)) < 0.001, "Rendered ring vertices center on the trunk foot rather than the logical pivot")
	fixture.position += Vector3(2, 0, 1)
	targets.show_layer("hover", fixture, targets.HOVER_COLOR, true)
	expect(layer.center.distance_to(expected + Vector3(2, 0, 1)) < 0.001, "Cached base anchor follows object translation")
	trunk.name = "Foundation"
	trunk.show()
	var base: Dictionary = targets.footprint(fixture, false)
	expect(fixture.to_global(base.anchor).distance_to(layer.center) < 0.001, "Building foundation centers the ring independently of asymmetric upper geometry")
	fixture.free()
