extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	world.hud.refresh(0)
	expect(not world.hud.extraction_button.visible and not world.hud.boarding_bar.visible, "Opening HUD stays compact")
	world.session.elapsed = 1380
	world.hud.refresh(0)
	expect(world.hud.extraction_button.visible, "Route action becomes available in rescue preparation")
	world.go_to_extraction()
	expect(world.order == "move" and not world.hero.route.is_empty(), "Evacuation action uses a real traversable route")
	world.stop_order()
	world.session.phase = "evacuate"
	world.session.finale_wave = 3
	world.hero.position = world.extraction
	world.vision.update()
	var revision: int = world.board.revision
	world.extraction_feedback.update()
	expect(world.extraction_feedback.caption.visible and world.extraction_feedback.inside(), "Visible landing zone displays in-world boarding status")
	world._physics_process(6)
	world.extraction_feedback.update()
	world.hud.refresh(0)
	expect(world.session.phase == "evacuate" and world.session.boarding_progress == 6, "Feedback preserves the twelve second boarding rule")
	expect(world.hud.boarding_bar.value == 6 and world.extraction_feedback.caption.text.contains("6.0"), "HUD and world marker show actual saved progress")
	expect(world.extraction_feedback.geometry.get_surface_count() == 1, "Progress creates a terrain-following arc")
	expect(world.extraction_marker.scale == Vector3.ONE, "Landing marker no longer pulses in size")
	world.hero.position += Vector3(8,0,0)
	world._physics_process(2)
	world.hud.refresh(0)
	expect(world.session.boarding_progress == 5 and world.hud.objective.text.contains("回退"), "Leaving zone reports actual progress loss")
	world.paused = true
	world._physics_process(3)
	world.extraction_feedback.update()
	expect(world.session.boarding_progress == 5, "Pause freezes boarding progress and its display")
	var snap := Save.snapshot(world)
	expect(Save.validate(snap).is_empty(), "Evacuation feedback needs no new save schema")
	var expected_rng: int = world.rng.state
	for i in range(20): world.extraction_feedback.update()
	expect(world.rng.state == expected_rng and world.board.revision == revision, "Render feedback never changes gameplay RNG or navigation")
	world.free()
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	Save.apply(world,snap)
	world.extraction_feedback.update()
	world.hud.refresh(0)
	expect(world.hud.boarding_bar.value == 5 and world.paused, "Load reconstructs progress without advancing it")
	world.paused = false
	world.hero.position = world.extraction
	world.hero.health = world.hero.max_health
	world._physics_process(7)
	world.extraction_feedback.update()
	expect(world.session.phase == "won" and not world.extraction_feedback.caption.visible, "Successful boarding uses existing win flow and hides live prompt")
	world.session.phase = "evacuate"
	world.session.mode = "classic"
	world._physics_process(0.01)
	expect(world.session.phase == "won", "Classic mode retains instant extraction")
	world.session.phase = "evacuate"
	world.session.mode = "standard"
	world.hero.health = 0
	world._physics_process(0.01)
	expect(world.session.phase == "lost", "Feedback does not allow a dead survivor to extract")
	world.free()
	print("EXTRACTION FEEDBACK: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
