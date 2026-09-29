extends RefCounted
## Small additive poses over the imported clips. Simulation and work clocks stay in Pawn/Worker.
var contact: RefCounted
var gait_weight := 0.0
var bank := 0.0
var turn_velocity := 0.0
var elapsed := 0.0

func _init(surface_contact: RefCounted) -> void:
	contact = surface_contact

func rotate(name: String, angles: Vector3) -> void:
	var bone: Transform3D = contact.pose(name)
	bone.basis = Basis.from_euler(angles) * bone.basis
	contact.override_pose(name, bone)

func feet() -> Array[Transform3D]:
	return [contact.pose("footL"), contact.pose("footR")]

func plant(previous: Array[Transform3D]) -> void:
	# The pelvis carries the weight shift; ankles retain the authored support/swing arc.
	for i in range(2):
		var side := "L" if i == 0 else "R"
		contact.solve("thigh" + side, "shin" + side, "foot" + side, previous[i].origin, previous[i].basis)

func locomotion(action: String, cycle: float, speed: float, dt: float) -> void:
	if action == "death":
		gait_weight = 0.0
		bank = 0.0
		return
	elapsed += dt
	var walking := action in ["walk", "carry"]
	var carrying := action in ["carry", "carry_idle"]
	gait_weight = lerpf(gait_weight, clampf(speed / 3.0, 0.0, 1.0) if walking else 0.0, 1.0 - exp(-10.0 * dt))
	bank = lerpf(bank, clampf(-turn_velocity * 0.026, -0.10, 0.10) if walking else 0.0, 1.0 - exp(-8.0 * dt))
	turn_velocity = 0.0
	if action not in ["walk", "carry", "idle", "carry_idle"]: return
	var planted := feet()
	var step := sin(cycle * TAU)
	var breath := sin(elapsed * 2.7)
	var sway := step * gait_weight
	var root: Transform3D = contact.pose("root")
	root.origin += Vector3(0.023 * sway, -0.012 * (1.0 - cos(cycle * TAU * 2.0)) * gait_weight, 0.0)
	root.basis = Basis.from_euler(Vector3(0.038 * gait_weight, 0.047 * sway, -0.025 * sway + bank)) * root.basis
	contact.override_pose("root", root)
	rotate("spine", Vector3((0.026 if carrying else 0.045) * gait_weight + breath * 0.009, -0.082 * sway, 0.019 * sway - bank * 0.30))
	rotate("neck", Vector3(-0.03 * gait_weight, 0.018 * sin(elapsed * 0.9) * (1.0 - gait_weight), -bank * 0.25))
	rotate("head", Vector3(-breath * 0.006, 0.026 * sway, 0.0))
	if not carrying:
		# Elbows trail the shoulder swing instead of both joints reversing together.
		for side in ["L", "R"]:
			var sign_side := 1.0 if side == "L" else -1.0
			rotate("forearm" + side, Vector3(0.075 * sin(cycle * TAU - 0.6) * sign_side * gait_weight, 0.0, 0.0))
	plant(planted)

func work(action: String, phase: float) -> void:
	var impact := 0.65 if action == "build" else 1.1
	var windup := 0.48 if action == "build" else 0.85
	var end := 0.9 if action == "build" else 1.35
	var load := smoothstep(0.0, windup, phase)
	var strike := smoothstep(windup, impact, phase)
	var recover := smoothstep(impact + 0.025, end, phase)
	var anticipation := load * (1.0 - strike)
	var follow := strike * (1.0 - recover)
	var compact := 0.62 if action == "build" else 1.0
	var planted := feet()
	var step_in := smoothstep(0.0, 0.24, phase)
	var stance := step_in * (1.0 - recover)
	# A short lead-foot step opens a working stance; its lift ends before the strike.
	planted[0].origin += Vector3(-0.028 * stance, 0.038 * sin(step_in * PI) * (1.0 - recover), 0.095 * stance)
	var root: Transform3D = contact.pose("root")
	root.origin += Vector3((-0.025 * anticipation + 0.022 * follow) * compact, -0.025 * anticipation - 0.025 * follow, 0.018 * follow)
	root.basis = Basis.from_euler(Vector3(0.0, (-0.075 * anticipation + 0.025 * follow) * compact, -0.022 * anticipation)) * root.basis
	contact.override_pose("root", root)
	# A visible shoulder windup transfers into the hips, then settles after contact.
	rotate("spine", Vector3((-0.075 * anticipation + 0.022 * follow) * compact, (-0.13 * anticipation + 0.035 * follow) * compact, 0.025 * anticipation))
	rotate("neck", Vector3(0.03 * anticipation, 0.10 * anticipation * compact, 0.0))
	rotate("upper_armL", Vector3(-0.045 * anticipation, -0.065 * anticipation, -0.035 * follow))
	plant(planted)
