extends "res://tests/core_focus_input_test.gd"

func screenshot(name: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	var folder := "res://captures/coop"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	expect(root.get_texture().get_image().save_png(folder.path_join(name+".png"))==OK,"Native capture "+name)

func run() -> void:
	Save.directory="user://coop_input_fixture"
	world=load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled=false
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.sound.set_process(false)
	await settle()
	var ui = world.coop.ui
	expect(ui.entry_button.is_visible_in_tree(),"Start menu exposes coop entry")
	await screenshot("01-start")
	click(ui.entry_button.get_global_rect().get_center())
	await settle()
	expect(ui.panel.visible and not world.hud.start_panel.visible,"Native click opens connection dialog")
	expect(root.get_visible_rect().encloses(ui.panel.get_global_rect()),"Connection dialog fits viewport")
	await screenshot("02-room")
	ui.port.value=26000+int(Time.get_ticks_usec()%10000)
	click(ui.host_button.get_global_rect().get_center())
	await settle()
	expect(world.coop.hosting and world.started and not ui.panel.visible,"Native host button starts a room")
	expect(ui.room_button.visible and root.get_visible_rect().encloses(ui.room_button.get_global_rect()),"Compact room status is visible inside viewport")
	expect(world.hud.bottom.size.y<=210,"Coop preserves compact bottom HUD")
	await screenshot("03-host")
	click(ui.room_button.get_global_rect().get_center())
	await settle()
	expect(ui.panel.visible and ui.host_button.disabled and ui.join_button.disabled,"Room info cannot create a second peer while active")
	expect(ui.message.text.contains("UDP"),"Room info explains actual join port")
	click(ui.close_button.get_global_rect().get_center())
	await settle()
	world.coop.make_pawn(2)
	world.coop.pawns[2].health=0
	world.coop.pawns[2].position=world.hero.position+Vector3(2,0,0)
	world.session.gold=20
	await settle()
	expect(ui.revive_button.visible,"Downed teammate exposes rescue action")
	click(ui.revive_button.get_global_rect().get_center())
	await settle()
	expect(world.coop.pawns[2].health>0 and world.session.gold==10,"Native rescue click revives and spends exactly once")
	world.toggle_pause()
	await settle()
	expect(world.hud.pause_panel.visible and not world.hud.save_button.disabled and world.hud.load_button.disabled,"Host pause offers coop save and blocks single-player load")
	await screenshot("04-paused")
	world.free()
	print("COOP INPUT: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
