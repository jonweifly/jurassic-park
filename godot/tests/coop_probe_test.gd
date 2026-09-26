extends SceneTree
var port := 24566
var full := false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="): port=int(arg.trim_prefix("--port="))
		if arg=="--full": full=true
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled=false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.coop.join("127.0.0.1",port,"camp" if full else "wrong")
	var end := Time.get_ticks_msec()+10000
	while world.coop.connecting and Time.get_ticks_msec()<end: await process_frame
	var ok: bool = not world.coop.connected and not world.started and world.coop.status.contains("已满" if full else "口令不正确")
	print("COOP PROBE: ","full" if full else "password"," ","0 failures" if ok else "1 failures", " ",world.coop.status)
	world.free()
	quit(0 if ok else 1)
