extends SceneTree
## Run with the real audio driver: sh scripts/godot.sh --script res://tests/audio_test.gd
var checks := 0
var failures := 0
var capture := AudioEffectCapture.new()

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func energy() -> float:
	var samples := capture.get_buffer(capture.get_frames_available())
	var sum := 0.0
	for sample in samples: sum += sample.length_squared()
	return sqrt(sum / maxf(1, samples.size() * 2))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var sound = world.sound
	var original_levels: Dictionary = sound.levels.duplicate()
	var original_mute: bool = sound.muted
	sound.settings_path = "user://audio-test.cfg"
	sound.set_level("Master", 0.8)
	sound.set_level("Effects", 0.85)
	sound.set_level("Ambience", 0.7)
	sound.set_muted(false)
	var effect_index := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	await create_timer(1.3).timeout
	expect(sound.streams.size() == sound.FILES.size()+sound.ENVIRONMENT_FILES.size(), "All declared WAV assets must load")
	for key in sound.FILES + sound.ENVIRONMENT_FILES:
		expect(sound.streams[key].get_length() > 0.04, "Audio asset must have duration: " + key)
	var ambient_rms := energy()
	expect(ambient_rms > 0.001, "Start dialog must already produce non-silent ambience through audio mixer")
	print("START AMBIENCE RMS: ", ambient_rms)
	# Isolate event playback from ambience, then sample actual mixer output.
	sound.set_process(false)
	for loop in sound.loops.values(): loop.stop()
	for voice in sound.voices: voice.stop()
	await create_timer(0.2).timeout
	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, record)
	record.set_recording_active(true)
	for key in ["chop", "mine", "deposit", "hammer", "complete", "bow", "electric", "gate", "roar", "rescue"]:
		sound.cooldowns.clear()
		capture.clear_buffer()
		sound.play_voice(key, "Effects", -8)
		await create_timer(sound.streams[key].get_length() + 0.1).timeout
		var rms := energy()
		expect(rms > 0.001, "Event must produce non-silent mixer output: " + key)
		print("EVENT ", key, " RMS: ", rms)
	record.set_recording_active(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	expect(record.get_recording().save_to_wav("res://captures/audio-preview.wav") == OK, "Mixed audio preview must save")
	sound.set_muted(true)
	expect(AudioServer.is_bus_mute(0), "Mute must apply to the master bus")
	var config := ConfigFile.new()
	config.load(sound.settings_path)
	expect(config.get_value("volume", "muted") == true, "Mute preference must persist")
	sound.set_muted(false)
	sound.set_level("Effects", 0)
	expect(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")) <= -79, "Effects slider at zero must suppress effects bus")
	capture.clear_buffer()
	sound.cooldowns.clear()
	sound.play_voice("chop", "Effects", -8)
	await create_timer(0.4).timeout
	expect(energy() < 0.0001, "Zero effects volume must suppress actual mixer samples")
	world.camera_focus = world.hero.position
	world.vision.update()
	sound.cooldowns.clear()
	for voice in sound.voices: voice.stop()
	sound.play_at("roar", world.hero.position + Vector3(100, 0, 0))
	expect(not sound.voices.any(func(v): return v.playing), "Distant sound must be culled")
	sound.play_at("chop", world.hero.position)
	expect(sound.voices.any(func(v): return v.playing), "Nearby visible work must start a player")
	world.started = true
	world.paused = true
	sound._process(0.1)
	expect(sound.voices.filter(func(v): return v.playing).all(func(v): return v.stream_paused), "Pause must suspend ongoing gameplay effects")
	world.paused = false
	sound._process(0.1)
	expect(sound.voices.filter(func(v): return v.playing).all(func(v): return not v.stream_paused), "Resume must release paused effects")
	# Restore user's live bus levels; tests never overwrite their audio.cfg.
	sound.levels = original_levels
	sound.muted = original_mute
	sound.apply_levels()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sound.settings_path))
	AudioServer.remove_bus_effect(0, effect_index + 1)
	AudioServer.remove_bus_effect(0, effect_index)
	world.queue_free()
	await create_timer(0.15).timeout
	print("AUDIO: ", checks, " checks, ", failures, " failures. Device: ", AudioServer.output_device)
	quit(0 if failures == 0 else 1)
