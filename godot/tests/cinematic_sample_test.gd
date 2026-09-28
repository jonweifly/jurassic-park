extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func key(sample: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	sample._unhandled_input(event)
func run() -> void:
	var sample = load("res://scenes/cinematic_sample.tscn").instantiate()
	root.add_child(sample)
	await process_frame
	sample.set_process(false)
	check(sample.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,"Default preview must use the game's orthographic projection")
	check(is_equal_approx(sample.pitch,deg_to_rad(52)),"Default pitch must match the gameplay camera")
	check(is_equal_approx(sample.camera.size,36.0),"Default camera size must match gameplay")
	check(sample.animator != null and sample.animator.is_playing(),"Rex must have a playing animation")
	var arrays: Array = sample.get_node("RainforestSet/Ground").mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_NORMAL][0].y > .9,"Ground front normals must point upward")
	if DisplayServer.get_name() != "headless":
		for node in sample.get_node("RainforestSet").find_children("*","MultiMeshInstance3D",true,false):
			check(node.multimesh.buffer.size() == node.multimesh.instance_count*12,"Missing instance transforms: "+str(node.get_path()))
	key(sample,KEY_G)
	sample._process(1.0)
	check(sample.gate_amount > 0 and sample.gate_amount < 1,"Gate must animate gradually")
	check(sample.gate_left.position.x < 0 and sample.gate_right.position.x > 0,"Gate leaves must move apart")
	key(sample,KEY_P)
	var stopped: float = sample.gate_amount
	sample._process(1.0)
	check(is_equal_approx(sample.gate_amount,stopped),"Power loss must stop gate")
	key(sample,KEY_G)
	check(sample.gate_open,"Powerless gate must ignore requests")
	check(sample.hud.controls.gate.disabled,"Powerless gate button must be disabled")
	for light in sample.lights: check(not light.visible,"Power loss must extinguish fixtures")
	key(sample,KEY_P)
	sample._process(4.0)
	check(is_equal_approx(sample.gate_amount,1.0),"Gate must resume after power returns")
	key(sample,KEY_N)
	check(sample.night and sample.rain.visible,"Night must show rain")
	key(sample,KEY_N)
	check(not sample.night and not sample.rain.visible,"Dusk must hide rain immediately")
	key(sample,KEY_ESCAPE)
	var old_clock: float = sample.clock
	sample._process(1.0)
	check(is_equal_approx(old_clock,sample.clock),"Paused preview must stop animation time")
	key(sample,KEY_ESCAPE)
	for index in range(3):
		sample.set_view(index,true)
		check(not sample.camera.is_position_behind(sample.focus),"Camera must face its subject")
		check(sample.camera.is_position_in_frustum(sample.get_node("Tyrannosaur").position+Vector3.UP*2),"Rex must be inside preset camera frame")
	key(sample,KEY_TAB)
	check(not sample.hud.visible,"Tab must hide HUD")
	key(sample,KEY_TAB)
	check(sample.hud.visible,"Tab must restore HUD")
	await process_frame
	var bounds: Rect2 = sample.hud.canvas.get_global_rect()
	for name in ["StationControls","ViewControls"]:
		check(bounds.encloses(sample.hud.canvas.get_node(name).get_global_rect()),"HUD overflow: "+name)
	print("CINEMATIC TEST: ",checks," checks, ",failures," failures")
	sample.queue_free()
	await process_frame
	quit(1 if failures else 0)
