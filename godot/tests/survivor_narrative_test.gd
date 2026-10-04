extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var world: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func tick(dt: float) -> void:
	world.hud.refresh(dt)
	world.narrative.update(dt)

func ready_to_speak() -> void:
	world.hud.clear_subtitle()
	world.narrative.cooldown = 0.0

func run() -> void:
	Save.directory = "user://survivor_narrative_fixture"
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500, "standard")
	world.spawn_clocks.clear()
	tick(0.0)
	expect(world.hud.subtitle_label.text.contains("先找地方落脚"), "Opening appears in the playable scene")
	expect(world.hud.subtitle_plate.mouse_filter == Control.MOUSE_FILTER_IGNORE and world.hud.subtitle_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Subtitles leave pointer input available")
	var remaining: float = world.hud.subtitle_time
	world.paused = true
	tick(30.0)
	expect(is_equal_approx(world.hud.subtitle_time, remaining) and not world.hud.subtitle_plate.visible, "Pause hides the subtitle and preserves reading time")
	world.paused = false
	tick(0.0)
	expect(world.hud.subtitle_plate.visible, "Resume restores the same subtitle")
	ready_to_speak()
	world.order = "wood"
	world.hero.play_animation("walk", 0)
	tick(0.0)
	expect(world.hud.subtitle_time == 0.0, "A distant harvesting command does not speak before actual work")
	world.hero.play_animation("chop", 0)
	tick(0.0)
	expect(world.hud.subtitle_label.text.contains("这批木材") and world.narrative.shown.get("wood", false), "Actual work is observed even when the order was issued before the physics tick")
	world.hero.play_animation("mine", 0)
	tick(1.0)
	expect(world.hud.subtitle_label.text.contains("这批木材") and not world.narrative.shown.get("gold", false), "A new action cannot interrupt a thought or bypass its cooldown")
	tick(30.0)
	expect(world.narrative.shown.get("gold", false), "A later mining action receives its own thought")
	world.hero.play_animation("chop", 0)
	tick(60.0)
	expect(world.hud.subtitle_time == 0.0, "Continuous and repeated gathering does not replay the same thought")
	world.order = "idle"
	world.hero.play_animation("idle", 0)
	var tent: Dictionary = world.session.build("tent", Vector2i(60, 62))
	tent.remaining = 0.0
	tick(0.0)
	expect(world.hud.subtitle_label.text.contains("落脚处"), "Completed shelter triggers the camp story beat")
	ready_to_speak()
	tick(0.0)
	expect(world.hud.subtitle_time == 0.0, "Camp story is not repeated every frame")
	world.session.elapsed = world.session.duration - 120.0
	tick(0.0)
	expect(world.hud.subtitle_label.text.contains("收到你的信标"), "Rescue preparation begins at the existing two-minute threshold")
	tick(12.0)
	expect(world.hud.subtitle_label.text.contains("我会守住撤离点"), "The survivor answers after the radio line has finished")
	world.session.phase = "evacuate"
	world.session.boarding_progress = 0.1
	tick(0.0)
	expect(world.narrative.pending.size() == 2, "Arrival and boarding wait for the current line without overwriting it")
	tick(5.0)
	expect(world.hud.subtitle_label.text.contains("撤离点已就绪"), "Arrival takes precedence over old camp dialogue")
	tick(7.1)
	expect(world.hud.subtitle_label.text.contains("保持在停机坪范围"), "Boarding communication fits within the twelve-second boarding window")
	world.session.boarding_progress = 0.05
	tick(0.0)
	expect(world.narrative.shown.get("left_pad", false), "Leaving the pad triggers a single contextual warning")
	world.session.phase = "won"
	tick(0.0)
	expect(world.hud.subtitle_label.text.contains("人员已接回") and world.narrative.pending.is_empty(), "Success replaces obsolete radio messages with the ending")
	world.session.phase = "evacuate"
	world.session.evacuation_elapsed = 260.0
	world.session.boarding_progress = 3.0
	world.narrative.reset(true)
	tick(10.0)
	expect(world.hud.subtitle_time == 0.0 and world.narrative.pending.is_empty(), "Loading late in rescue skips historical messages and the opening")
	world.session.phase = "lost"
	tick(0.0)
	expect(world.hud.subtitle_label.text.contains("能听到吗"), "Failure has its own radio ending")
	world.session.phase = "playing"
	world.session.elapsed = 300.0
	world.narrative.phase = ""
	tick(0.0)
	expect(world.narrative.phase == "playing" and world.narrative.pending.is_empty(), "A client joining an ongoing scene initializes from replicated state")
	world.free()
	print("SURVIVOR NARRATIVE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
