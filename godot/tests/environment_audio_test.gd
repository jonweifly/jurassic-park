extends SceneTree
var checks := 0
var failures := 0
var capture := AudioEffectCapture.new()
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func levels() -> Vector2:
	var frames := capture.get_buffer(capture.get_frames_available())
	var sum := Vector2.ZERO
	for frame in frames: sum += frame*frame
	return Vector2(sqrt(sum.x/maxi(1,frames.size())),sqrt(sum.y/maxi(1,frames.size())))
func run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500,"standard")
	world.spawn_clocks.clear()
	world.update_camera(0)
	world.vision.update()
	var sound = world.sound
	sound.set_process(false)
	var original_levels: Dictionary = sound.levels.duplicate()
	var original_mute: bool = sound.muted
	sound.levels = {"Master":0.8,"Effects":0.85,"Ambience":0.7}
	sound.muted = false
	sound.apply_levels()
	for player in sound.loops.values()+sound.voices: player.stop()
	var index := AudioServer.get_bus_effect_count(0)
	capture.buffer_length = 6
	AudioServer.add_bus_effect(0,capture)
	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0,record)
	await create_timer(.25).timeout
	record.set_recording_active(true)
	var metrics := {}
	for key in sound.ENVIRONMENT_FILES:
		sound.cooldowns.clear()
		capture.clear_buffer()
		sound.play_voice(key,"Effects" if "call" in key else "Ambience",-7.0)
		var duration: float = sound.streams[key].get_length() if "call" in key else minf(3.4,sound.streams[key].get_length())
		await create_timer(duration).timeout
		var value := levels()
		metrics[key] = [value.x,value.y]
		expect(value.length()>0.002,"New asset produces audible native mixer output: "+key)
		for voice in sound.voices: voice.stop()
		await create_timer(.15).timeout
	record.set_recording_active(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/environment"))
	expect(record.get_recording().save_to_wav("res://captures/environment/audio-preview.wav") == OK,"Native environmental audio preview saved")
	# Actual mixer energy on each side proves positional stereo survives the bus routing.
	for side in [-1.0,1.0]:
		capture.clear_buffer()
		sound.cooldowns.clear()
		sound.play_voice("raptor_call_1","Effects",-7,false,side*.8)
		await create_timer(.6).timeout
		var value := levels()
		expect(value.x>value.y*2 if side<0 else value.y>value.x*2,"Stereo pan is audible on the expected side")
		for voice in sound.voices: voice.stop()
		await create_timer(.15).timeout
	# A major encounter still gets a voice when ordinary effects occupy the pool.
	for i in range(sound.voices.size()):
		sound.cooldowns.clear()
		sound.play_voice("rain","Effects",-40)
	sound.cooldowns.clear()
	sound.play_voice("trex_call_1","Effects",-5,true)
	expect(sound.voices.any(func(v):return v.playing and v.stream==sound.streams.trex_call_1),"Tyrannosaur cue can replace an ordinary voice in a saturated pool")
	world.paused = true
	sound._process(.1)
	expect(sound.voices.filter(func(v):return v.playing).all(func(v):return v.stream_paused),"Pause freezes positional dinosaur cues")
	world.paused = false
	sound._process(.1)
	expect(sound.voices.filter(func(v):return v.playing).all(func(v):return not v.stream_paused),"Resume releases positional cues")
	for voice in sound.voices: voice.stop()
	world.weather.preview_kind = -1
	world.session.elapsed = 436.9
	world.weather.update()
	world.session.elapsed = 437.02
	world.weather.update()
	expect(world.weather.flash > 0.1 and not sound.voices.any(func(v):return v.playing),"Storm flashes before the delayed thunder cue")
	world.session.elapsed = 438.8
	world.weather.update()
	expect(sound.voices.any(func(v):return v.playing and v.stream==sound.streams.thunder_2),"Thunder fires once after the lightning delay")
	for voice in sound.voices: voice.stop()
	world.weather.update()
	expect(not sound.voices.any(func(v):return v.playing),"Repeated weather evaluation never duplicates a thunder event")
	for player in sound.loops.values(): player.play()
	world.weather.preview_kind = 3
	world.update_lighting()
	world.update_camera(0)
	for i in range(20): sound._process(.1)
	expect(world.weather.drops.emitting and world.weather.drops.amount == 900,"Native storm starts bounded high-quality rain emitter")
	expect(world.weather.splashes != null and world.weather.splashes.emitting and world.weather.splashes.amount == 11,"Storm enables a bounded high-quality ground splash sample")
	expect(world.weather.flash_overlay != null,"Storm creates a screen-space lightning flash layer")
	expect(sound.loops.rain.volume_db > -15 and sound.loops.wind_gale.volume_db > -20,"Storm drives rain and gale ambience")
	var ambience: float = sound.loops.rain.volume_db
	sound.cooldowns.clear()
	sound.play_voice("trex_call_2","Effects",-5,true)
	for i in range(10): sound._process(.1)
	expect(sound.loops.rain.volume_db < ambience-2,"Dinosaur cue ducks rain so the warning stays intelligible")
	world.paused = true
	world.weather.update()
	expect(world.weather.drops.speed_scale == 0,"Pause freezes rain motion")
	world.paused = false
	world.preferences.values.quality = 0
	world.weather.update()
	expect(world.weather.drops.amount == 320,"Low quality reduces rain particles without changing weather")
	expect(world.weather.splashes.amount == 3,"Low quality reduces splash particles without changing weather")
	world.weather.preview_kind = 0
	world.weather.update()
	expect(not world.weather.drops.emitting,"Clear weather stops rain emission")
	# Player preferences still control all new buses.
	sound.levels.Effects = 0
	sound.levels.Ambience = 0
	sound.apply_levels()
	await create_timer(.2).timeout
	capture.clear_buffer()
	sound.cooldowns.clear()
	sound.play_voice("trex_call_1","Effects",-5,true)
	await create_timer(.5).timeout
	expect(levels().length()<0.0001,"Effects and ambience sliders suppress the new audio at the mixer")
	sound.levels = original_levels
	sound.muted = original_mute
	sound.apply_levels()
	AudioServer.remove_bus_effect(0,index+1)
	AudioServer.remove_bus_effect(0,index)
	FileAccess.open("res://captures/environment/audio-metrics.json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	world.free()
	print("ENVIRONMENT AUDIO: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
