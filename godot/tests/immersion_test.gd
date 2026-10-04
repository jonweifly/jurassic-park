extends SceneTree
const Save = preload("res://scripts/save_store.gd")
const Preferences = preload("res://scripts/preferences.gd")
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
	Save.directory = "user://immersion_fixture"
	Preferences.file_path = "user://immersion_fixture/preferences.cfg"
	w = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	w.encounter.set_process(false)
	w.sound.set_process(false)
	w.start_session(1500, "standard")
	w.spawn_clocks.clear()
	w.preferences.values.perspective = true
	w.preferences.values.impact_motion = true
	w.camera_rig.center(true)
	await physics_frame
	# Exercise actual physics picking at the same ground points across both lenses.
	for perspective in [true, false]:
		w.preferences.values.perspective = perspective
		for span in [18.0, 36.0, 68.0]:
			for angle in [0.0, 0.8, 1.8]:
				w.camera_size = span
				w.camera_rig.target_yaw = angle
				w.update_camera(0)
				var point: Vector3 = w.hero.position
				var screen: Vector2 = w.camera.unproject_position(point)
				var hit: Vector3 = w.ground_at(screen)
				expect(hit.distance_to(point) < 0.15, "Terrain pick failed: perspective=%s span=%.1f yaw=%.1f expected=%s hit=%s distance=%.3f" % [perspective, span, angle, point, hit, hit.distance_to(point)])
				expect(w.camera.projection == (Camera3D.PROJECTION_PERSPECTIVE if perspective else Camera3D.PROJECTION_ORTHOGONAL), "Projection follows the player's preference")
		expect(w.ground_at(Vector2(-20000, -20000)) == Vector3(10000, 0, 10000), "Off-island rays remain misses instead of creating fictitious ground commands")
	w.preferences.values.perspective = true
	w.camera_rig.reset()
	w.update_camera(0)
	w.vision.update()
	var at: Vector3 = w.hero.position
	var enemy: Node3D = w.spawn_dinosaur(at + Vector3(2, 0, 0), "trex")
	enemy.set_meta("ai_target_kind", "hero")
	var cell: Vector2i = w.board.cell_at(enemy.position)
	w.vision.visible_cells.erase(cell)
	enemy.visible = true # Even a stale visible flag must not reveal unseen enemies.
	w.encounter.scan()
	expect(w.encounter.count == 0, "Hidden dinosaurs cannot trigger an encounter warning")
	w.encounter.impact(enemy.position)
	expect(w.encounter.dust.is_empty() and w.camera_rig.impact_strength == 0, "Unseen hits cannot create particles or camera motion")
	w.vision.visible_cells[cell] = true
	w.encounter.scan()
	expect(w.encounter.count == 1 and w.encounter.desired_tension > 0, "A revealed attacking dinosaur raises local encounter tension")
	enemy.set_meta("ai_target_kind", "")
	w.encounter.scan()
	expect(w.encounter.count == 0, "A wandering dinosaur does not continuously alarm the player")
	w.vision.visible_cells[w.board.cell_at(at)] = true
	var rng_state: int = w.rng.state
	var hp: float = w.hero.health
	var elapsed: float = w.session.elapsed
	w.encounter.impact(at, true)
	expect(w.encounter.dust.size() == 1 and w.camera_rig.impact_strength > 0, "A local heavy contact emits debris and a bounded camera pulse")
	w.encounter.impact(at, true)
	expect(w.encounter.dust.size() == 1, "One area strike is coalesced instead of flashing for every building")
	w.paused = true
	w.encounter._process(0.2)
	expect(w.encounter.dust[0].age == 0.0, "Pause freezes the new contact debris")
	w.encounter.impact_cooldown = 0.0
	w.encounter.impact(at)
	expect(w.encounter.dust.size() == 1, "Paused games cannot spawn extra impact effects")
	w.paused = false
	w.preferences.values.impact_motion = false
	w.update_camera(0.02)
	w.encounter.impact(at)
	expect(w.camera_rig.impact_strength == 0.0, "Disabling impact motion clears and prevents camera shake")
	w.encounter.update_dust(0.7)
	expect(w.encounter.dust.is_empty(), "Contact debris frees itself promptly")
	w.preferences.values.quality = 0
	w.encounter.impact_cooldown = 0.0
	w.encounter.impact(at)
	expect(w.encounter.dust.is_empty(), "Low quality omits cosmetic debris")
	expect(w.rng.state == rng_state and w.hero.health == hp and w.session.elapsed == elapsed, "Presentation must never consume simulation RNG, deal damage or advance time")
	# Co-op uses the same presentation, including a pause requested by the guest.
	w.coop.set_process(false)
	w.coop.active = true
	w.coop.hosting = true
	w.coop.pawns[1] = w.hero
	w.coop.guest_paused = true
	w.preferences.values.quality = 2
	w.preferences.values.impact_motion = true
	w.encounter.impact_cooldown = 0.0
	w.encounter.impact(at)
	w.update_camera(0.1)
	expect(w.encounter.dust.is_empty() and w.camera_rig.impact_strength == 0, "A guest's room pause prevents host particles and camera motion")
	w.coop.guest_paused = false
	enemy.set_meta("ai_target_kind", "building")
	# The co-op actions occupy the center top edge. Local encounter presentation
	# must use their actual bounds instead of covering either action.
	w.hud.pause_panel.hide()
	w.coop.ui.refresh()
	w.encounter.scan()
	w.encounter.event_cooldown = 0.0
	w.encounter.show_event("协作接敌", "两名幸存者都应能看到房间和救援操作。")
	w.encounter.layout_messages()
	var encounter_origin: Vector2 = w.encounter.get_global_rect().position
	var warning_rect: Rect2 = Rect2(encounter_origin + w.encounter.banner_rect.position, w.encounter.banner_rect.size)
	expect(w.coop.ui.room_button.visible and not warning_rect.intersects(w.coop.ui.room_button.get_global_rect()), "Encounter warning stays below the visible co-op room control")
	expect(w.encounter.event_title.get_global_rect().position.y >= warning_rect.end.y + 8.0, "Encounter event title stays below the warning row")
	w.coop.make_pawn(2)
	var downed_teammate: Node3D = w.coop.pawns[2]
	downed_teammate.health = 0.0
	w.coop.ui.refresh()
	w.encounter.layout_messages()
	warning_rect = Rect2(encounter_origin + w.encounter.banner_rect.position, w.encounter.banner_rect.size)
	expect(w.coop.ui.revive_button.visible and not warning_rect.intersects(w.coop.ui.room_button.get_global_rect()) and not warning_rect.intersects(w.coop.ui.revive_button.get_global_rect()), "Encounter warning clears both co-op actions when a teammate needs revival")
	var packet: Dictionary = w.coop.replication.actor_packet()
	expect(packet.dinosaurs[enemy.get_meta("save_id")].target_kind == "building", "Replicated dinosaurs include the engagement state required by the guest warning")
	w.coop.hosting = false
	w.coop.connected = true
	w.coop.server_paused = false
	w.dinosaurs.erase(enemy)
	enemy.free()
	w.coop.replication.apply_actors(packet)
	w.vision.update()
	w.encounter.scan()
	expect(w.encounter.count == 1 and w.encounter.desired_tension > 0, "The guest warning works from a received actor snapshot without local AI")
	w.coop._effect("impact", [at, true])
	expect(w.encounter.dust.size() == 1 and w.camera_rig.impact_strength > 0, "The guest can render a host contact event without running damage simulation")
	var age: float = w.encounter.dust[0].age
	w.coop.server_paused = true
	w.encounter._process(0.2)
	expect(w.encounter.dust[0].age == age, "Replicated room pause freezes the guest's contact effect")
	w.coop.active = false
	w.coop.connected = false
	w.free()
	print("IMMERSION: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
