extends SceneTree
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
const Catalog = preload("res://scripts/catalog.gd")
var world: Node
var folder := "res://captures/contact"

func _initialize() -> void: call_deferred("run")

func shot(title: String) -> void:
	for frame in range(4):
		world.paused = false
		world.hud.refresh(0)
		await process_frame
	RenderingServer.force_draw(false)
	if world.hero.animation_state in ["chop", "mine", "build"]:
		var contact: RefCounted = world.hero.visual.contact
		var prop: Node3D = world.hero.visual.axe if world.hero.animation_state == "chop" else (world.hero.visual.pickaxe if world.hero.animation_state == "mine" else world.hero.visual.hammer)
		print("RENDERED CONTACT ", title, " tip=", world.hero.visual.work_tip(), " tool=", prop.global_transform, " hand=", contact.skeleton.to_global(contact.pose("handR").origin))
	var result := root.get_texture().get_image().save_png(folder.path_join(title + ".png"))
	print("CONTACT SCREENSHOT ", title, " result=", result)

func aperture(value: float) -> void:
	for mat in world.scenery.obstructions.materials.values(): mat.set_shader_parameter("cutout_enabled",value)

func close_camera(focus: Vector3, offset: Vector3, size: float) -> void:
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.position = focus + offset
	world.camera.look_at(focus)
	world.camera.size = size
	world.scenery.update_view(0)

func run() -> void:
	Save.directory = "user://contact_capture_fixture"
	Preferences.file_path = "user://contact_capture_fixture/preferences.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	world.pointer_feedback.hide()
	world.hud.hide()
	# Real nearest reachable tree and the same worker route used in play.
	var cells: Array = world.trees.keys()
	cells.sort_custom(func(a,b): return world.board.point(a).distance_squared_to(world.hero.position) < world.board.point(b).distance_squared_to(world.hero.position))
	var tree := Vector3.ZERO
	var found_tree := false
	for cell in cells:
		var target: Vector3 = world.board.point(cell)
		var route: PackedVector3Array = world.worker.work_route("wood",target)
		if route.is_empty() or not world.worker.wood_contact(route[-1], target): continue
		found_tree = true
		tree = target
		world.hero.position = route[-1]
		break
	if not found_tree:
		push_error("No reachable tree for contact capture")
		world.free()
		quit(1)
		return
	world.vision.update()
	var direction: Vector3 = (tree-world.hero.position).normalized()
	world.hero.visual.face(direction,1)
	var focus: Vector3 = world.hero.position + Vector3.UP
	close_camera(focus,Vector3(direction.z*5,3,-direction.x*5)-direction*2,6)
	world.hero.work_pose("chop",tree,0.85,1)
	await shot("chop-windup")
	world.hero.work_pose("chop",tree,1.1,1)
	world.work_impact(tree,Color("ad8756"))
	await shot("chop-contact")
	print("CHOP contact=", world.hero.visual.work_tip(), " target=",tree," worker_distance=",world.hero.position.distance_to(tree))
	# Isolated visual facility fixture: does not alter saves or production economy.
	var base: Vector3 = world.board.point(Vector2i(65,62))
	var fossil: Node3D = load("res://scenes/models/fossil.tscn").instantiate()
	world.add_child(fossil)
	fossil.position = base + Vector3(0,0,1.5)
	world.vision.shade(fossil)
	world.hero.position = base
	world.hero.work_pose("mine",fossil.position,1.1,1)
	world.vision.update()
	close_camera(base+Vector3(0,0.8,0.6),Vector3(5,3,-3),5.5)
	await shot("mine-contact")
	fossil.free()
	var tent: Node3D = load("res://scenes/models/tent.tscn").instantiate()
	world.add_child(tent)
	tent.position = base + Vector3(0,0,1.7)
	world.vision.shade(tent)
	world.scenery.prepare_building(tent,"tent")
	var tent_data := {"kind":"tent","remaining":5.0}
	tent_data.hp = Catalog.max_health(tent_data)
	world.scenery.update_building(tent,tent_data)
	world.hero.work_pose("build",tent.position,0.65,1)
	close_camera(base+Vector3(0,1,0.8),Vector3(6,3,-3),7)
	await shot("build-contact")
	tent.free()
	world.hero.advance(0.3)
	var tower: Node3D = load("res://scenes/models/tower.tscn").instantiate()
	world.add_child(tower)
	tower.position = base + Vector3(1.8,0,1.8)
	world.vision.shade(tower)
	world.scenery.prepare_building(tower,"tower")
	var tower_data := {"kind":"tower","remaining":0}
	tower_data.hp = Catalog.max_health(tower_data)
	world.scenery.update_building(tower,tower_data)
	close_camera(base+Vector3.UP,Vector3(8,7,8),9)
	aperture(0)
	await shot("building-occlusion-before")
	aperture(1)
	await shot("building-occlusion-after")
	tower.free()
	var rock: Node3D = load("res://scenes/models/rock.tscn").instantiate()
	world.add_child(rock)
	rock.position = base+Vector3(1.1,0,1.1)
	rock.scale = Vector3.ONE*2.3
	world.vision.shade(rock)
	world.scenery.obstructions.register(rock)
	close_camera(base+Vector3.UP*0.8,Vector3(8,6.3,8),8)
	aperture(0)
	await shot("rock-occlusion-before")
	aperture(1)
	await shot("rock-occlusion-after")
	rock.free()
	world.hud.show()
	world.camera_size = 18
	world.camera_rig.target_pitch = deg_to_rad(38)
	world.camera_rig.center(true)
	world.update_camera(0)
	await shot("gameplay-overview")
	world.free()
	quit()
