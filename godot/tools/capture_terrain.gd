extends SceneTree
## Native GL camera-pan regression and dry/wet terrain captures.
var folder := "res://captures/terrain-review"
var world: Node
var failures := 0
var report := {}
var samples: Array[Vector3] = []

func _initialize() -> void: call_deferred("run")

func frame(name: String, save: bool = true) -> Array:
	for i in range(4): await process_frame
	# Occluded native windows must still render during automated verification.
	RenderingServer.force_draw(false)
	var picture := root.get_texture().get_image()
	if save: picture.save_png(folder.path_join(name+".png"))
	var values := []
	for at in samples:
		var screen: Vector2 = world.camera.unproject_position(at)
		if screen.x < 3 or screen.y < 3 or screen.x >= picture.get_width()-3 or screen.y >= picture.get_height()-3:
			values.append(-1.0)
			continue
		var color := Color(0,0,0,0)
		for dy in range(-1,2):
			for dx in range(-1,2): color += picture.get_pixel(roundi(screen.x)+dx,roundi(screen.y)+dy)/9.0
		values.append((color.r+color.g+color.b)/3.0)
	return values

func run() -> void:
	var opening := "--opening" in OS.get_cmdline_user_args()
	if opening: folder = "res://captures/opening-replay"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.hud.hide()
	world.pointer_feedback.hide()
	world.camera_rig.following = false
	world.camera_size = 55
	world.weather.preview_kind = 0
	world.weather.update()
	world.vision.image.fill(Color(.48,.48,.48))
	world.vision.texture.update(world.vision.image)
	var water: MeshInstance3D = world.get_node("Island/Water")
	var material: ShaderMaterial = water.material_override
	var layout: RefCounted = world.board.layout
	for z in (range(-23,-9) if opening else range(60,93,2)):
		for x in (range(12,25) if opening else range(72,111,2)):
			var level: float = layout.water_level_at(x,z)
			if level > -90 and level-layout.height_at(x,z) > (0.8 if opening else 1.5): samples.append(Vector3(x,level+.04,z))
	var focus := Vector3(18,0,-14) if opening else Vector3(88,0,73)
	# The optional probe deliberately restores the old two-pass ordering defect
	# on the current geometry. It must be removed for the production verdict.
	var variants := ["after"]
	if "--probe-overlay" in OS.get_cmdline_user_args(): variants = ["overlay-probe","after"]
	for variant in variants:
		water.material_overlay = world.vision.overlay if variant == "overlay-probe" else null
		material.render_priority = 0 if variant == "overlay-probe" else 1
		world.camera_focus = focus
		world.update_camera(0)
		for i in range(12): await process_frame
		var frames := []
		for i in range(48):
			var offset := float(i if i < 24 else 47-i)*.08
			world.camera_focus = focus+Vector3(offset,0,0)
			world.update_camera(0)
			frames.append(await frame("replay-%s-%02d" % [variant,i],i%4 == 0))
		var max_jump := 0.0
		for i in range(1,frames.size()):
			var delta := 0.0
			var count := 0
			for j in range(samples.size()):
				if frames[i][j] >= 0 and frames[i-1][j] >= 0:
					delta += frames[i][j]-frames[i-1][j]
					count += 1
			max_jump = maxf(max_jump,absf(delta)/maxi(count,1))
		report[variant] = {"frames":frames,"sample_count":samples.size(),"max_mean_brightness_jump":max_jump}
		if variant == "after" and (samples.size() < 20 or max_jump > .025):
			push_error("Lake brightness jumps during continuous camera motion: "+str(max_jump))
			failures += 1
		print("TERRAIN REPLAY ",variant," samples=",samples.size()," max_mean_jump=",max_jump)
	FileAccess.open(folder.path_join("replay.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	world.vision.image.fill(Color.WHITE)
	world.vision.texture.update(world.vision.image)
	for region in [{"name":"water","at":Vector3(89,0,73),"size":55.0},{"name":"mountain","at":Vector3(55,0,-55),"size":40.0},{"name":"ground","at":Vector3(4,0,-4),"size":18.0}]:
		world.camera_focus = region.at
		world.camera_size = region.size
		world.update_camera(0)
		await frame("after-"+region.name)
	world.weather.preview_kind = 2
	world.weather.update()
	world.update_camera(0)
	await frame("after-rain")
	world.preferences.values.quality = 0
	world.preferences.apply(world,false)
	world.camera_focus = Vector3(89,0,73)
	world.camera_size = 68
	world.update_camera(0)
	await frame("after-low-far")
	world.free()
	print("TERRAIN CAPTURE: ",failures," failures")
	quit(0 if failures == 0 else 1)
