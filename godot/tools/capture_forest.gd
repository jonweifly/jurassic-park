extends SceneTree
## Comparable native render samples; debug switches never alter saved gameplay data.
var world: Node

func _initialize() -> void:
	call_deferred("run")

func screenshot(name: String) -> void:
	world.hud.refresh(0)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://captures/%s.png" % name)
	print("SCREENSHOT ",name)

func canopy_fixture() -> bool:
	var start: Vector3 = world.hero.position
	var best := INF
	var fixture := {}
	for cell in world.trees:
		var target: Vector3 = world.board.point(cell)
		if target.distance_to(start) > 14: continue
		var route: PackedVector3Array = world.board.route(start,target,true)
		if route.is_empty() or route.size() > 10: continue
		world.hero.position = route[route.size()-1]
		for leaf in world.trees[cell].node.find_children("*","MeshInstance3D",true,false):
			if not leaf.material_override is ShaderMaterial: continue
			var direction: Vector3 = leaf.global_position-world.hero.position
			world.camera_rig.target_yaw = atan2(direction.x,direction.z)
			world.camera_rig.target_pitch = deg_to_rad(38)
			world.camera_rig.center()
			world.camera_size = 18
			world.update_camera(0)
			var axis: Vector3 = world.camera.global_basis.z
			var offset: Vector3 = leaf.global_position-world.hero.position-Vector3.UP*1.15
			var along := offset.dot(axis)
			if along <= 0.4: continue
			var score := (offset-axis*along).length()
			if score < best:
				best = score
				fixture = {"position":world.hero.position,"yaw":world.camera_rig.target_yaw}
	if fixture.is_empty(): return false
	world.hero.position = fixture.position
	world.camera_rig.target_yaw = fixture.yaw
	world.camera_rig.center()
	world.update_camera(0)
	world.vision.update()
	print("CANOPY closest_projection_m=",best)
	return true

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(3600)
	world.spawn_clocks.clear()
	world.prepare_demo()
	world._physics_process(1.0/30)
	world.update_camera(0)
	world.vision.update()
	var mode := "unbatched" if "--unbatched-forest" in OS.get_cmdline_user_args() else "batched"
	if "--production" in OS.get_cmdline_user_args(): mode = "production"
	var timings := []
	for i in range(180):
		var before := Time.get_ticks_usec()
		world.hud.refresh(0)
		RenderingServer.force_draw(false)
		await process_frame
		if i >= 60: timings.append(float(Time.get_ticks_usec()-before)/1000)
	timings.sort()
	var result := {"mode":mode,"viewport":str(root.get_texture().get_image().get_size()),"iterations":timings.size(),"median_iteration_ms":timings[timings.size()/2],"p95_iteration_ms":timings[int(timings.size()*0.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"source_parts":world.scenery.forest.source_parts,"batches":world.scenery.forest.batches.size()}
	var output := FileAccess.open("res://captures/forest-%s.json" % mode,FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t"))
	output.close()
	print("FOREST ",JSON.stringify(result))
	await screenshot("forest-"+mode)
	if mode != "unbatched" and canopy_fixture():
		for mat in world.scenery.foliage_cache.values()+[world.scenery.leaf_fog]: mat.set_shader_parameter("cutout_enabled",0.0)
		await screenshot("canopy-before")
		world.scenery.update_view()
		await screenshot("canopy-after")
	world.queue_free()
	await process_frame
	quit()
