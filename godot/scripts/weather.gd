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
var preview_kind := -1 # Capture fixtures only; never persisted or exposed as a cheat UI.
var drops: CPUParticles3D
var rain_material: ShaderMaterial
var roof_texture: ImageTexture
var roof_revision := -1
var roof_bucket := Vector2i(-999,-999)
var roof_count := -1

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
	direction = Vector2(cos(clock*0.005+0.4),sin(clock*0.005+0.4))
	var thunder_id := floori(clock/23.0)
	var thunder_phase := fposmod(clock,23.0)
	flash = 0.22 * (1.0-smoothstep(0.12,0.6,thunder_phase)) if kind == 3 and rain > 0.85 else 0.0
	# A single broad, soft flash, followed by delayed thunder; loading never replays old events.
	if last_thunder == -1 or abs(thunder_id-last_thunder)>1: last_thunder = thunder_id
	if thunder_phase >= 1.7 and last_thunder < thunder_id:
		last_thunder = thunder_id
		if kind == 3 and rain > 0.85 and not world.paused:
			world.sound.play_voice("thunder_%d" % (1+thunder_id%2),"Ambience",-8.0)
	if drops:
		drops.emitting = rain > 0.05 and world.started and world.session.phase in ["playing","evacuate"]
		var amount := 320 if world.preferences.values.quality == 0 else (600 if world.preferences.values.quality == 1 else 900)
		if drops.amount != amount: drops.amount = amount
		drops.speed_scale = 0.0 if world.paused else 1.0
		drops.position = world.camera_rig.focus + Vector3.UP*16
		drops.direction = Vector3(direction.x*wind*.35,-1,direction.y*wind*.35).normalized()
		rain_material.set_shader_parameter("rain_gain",rain)
		rain_material.set_shader_parameter("rain_drift",direction*wind*.35)
		update_roofs()

func apply_lighting() -> void:
	world.sun.light_energy *= lerpf(1.0,0.50,cloud)
	world.environment.ambient_light_energy *= lerpf(1.0,0.86,cloud)
	world.environment.ambient_light_energy += flash
	world.sun.light_color = world.sun.light_color.lerp(Color("b4c5cf"),cloud*.45)
	world.environment.fog_density = lerpf(0.00065,0.0018,rain)

func create_rain() -> void:
	var height_image := Image.create(129,129,false,Image.FORMAT_RF)
	for y in range(129):
		for x in range(129): height_image.set_pixel(x,y,Color(float(world.board.layout.heights[y*129+x]),0,0))
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
	drops.lifetime = 1.35
	drops.preprocess = 1.35
	drops.local_coords = false
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(22,2,22)
	drops.spread = 3
	drops.gravity = Vector3.ZERO
	drops.initial_velocity_min = 18
	drops.initial_velocity_max = 23
	drops.scale_amount_min = 0.65
	drops.scale_amount_max = 1.15
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.018,0.24)
	mesh.material = rain_material
	drops.mesh = mesh
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(drops)

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
