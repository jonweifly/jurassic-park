extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	preload("res://scripts/feature_policy.gd").peripheral_enabled = true
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func click(control: Control) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func press(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)

func run() -> void:
	Save.directory = "user://variety_input_fixture"
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.hud.refresh(0)
	await process_frame
	await physics_frame
	var start: Button = world.hud.standard_start_button
	world.hud.content_seed_input.text = "bad"
	click(start)
	expect(not world.started, "Invalid seed cannot start a session")
	world.hud.content_seed_input.text = "1826"
	click(start)
	world.paused = false
	world.hud.refresh(0)
	await process_frame
	expect(world.started and world.session.adventure.run.seed == 1826, "Actual start button creates the chosen content draw")
	press(KEY_L)
	world.hud.refresh(0)
	await process_frame
	var panel = world.hud.expedition_panel
	panel.tabs.current_tab = 2
	await process_frame
	var before := Vector2i(world.session.wood, world.session.gold)
	click(panel.contract_buttons[0])
	await process_frame
	expect(world.session.adventure.run.active == world.session.adventure.run.offers[0] and world.paused, "Actual contract button accepts and keeps reading paused")
	expect(Vector2i(world.session.wood, world.session.gold) == before and panel.contract_buttons[1].disabled, "Accepting neither charges nor permits a second reward path")
	click(panel.contract_next)
	await process_frame
	expect(panel.tabs.current_tab == 0 and panel.go_button.visible, "Next-site button selects a known task destination")
	click(panel.go_button)
	world.hud.refresh(0)
	await process_frame
	expect(not panel.panel.visible and not world.paused and world.order == "expedition" and not world.hero.route.is_empty(), "Actual go button closes modal and issues a walking route")
	var initial: Vector3 = world.hero.position
	world._physics_process(0.5)
	expect(world.hero.position.distance_to(initial) > 0.1, "Accepted travel actually moves survivor")
	press(KEY_ESCAPE)
	world.hud.refresh(0)
	await process_frame
	press(KEY_L)
	world.hud.refresh(0)
	await process_frame
	panel.select_site("relay" if world.session.adventure.run.active == "signal" else "cache")
	click(panel.go_button)
	expect(not world.paused and not panel.panel.visible, "Explicit travel from a previously paused journal resumes play")
	world.free()
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.hud.start_selected_session(2700, "classic")
	expect(world.started and world.session.mode == "classic" and world.session.adventure.run.seed > 0 and world.session.adventure.run.plan.size() == 8, "Blank seed starts long mode with a valid random content plan")
	world.free()
	print("VARIETY INPUT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
