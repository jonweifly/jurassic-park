extends SceneTree
const Preferences = preload("res://scripts/preferences.gd")
const Save = preload("res://scripts/save_store.gd")
const OUT := "res://captures/hud-compact"
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func verify(size: Vector2i, label: String) -> void:
	root.size = size
	for frame in range(3): await process_frame
	var bottom_rect: Rect2 = world.hud.bottom.get_global_rect()
	expect(bottom_rect.size.x > 0 and bottom_rect.size.y > 0 and bottom_rect.position.x >= -2 and bottom_rect.position.y >= -2, label + " bottom panel has valid viewport layout")
	expect(world.hud.bottom.offset_bottom >= -8, label + " bottom panel hugs the viewport edge")
	expect(bottom_rect.size.y <= 210, label + " bottom panel remains compact")
	expect(world.hud.minimap.custom_minimum_size.x > world.hud.minimap.custom_minimum_size.y, label + " minimap uses a wider landscape ratio")
	var quest_rect: Rect2 = world.hud.quest_box.get_global_rect()
	var camera_rect: Rect2 = world.hud.camera_panel.get_global_rect()
	# The headless font fallback has a taller line box than the native system font.
	var headless := DisplayServer.get_name() == "headless"
	expect(quest_rect.size.x <= 264 and quest_rect.size.y <= 100, label + " normal objective stays within the reduced edge strip")
	expect(camera_rect.size.x <= 210 and camera_rect.size.y <= (52 if headless else 38), label + " camera controls remain a slim toolbar")
	expect(root.get_visible_rect().encloses(quest_rect) and root.get_visible_rect().encloses(camera_rect), label + " top controls fit the viewport")
	expect(quest_rect.encloses(world.hud.camp_view_button.get_global_rect()) and quest_rect.encloses(world.hud.quest_toggle.get_global_rect()), label + " camp alert and briefing toggle remain clickable inside the strip")
	expect(not world.hud.field_notice.is_visible_in_tree(), label + " routine field information is disclosed on demand")
	for build_button in world.hud.build_buttons.values():
		expect(root.get_visible_rect().encloses(build_button.get_global_rect()), label + " every building choice stays inside the viewport")
	print("HUD EDGE SIZE ", label, ": objective ", quest_rect.size, " camera ", camera_rect.size)
	if not headless:
		RenderingServer.force_draw(false)
		expect(root.get_texture().get_image().save_png(OUT.path_join(label + ".png")) == OK, label + " native HUD capture saved")

func run() -> void:
	var fixture := "user://hud_layout_fixture_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Preferences.file_path = fixture.path_join("preferences.cfg")
	Save.directory = fixture
	world = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500.0, "standard")
	world.hud.refresh(0)
	await verify(Vector2i(1280,800), "wide")
	await verify(Vector2i(1000,800), "windowed")
	await verify(Vector2i(1000,550), "short")
	# Repeated refreshes with changing counters must not move the middle controls.
	var resource_x: float = world.hud.resource_label.get_global_position().x
	var clock_x: float = world.hud.clock_label.get_global_position().x
	world.session.wood = 999
	world.session.elapsed = 61
	world.hud.refresh(0)
	expect(is_equal_approx(world.hud.resource_label.get_global_position().x, resource_x), "resource label has stable horizontal position")
	expect(is_equal_approx(world.hud.clock_label.get_global_position().x, clock_x), "clock label has stable horizontal position")
	var compact_height: float = world.hud.quest_box.size.y
	world.hud.quest_toggle.button_pressed = true
	for frame in range(3): await process_frame
	expect(world.hud.field_notice.is_visible_in_tree() and world.hud.quest_box.size.y > compact_height, "briefing toggle reveals secondary field information")
	world.hud.quest_toggle.button_pressed = false
	for frame in range(3): await process_frame
	expect(is_equal_approx(world.hud.quest_box.size.y, compact_height), "closing briefing releases its occupied playfield area")
	world.session.phase = "evacuate"
	world.session.boarding_progress = 4
	world.hud.refresh(0)
	for frame in range(3): await process_frame
	expect(world.hud.objective.text.contains("回退") and world.hud.boarding_bar.visible and world.hud.extraction_button.visible, "compact mode preserves urgent extraction instructions and progress")
	expect(world.hud.rescue_clock.text.contains("撤离剩余") and world.hud.quest_box.size.y <= 190, "extraction countdown stays visible without restoring the large briefing")
	# Camera height correction is smoothed and must settle when the target is static.
	world.paused = true
	world.camera_rig.center(true)
	world.update_camera(0)
	var camera_position: Vector3 = world.camera.position
	for i in range(12): world.update_camera(1.0 / 60.0)
	expect(world.camera.position.distance_to(camera_position) < 0.01, "static camera does not jitter")
	world.free()
	print("HUD LAYOUT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
