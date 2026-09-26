extends "res://tests/core_focus_input_test.gd"
const Catalog = preload("res://scripts/catalog.gd")

func screenshot(name: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	var folder := "res://captures/tower-upgrades"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	expect(root.get_texture().get_image().save_png(folder.path_join(name+".png"))==OK,"Capture "+name)
	var rect: Rect2 = world.hud.bottom.get_global_rect()
	expect(root.get_visible_rect().encloses(rect) and rect.size.y<=210,"Compact HUD: "+name)
	for c in world.hud.refit_buttons.values()+[world.hud.tower_commands.camp_button,world.hud.tower_commands.engineering_button]:
		if c.is_visible_in_tree(): expect(rect.encloses(c.get_global_rect()),"Contextual control fits: "+name)

func run() -> void:
	Save.directory="user://tower_upgrade_input_fixture"
	world=load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled=false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.sound.set_process(false)
	world.start_session(1500,"standard")
	world.prepare_demo()
	world.session.wood=1000
	world.session.gold=1000
	world.weather.preview_kind=0
	world.camera_size=25
	world.update_camera(0)
	world.vision.update()
	var tower: Dictionary
	var lab: Dictionary
	for b in world.session.buildings:
		if b.kind=="tower": tower=b
		if b.kind=="lab": lab=b
	await physics_frame
	await settle()
	click(world.camera.unproject_position(world.board.point(tower.cell)))
	await settle()
	expect(world.selected_id==tower.id and world.hud.tower_commands.panel.visible,"Scene selection opens tower commands")
	expect(not world.hud.tower_commands.grid.visible,"Contextual cards replace build grid")
	for option in ["range","rapid","heavy"]: expect(world.hud.refit_buttons[option].disabled,"Locked card: "+option)
	var original_height: float = world.hud.bottom.size.y
	click(world.hud.refit_buttons.range.get_global_rect().get_center())
	expect(tower.get("refit", "").is_empty(),"Clicking locked card cannot spend or upgrade")
	await screenshot("01-locked")
	click(world.hud.tower_commands.engineering_button.get_global_rect().get_center())
	await settle()
	expect(world.paused and world.hud.tech_panel.visible,"Research shortcut opens paused technology panel")
	expect(world.hud.tech_buttons.tower_engineering.disabled,"Foundation alone cannot research")
	world.hud.close_tech()
	world.selected_id=lab.id
	await settle()
	click(world.hud.research_button.get_global_rect().get_center())
	await settle()
	expect(lab.kind=="laboratory","Laboratory upgraded via existing command")
	world.session.work(lab.id,10)
	world.selected_id=tower.id
	await settle()
	click(world.hud.tower_commands.engineering_button.get_global_rect().get_center())
	await settle()
	expect(not world.hud.tech_buttons.tower_engineering.disabled,"Completed lab enables engineering card")
	await screenshot("02-research")
	click(world.hud.tech_buttons.tower_engineering.get_global_rect().get_center())
	await settle()
	expect(world.session.research_job.get("tech")=="tower_engineering","Native research click starts the new technology")
	world.hud.close_tech()
	world.session.tick(25)
	await settle()
	expect(not world.hud.refit_buttons.range.disabled,"Completion unlocks selected tower without reselection")
	await screenshot("03-choices")
	click(world.hud.refit_buttons.range.get_global_rect().get_center())
	await settle()
	expect(tower.get("refit")=="range" and world.hud.tower_commands.completed.visible,"Upgrade starts and displays progress")
	world.session.tick(12)
	world.update_buildings(0)
	world.selected_id=-1
	await settle()
	var weapon: Node3D = world.visuals[tower.id].get_node("Model/Gun")
	click(world.camera.unproject_position(weapon.global_position+Vector3.UP*.2))
	await settle()
	expect(world.selected_id==tower.id,"Clicking elevated weapon selects the upgraded tower")
	await screenshot("04-range-ready")
	expect(world.hud.bottom.size.y<=original_height,"Upgrade details do not increase panel height")
	click(world.hud.tower_commands.camp_button.get_global_rect().get_center())
	await settle()
	expect(world.selected_id==-1 and world.hud.tower_commands.grid.visible,"Rightmost camp command restores construction")
	world.selected_id=tower.id
	world.select_build("tower")
	await settle()
	expect(world.hud.tower_commands.grid.visible,"Keyboard building action restores construction grid")
	world.build_mode=""
	# Reuse tower as unupgraded fixture to verify all cards at several aspect ratios.
	tower.erase("refit")
	tower.invested_wood=15
	tower.invested_gold=15
	world.preferences.values.fullscreen=false
	world.preferences.apply(world)
	for size in [Vector2i(1000,800),Vector2i(1280,720),Vector2i(1920,1080)]:
		DisplayServer.window_set_size(size)
		await create_timer(.25).timeout
		await screenshot("choices-%dx%d" %[size.x,size.y])
		world.hud.open_tech()
		await settle()
		expect(root.get_visible_rect().encloses(world.hud.tech_panel.get_global_rect()),"Scrollable research panel fits viewport")
		world.hud.close_tech()
	world.free()
	print("TOWER UPGRADE INPUT: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
