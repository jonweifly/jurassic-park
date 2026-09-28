extends SceneTree
var sample: Node3D
var folder := "res://captures/cinematic-sample"
func _initialize() -> void: call_deferred("run")
func frame_wait(count: int) -> void:
	for i in range(count): await process_frame
func shot(name: String) -> void:
	await frame_wait(24)
	# Draw explicitly so an occluded preview window cannot suspend capture.
	RenderingServer.force_draw(false)
	var result := root.get_texture().get_image().save_png(folder.path_join(name+".png"))
	print("CINEMATIC CAPTURE ",name," ",result)
func run() -> void:
	root.size = Vector2i(1600,1000)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	sample = load("res://scenes/cinematic_sample.tscn").instantiate()
	root.add_child(sample)
	await frame_wait(30)
	await shot("00-topdown-default")
	sample.set_view(2,true)
	await shot("01-dusk-station")
	sample.toggle_weather()
	await frame_wait(70)
	await shot("02-rain-night")
	sample.set_view(1,true)
	await shot("03-dinosaur-night")
	sample.toggle_weather()
	await shot("04-dinosaur-day")
	sample.set_view(0,true)
	await shot("05-overview")
	sample.toggle_gate()
	for i in range(250): await process_frame
	await shot("06-gate-open")
	sample.set_view(0,true)
	sample.toggle_weather()
	sample.toggle_power()
	await shot("07-power-off")
	var report := {"viewport":str(root.size),"renderer":RenderingServer.get_current_rendering_method(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"gate_amount":sample.gate_amount,"powered":sample.powered,"animation":sample.animator.current_animation if sample.animator else "missing"}
	FileAccess.open(folder.path_join("capture-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CINEMATIC REPORT ",JSON.stringify(report))
	quit()
