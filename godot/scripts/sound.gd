extends Node
## Audio uses the camera's ground focus, avoiding isometric-camera height falloff.
const FILES = ["click", "ready", "deposit", "complete", "warning", "rescue", "won", "lost", "chop", "hammer", "mine", "step", "shot", "bow", "electric", "gate", "hit", "roar", "collapse", "day", "night", "fire", "generator"]
const ENVIRONMENT_FILES = ["small_raptor_call_1","small_raptor_call_2","raptor_call_1","raptor_call_2","young_trex_call_1","young_trex_call_2","trex_call_1","trex_call_2","wind_breeze","wind_gale","rain","thunder_1","thunder_2"]
const LOOP_FILES = ["day","night","fire","generator","wind_breeze","wind_gale","rain"]
const DinosaurAudio = preload("res://scripts/dinosaur_audio.gd")
var dinosaur_audio: RefCounted
var panners: Array[AudioEffectPanner] = []
const SETTINGS = "user://audio.cfg"
var world: Node
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var loops: Dictionary = {}
var cooldowns: Dictionary = {}
var levels := {"Master": 0.8, "Ambience": 0.7, "Effects": 0.85}
var muted := false
var previous_phase := "playing"
var previous_hp := 150.0
var foot_clock := 0.0
var work_clock := 0.0
var roar_clock := 2.0
var settings_path := SETTINGS
var output_enabled := true

func _ready() -> void:
	# Dummy audio never mixes in headless gameplay tests. Validate sound with audio_test.gd.
	output_enabled = DisplayServer.get_name() != "headless"
	var has_limiter := false
	for i in range(AudioServer.get_bus_effect_count(0)):
		if AudioServer.get_bus_effect(0, i).resource_name == "GamePeakLimiter": has_limiter = true
	if not has_limiter:
		var limiter := AudioEffectLimiter.new()
		limiter.resource_name = "GamePeakLimiter"
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(0, limiter)
	for bus_name in ["Ambience", "Effects", "Interface"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	dinosaur_audio = DinosaurAudio.new(self)
	for key in FILES + ENVIRONMENT_FILES:
		var stream: AudioStreamWAV = load("res://assets/audio/%s.wav" % key).duplicate()
		if key in LOOP_FILES:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
		streams[key] = stream
	for i in range(16):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)
		var bus_name := "Position_%02d" % i
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count-1
			AudioServer.set_bus_name(index,bus_name)
			AudioServer.set_bus_send(index,"Effects")
			AudioServer.add_bus_effect(index,AudioEffectPanner.new())
		panners.append(AudioServer.get_bus_effect(index,0))
	for key in LOOP_FILES:
		var player := AudioStreamPlayer.new()
		player.stream = streams[key]
		player.bus = "Ambience"
		player.volume_db = -60
		add_child(player)
		loops[key] = player
		if output_enabled: player.play()
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		for key in levels: levels[key] = clampf(float(config.get_value("volume", key, levels[key])), 0, 1)
		muted = bool(config.get_value("volume", "muted", false))
	apply_levels()
	# Audible feedback also exists before the start-duration dialog is dismissed.
	play_ui("ready")

func apply_levels() -> void:
	for key in levels:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(key), linear_to_db(maxf(0.0001, levels[key])))
	AudioServer.set_bus_mute(0, muted or levels.Master <= 0)

func save_settings() -> void:
	var config := ConfigFile.new()
	for key in levels: config.set_value("volume", key, levels[key])
	config.set_value("volume", "muted", muted)
	config.save(settings_path)

func set_level(key: String, value: float) -> void:
	levels[key] = clampf(value, 0, 1)
	apply_levels()
	save_settings()

func set_muted(value: bool) -> void:
	muted = value
	apply_levels()
	save_settings()

func play_ui(key: String) -> void:
	play_voice(key, "Interface", -9.0)

func audible(position: Vector3) -> bool:
	if not is_instance_valid(world): return false
	var distance := Vector2(position.x - world.camera_focus.x, position.z - world.camera_focus.z).length()
	if distance >= 32: return false
	# Hidden actions do not leak enemy positions through sound.
	return not world.vision or world.vision.is_visible(world.board.cell_at(position))

func play_at(key: String, position: Vector3, gain_db: float = 0.0, priority: bool = false) -> void:
	# Dinosaur calls are chosen locally from visible animals or attack cues;
	# forwarding their layered samples as well would play a second roar.
	if world.coop and not key.contains("_call_"): world.coop.effect("sound",[key,position,gain_db,priority])
	if not audible(position): return
	var offset: Vector3 = position-world.camera_focus
	var distance := Vector2(offset.x,offset.z).length()
	var pan := clampf(offset.dot(world.camera.global_basis.x)/16.0,-0.8,0.8)
	play_voice(key, "Effects", -5.0 + gain_db + linear_to_db(maxf(0.01, 1.0 - distance / 32.0)),priority,pan)

func play_dinosaur(d: Node3D, attack: bool = false) -> void:
	if world.coop: world.coop.effect("dinosaur",[d.get_meta("save_id",-1),attack])
	dinosaur_audio.cue(d,attack)

func play_voice(key: String, bus_name: String, gain_db: float, priority: bool = false, pan: float = 0.0) -> void:
	if not output_enabled or not streams.has(key) or cooldowns.get(key, 0.0) > 0: return
	var available := voices.filter(func(v): return not v.playing)
	if available.is_empty() and priority:
		available = voices.filter(func(v): return not v.get_meta("priority",false) and v.bus != "Interface")
	for voice in available:
		voice.stream = streams[key]
		voice.set_meta("priority",priority)
		voice.set_meta("gameplay",bus_name == "Effects" or key.begins_with("thunder_"))
		var index := voices.find(voice)
		panners[index].pan = pan
		voice.bus = "Position_%02d" % index if bus_name == "Effects" else bus_name
		voice.volume_db = gain_db
		voice.pitch_scale = 1.0
		voice.play()
		cooldowns[key] = 0.07
		return

func _process(dt: float) -> void:
	for key in cooldowns: cooldowns[key] = maxf(0, cooldowns[key] - dt)
	if not is_instance_valid(world) or not is_instance_valid(world.hero): return
	var active: bool = not world.paused and world.session.phase in ["playing", "evacuate"]
	if world.coop and world.coop.active: active = active and not world.coop.room_paused()
	var ambience_gain := 1.0 if active or not world.started else 0.3
	var rain: float = world.weather.rain if world.weather else 0.0
	var wind: float = world.weather.wind if world.weather else 0.16
	var duck := 0.60 if voices.any(func(v): return v.playing and v.get_meta("priority",false)) else 1.0
	set_loop("day", ambience_gain*(1-rain*.75)*duck if not world.night else 0.0, dt)
	set_loop("night", ambience_gain*(1-rain*.65)*duck if world.night else 0.0, dt)
	set_loop("wind_breeze",ambience_gain*(0.3+wind*.3)*duck,dt)
	set_loop("wind_gale",ambience_gain*maxf(0,wind-.3)*duck*.9,dt)
	set_loop("rain",ambience_gain*rain*duck*.8,dt)
	var fire_gain := 0.0
	var generator_gain := 0.0
	if active:
		for b in world.session.buildings:
			if b.hp <= 0 or b.remaining > 0 or b.kind not in ["fire", "generator"]: continue
			var p: Vector3 = world.board.point(b.cell)
			var distance := Vector2(p.x - world.camera_focus.x, p.z - world.camera_focus.z).length()
			var gain := maxf(0, 1.0 - distance / 17.0)
			if b.kind == "fire": fire_gain = maxf(fire_gain, gain)
			else: generator_gain = maxf(generator_gain, gain * 0.45)
	set_loop("fire", fire_gain, dt)
	set_loop("generator", generator_gain, dt)
	if previous_phase != world.session.phase:
		previous_phase = world.session.phase
		if previous_phase in ["won", "lost"]: play_ui(previous_phase)
		elif previous_phase == "evacuate": play_ui("rescue")
	if world.hero.health < previous_hp: play_at("hit", world.hero.position)
	previous_hp = world.hero.health
	for voice in voices:
		if voice.get_meta("gameplay",false): voice.stream_paused = not active
	if not active: return
	dinosaur_audio.update(dt)
	foot_clock -= dt
	work_clock -= dt
	if world.coop and world.coop.active:
		if world.coop.hosting and foot_clock<=0:
			for survivor in world.survivors():
				if survivor.current_speed>.2 and not survivor.route.is_empty():
					play_at("step",survivor.position,-3)
			foot_clock=.36
	elif world.hero.current_speed > 0.2 and not world.hero.route.is_empty() and foot_clock <= 0:
		play_at("step", world.hero.position, -3)
		foot_clock = 0.36

func set_loop(key: String, gain: float, dt: float) -> void:
	var player: AudioStreamPlayer = loops[key]
	var target := linear_to_db(maxf(0.001, gain))
	player.volume_db = lerpf(player.volume_db, target, minf(1.0, dt * 4))

func _exit_tree() -> void:
	for player in voices + loops.values():
		player.stop()
		player.stream = null
	streams.clear()
