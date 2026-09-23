extends Node3D

var route := PackedVector3Array()
var speed: float = 5.0
var health: float = 150.0
var max_health: float = 150.0
var age: float = 0.0
var is_dinosaur := false
var attack_cooldown := 0.0
var path_cooldown := 0.0
var last_board_revision := -1
var target_id := -1
var swing := 0.0
var dying := false
var death_clock := 0.8
var animation_state: String:
	get: return visual.state if visual else ""
var attack_damage := 12.0
var attack_interval := 1.0
var health_label: Label3D
var selection: MeshInstance3D
var navigation: RefCounted
var body_radius := 0.30
var current_speed := 0.0
var movement_blocked := false # Transient collision outcome, never persisted.
var travelled := 0.0
var carrying := false
var work_state := ""
var work_timeout := 0.0
var cargo_kind := ""
@onready var visual: Node = $Visual

func _ready() -> void:
	health_label = Label3D.new()
	health_label.position.y = 3.2 if is_dinosaur else 2.8
	health_label.font_size = 28
	health_label.pixel_size = 0.012
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_label.no_depth_test = true
	add_child(health_label)
	selection = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.68
	ring.outer_radius = 0.78
	ring.rings = 24
	ring.ring_segments = 6
	selection.mesh = ring
	selection.position.y = 0.09
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("87dfae")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection.material_override = material
	selection.visible = not is_dinosaur
	add_child(selection)

func work_pose(kind: String, target: Vector3, phase: float, dt: float) -> void:
	work_state = kind
	work_timeout = 0.15
	var direction := target - position
	visual.face(direction,dt,12)
	visual.seek_work(kind,phase,dt)
	if navigation: visual.ground(navigation.layout)
	visual.correct_work(kind,target,phase)
	visual.show_equipment(kind,carrying,cargo_kind)

func segment_open(from: Vector3, to: Vector3) -> bool:
	if not navigation: return true
	if not navigation.body_segment_open(from, to, body_radius): return false
	# Sweep the cell transitions, including diagonal corners. Existing grid owns collision.
	var previous: Vector2i = navigation.cell_at(from)
	var steps := maxi(1, ceili(from.distance_to(to) / 0.18))
	for i in range(1, steps + 1):
		var cell: Vector2i = navigation.cell_at(from.lerp(to, float(i) / steps))
		if cell == previous: continue
		if not navigation.is_open(cell): return false
		if cell.x != previous.x and cell.y != previous.y:
			if not navigation.is_open(Vector2i(cell.x, previous.y)) or not navigation.is_open(Vector2i(previous.x, cell.y)): return false
		previous = cell
	return true

func advance(dt: float) -> void:
	movement_blocked = false
	age += dt
	attack_cooldown = maxf(0, attack_cooldown - dt)
	path_cooldown -= dt
	swing = maxf(0, swing - dt * 4)
	work_timeout = maxf(0, work_timeout - dt)
	if health <= 0:
		play_animation("death", dt)
		visual.show_equipment("death",false,"")
		selection.hide()
		health_label.hide()
		return
	var before := position
	if not route.is_empty() and speed > 0:
		var acceleration := speed * 7.0
		var old_speed := current_speed
		current_speed = move_toward(current_speed, speed, acceleration * dt)
		var acceleration_time := absf(current_speed - old_speed) / acceleration
		var budget := (old_speed + current_speed) * 0.5 * acceleration_time + current_speed * (dt - acceleration_time)
		while budget > 0.00001 and not route.is_empty():
			var target := route[0]
			var direction := target - position
			direction.y = 0
			var distance := direction.length()
			if distance < 0.001:
				route.remove_at(0)
				continue
			var step := minf(budget, distance)
			var next := position + direction / distance * step
			if not segment_open(position, next):
				movement_blocked = true
				route.clear()
				current_speed = 0
				break
			position = next
			if navigation and navigation.layout: position.y = navigation.layout.height_at(position.x, position.z)
			budget -= step
			if step >= distance: route.remove_at(0)
		if position.distance_squared_to(before) > 0.00001:
			var heading := position - before
			visual.face(heading,dt)
	else: current_speed = 0
	var moved := Vector2(position.x - before.x, position.z - before.z).length()
	travelled += moved
	var moving := moved > 0.0001
	if moving or work_timeout <= 0 or swing > 0:
		var state := "attack" if swing > 0 else (("carry" if moving else "carry_idle") if carrying else ("walk" if moving else "idle"))
		play_animation(state, dt * clampf(moved / maxf(0.001, dt * visual.locomotion_reference_speed(state)), 0.25, 3.5) if moving else dt)
		visual.show_equipment(state,carrying,cargo_kind)
		if navigation: visual.ground(navigation.layout)
	health_label.text = "%d / %d" % [maxi(0, int(health)), int(max_health)] if health < max_health else ""
	health_label.modulate = Color("f68b73") if is_dinosaur else Color("b9e2c0")
	if is_dinosaur and get_meta("species", "") in ["elite_raptor", "alpha_trex", "spitter"]:
		health_label.text = preload("res://scripts/dinosaur_catalog.gd").spec(str(get_meta("species"))).name + "\n%d / %d" % [maxi(0, int(health)), int(max_health)]
		health_label.modulate = Color("edbb68")

func play_animation(state: String, dt: float) -> void:
	visual.play(state,dt)
