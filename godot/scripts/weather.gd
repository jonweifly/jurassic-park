extends RefCounted
## Presentation-only weather sampled from saved game time; no gameplay RNG or visibility edits.
const NAMES := ["微风", "大风", "阵雨", "雷雨"]
const STATES := [Vector3(0.16,0,0.03),Vector3(0.72,0,0.40),Vector3(0.42,0.62,0.68),Vector3(0.95,1,0.93)]
const DURATIONS := [155.0,90.0,145.0,100.0,100.0]
const ORDER := [0,1,2,3,2]
var world: Node
var wind := 0.16
var rain := 0.0
var cloud := 0.03
var wetness := 0.0
var direction := Vector2(0.9,0.35)
var clock := 0.0
var kind := 0
var flash := 0.0
var last_thunder := -1
var last_kind := -1
var preview_kind := -1 # Capture fixtures only; never persisted or exposed as a cheat UI.
var drops: CPUParticles3D
var splashes: CPUParticles3D
var rain_material: ShaderMaterial
var splash_material: ShaderMaterial
var roof_texture: ImageTexture
var roof_revision := -1
var roof_bucket := Vector2i(-999,-999)
var roof_count := -1
var flash_overlay: ColorRect

func _init(owner_world: Node) -> void:
	world = owner_world
	if DisplayServer.get_name() != "headless": create_rain()

static func sample(time: float) -> Dictionary:
	var cycle := fposmod(time,590.0)
	var index := 0
	while cycle >= DURATIONS[index] and index < DURATIONS.size()-1:
		cycle -= DURATIONS[index]
		index += 1
	var prior: int = ORDER[(index + ORDER.size()-1)%ORDER.size()] if time >= 590 or index > 0 else 0
	var blend := smoothstep(0,22,cycle)
	var state: Vector3 = STATES[prior].lerp(STATES[ORDER[index]],blend)
	# Ground dries gradually during the following clear spell.
	var wet := state.y
	if index == 0 and time >= 590: wet = maxf(wet,0.62*(1.0-smoothstep(0,95,cycle)))
	return {"kind":ORDER[index],"wind":state.x,"rain":state.y,"cloud":state.z,"wetness":wet}

func update() -> void:
	clock = world.session.game_time()
	var state := sample(clock)
	if preview_kind >= 0:
		var preset: Vector3 = STATES[preview_kind]
		state = {"kind":preview_kind,"wind":preset.x,"rain":preset.y,"cloud":preset.z,"wetness":preset.y}
	kind = state.kind
	wind = state.wind
	rain = state.rain
	cloud = state.cloud
	wetness = state.wetness
	if last_kind >= 0 and last_kind != kind and world.started and world.encounter:
		world.encounter.weather_event(kind)
	last_kind = kind
	direction = Vector2(cos(clock*0.005+0.4),sin(clock*0.005+0.4))
	var thunder_id := floori(clock/23.0)
	var thunder_phase := fposmod(clock,23.0)
	var storm := kind == 3 and rain > 0.85
	# Keep the existing deterministic lightning cadence, but make the event a
	# short cold pulse instead of a broad brightness change. The delayed thunder
	# cue below remains the audio anchor for the same event.
	flash = (0.20 + 0.02 * float(world.preferences.values.quality == 2)) * (1.0-smoothstep(0.12,0.6,thunder_phase)) if storm and not world.presentation_paused() else 0.0
	# A single broad, soft flash, followed by delayed thunder; loading never replays old events.
	if last_thunder == -1 or abs(thunder_id-last_thunder)>1: last_thunder = thunder_id
	if thunder_phase >= 1.7 and last_thunder < thunder_id:
		last_thunder = thunder_id
		if storm and not world.paused:
			world.sound.play_voice("thunder_%d" % (1+thunder_id%2),"Ambience",-8.0)
	if flash_overlay == null and DisplayServer.get_name() != "headless" and is_instance_valid(world.hud) and world.hud.root:
		create_flash_overlay()
	if flash_overlay:
		flash_overlay.visible = flash > 0.001
		flash_overlay.modulate.a = flash * (0.92 if world.preferences.values.quality > 0 else 0.76)
	if drops:
		drops.emitting = rain > 0.05 and world.started and world.session.phase in ["playing","evacuate"]
		var amount := 320 if world.preferences.values.quality == 0 else (600 if world.preferences.values.quality == 1 else 900)
		if drops.amount != amount: drops.amount = amount
		drops.speed_scale = 0.0 if world.paused else 1.0
		drops.position = world.camera_rig.focus + Vector3.UP*16
		drops.direction = Vector3(direction.x*wind*.35,-1,direction.y*wind*.35).normalized()
		rain_material.set_shader_parameter("rain_gain",rain)
		rain_material.set_shader_parameter("rain_drift",direction*wind*.35)
		if rain > 0.05: update_roofs()
		update_splashes()

func apply_lighting() -> void:
	world.sun.light_energy *= lerpf(1.0,0.42,cloud) * lerpf(1.0,0.82,rain)
	world.environment.ambient_light_energy *= lerpf(1.0,0.80,cloud)
	world.environment.ambient_light_energy += flash
	world.environment.ambient_light_color = world.environment.ambient_light_color.lerp(Color("d9efff"),flash*.72)
	world.sun.light_color = world.sun.light_color.lerp(Color("a9bdc9"),cloud*.55+rain*.15)
	# Keep the playable camp crisp while rain gathers a low, distant mist layer.
	# Height fog is especially useful on the sloped island: banks recede softly
	# without washing out the survivor, buildings, or nearby dinosaurs.
	world.environment.fog_density = lerpf(0.0007,0.0027,rain)
	world.environment.fog_height = lerpf(3.5,1.0,rain)
	world.environment.fog_height_density = lerpf(0.010,0.042,rain)
	world.environment.fog_sky_affect = lerpf(0.18,0.38,cloud)

func create_rain() -> void:
	var height_image: Image = world.board.layout.height_image()
	rain_material = ShaderMaterial.new()
	rain_material.shader = load("res://shaders/rain.gdshader")
	rain_material.set_shader_parameter("ground_heights",ImageTexture.create_from_image(height_image))
	var roof_image := Image.create(128,128,false,Image.FORMAT_RF)
	roof_image.fill(Color(-100,0,0))
	roof_texture = ImageTexture.create_from_image(roof_image)
	rain_material.set_shader_parameter("roof_heights",roof_texture)
	drops = CPUParticles3D.new()
	drops.name = "WeatherRain"
	drops.emitting = false
	drops.amount = 900
	drops.lifetime = 1.1
	drops.preprocess = 1.1
	drops.local_coords = false
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(22,3,22)
	drops.spread = 4
	drops.gravity = Vector3.ZERO
	# Faster, longer streaks read as driving rain instead of a light drizzle.
	drops.initial_velocity_min = 26
	drops.initial_velocity_max = 36
	drops.scale_amount_min = 0.55
	drops.scale_amount_max = 1.55
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.026,0.34)
	mesh.material = rain_material
	drops.mesh = mesh
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(drops)
	# A small camera-local sample of impact rings provides readable wet-ground
	# feedback without collision queries for every falling drop.
	splash_material = ShaderMaterial.new()
	splash_material.shader = load("res://shaders/rain_splash.gdshader")
	splash_material.set_shader_parameter("rain_gain",0.0)
	splashes = CPUParticles3D.new()
	splashes.name = "WeatherRainSplashes"
	splashes.emitting = false
	splashes.amount = 11
	splashes.lifetime = 0.72
	splashes.preprocess = 0.72
	splashes.local_coords = false
	splashes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	splashes.emission_box_extents = Vector3(13,0.015,13)
	splashes.direction = Vector3.UP
	splashes.spread = 180.0
	splashes.gravity = Vector3.ZERO
	splashes.initial_velocity_min = 0.0
	splashes.initial_velocity_max = 0.0
	splashes.randomness = 0.65
	splashes.rotation_degrees.x = -90.0
	var splash_mesh := QuadMesh.new()
	splash_mesh.size = Vector2(0.78,0.78)
	splash_mesh.material = splash_material
	splashes.mesh = splash_mesh
	splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(splashes)

func create_flash_overlay() -> void:
	if flash_overlay or not is_instance_valid(world.hud) or not world.hud.root: return
	flash_overlay = ColorRect.new()
	flash_overlay.name = "WeatherLightningFlash"
	flash_overlay.color = Color("d9efff")
	flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_overlay.visible = false
	world.hud.root.add_child(flash_overlay)
	world.hud.root.move_child(flash_overlay,0)

func update_splashes() -> void:
	if not splashes: return
	var quality := clampi(int(world.preferences.values.get("quality",2)),0,2)
	var amount: int = [3,7,11][quality]
	var active: bool = rain > 0.05 and world.started and world.session.phase in ["playing","evacuate"] and not world.presentation_paused()
	splashes.amount = amount
	splashes.emitting = active
	splashes.speed_scale = 0.0 if world.presentation_paused() else 1.0
	var focus: Vector3 = world.camera_rig.focus
	splashes.position = Vector3(focus.x,world.board.layout.height_at(focus.x,focus.z)+0.045,focus.z)
	splash_material.set_shader_parameter("rain_gain",rain)
	splash_material.set_shader_parameter("weather_clock",clock)

func update_roofs() -> void:
	if not roof_texture: return
	var bucket := Vector2i(floori(world.camera_rig.focus.x/12),floori(world.camera_rig.focus.z/12))
	if roof_revision == world.board.revision and roof_bucket == bucket and roof_count == world.session.buildings.size(): return
	roof_revision = world.board.revision
	roof_bucket = bucket
	roof_count = world.session.buildings.size()
	var image := Image.create(128,128,false,Image.FORMAT_RF)
	image.fill(Color(-100,0,0))
	for cell in world.trees:
		var p: Vector3 = world.board.point(cell)
		if p.distance_to(world.camera_rig.focus) < 36: image.set_pixel(cell.x,cell.y,Color(p.y+3.3,0,0))
	for b in world.session.buildings:
		if b.hp > 0 and b.kind not in ["fossil","fire","gate"]:
			var p: Vector3 = world.board.point(b.cell)
			image.set_pixel(b.cell.x,b.cell.y,Color(p.y+1.9,0,0))
	roof_texture.update(image)
