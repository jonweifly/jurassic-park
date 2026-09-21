extends CanvasLayer
const PreferencesPanel = preload("res://scripts/preferences_panel.gd")
const GuidePanel = preload("res://scripts/guide_panel.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Session = preload("res://scripts/session.gd")
const ExpeditionPanel = preload("res://scripts/expedition_panel.gd")
const Mini = preload("res://scripts/minimap.gd")
var content_seed_input: LineEdit
var profession_select: OptionButton
var standard_start_button: Button
var preferences_panel: RefCounted
var guide_panel: RefCounted
var tech_button: Button
var journal_button: Button
var controls_hint: Label
var start_hint: Label
var world: Node
var root: Control
var resource_label: Label
var clock_label: Label
var status_label: Label
var selection_label: Label
var detail_label: Label
var health: ProgressBar
var objective: Label
var tip: Label
var minimap: Control
var build_buttons: Dictionary = {}
var pause_panel: PanelContainer
var pause_title: Label
var resume_button: Button
var research_button: Button
var demolish_button: Button
var bottom: PanelContainer
var top: PanelContainer
var start_panel: PanelContainer
var notification_time := 0.0
var font: SystemFont
var sound_panel: PanelContainer
var sound_toggle: Button
var quest_box: PanelContainer
var camera_panel: PanelContainer
var follow_button: Button
var tech_panel: PanelContainer
var tech_buttons: Dictionary = {}
var tech_status: Label
var tech_was_paused := false
var save_label: Label
var continue_button: Button
var load_button: Button
var save_button: Button
var heal_button: Button
var eat_button: Button
var cook_button: Button
var modal_shade: ColorRect
var confirmation: ConfirmationDialog
var confirmation_action: Callable
var confirmation_was_paused := false
var load_panel: PanelContainer
var load_buttons: Dictionary = {}
var load_was_paused := false
var expedition_panel: RefCounted
var expedition_summary: Label
var extraction_button: Button
var boarding_bar: ProgressBar

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_font_override("font", font)
	root.add_theme_color_override("font_color", Color("e7e4cc"))
	add_child(root)
	top = panel()
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 18
	top.offset_right = -18
	top.offset_top = 14
	top.offset_bottom = 72
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	top.add_child(row)
	row.add_child(label("侏罗纪公园", 24, Color("d8c38d")))
	row.add_child(label("生 存 营 地", 13, Color("9eae98")))
	resource_label = label("", 18)
	resource_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(resource_label)
	clock_label = label("", 16)
	row.add_child(clock_label)
	sound_toggle = button("声音")
	sound_toggle.tooltip_text = "音量与静音"
	sound_toggle.pressed.connect(func(): sound_panel.visible = not sound_panel.visible)
	tech_button = button("科技  T")
	tech_button.pressed.connect(open_tech)
	row.add_child(tech_button)
	heal_button = button("治疗  H")
	heal_button.tooltip_text = "前往帐篷，每秒消耗 1 黄金恢复 10 生命；医疗研究后恢复 25。"
	heal_button.pressed.connect(world.heal)
	row.add_child(heal_button)
	eat_button = button("进食")
	eat_button.tooltip_text = "食用熟肉、浆果或补给，恢复饱腹度。"
	eat_button.pressed.connect(world.eat_food)
	row.add_child(eat_button)
	cook_button = button("烤肉")
	cook_button.tooltip_text = "在已建成的营火消耗生肉制作熟肉。"
	cook_button.pressed.connect(world.cook_food)
	row.add_child(cook_button)
	row.add_child(sound_toggle)
	var pause := button("暂停  Esc")
	pause.pressed.connect(world.toggle_pause)
	row.add_child(pause)
	quest_box = panel(Color(0.05, 0.10, 0.08, 0.86))
	root.add_child(quest_box)
	quest_box.position = Vector2(18, 88)
	quest_box.custom_minimum_size = Vector2(260, 124)
	quest_box.tooltip_text = "探索、调查委托和无线电统一收纳在探索日志中。"
	var quest_column := VBoxContainer.new()
	quest_column.add_theme_constant_override("separation", 4)
	quest_box.add_child(quest_column)
	quest_column.add_child(label("当前目标", 13, Color("d1b677")))
	objective = label("", 14)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.custom_minimum_size.x = 250
	quest_column.add_child(objective)
	status_label = label("", 11, Color("a6b59e"))
	quest_column.add_child(status_label)
	expedition_summary = label("", 11, Color("d5c490"))
	expedition_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	expedition_summary.custom_minimum_size.x = 250
	# Exploration, contracts and radio stay available from the journal without
	# permanently occupying the playfield with secondary text.
	expedition_summary.visible = false
	quest_column.add_child(expedition_summary)
	journal_button = button("探索 / 任务  L")
	journal_button.pressed.connect(func(): expedition_panel.open())
	quest_column.add_child(journal_button)
	boarding_bar = ProgressBar.new()
	boarding_bar.custom_minimum_size.y = 8
	boarding_bar.max_value = Catalog.BOARDING_SECONDS
	boarding_bar.show_percentage = false
	boarding_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boarding_bar.hide()
	quest_column.add_child(boarding_bar)
	extraction_button = button("前往 H 撤离点")
	extraction_button.tooltip_text = "沿实际可通行路线前往停机坪；途中仍可能遇到恐龙。"
	extraction_button.pressed.connect(world.go_to_extraction)
	extraction_button.hide()
	quest_column.add_child(extraction_button)
	tip = label("先建帐篷；木材送回后建营火、化石挖掘场，再发展电力和防线。", 16)
	tip.add_theme_color_override("font_outline_color", Color(0.04, 0.08, 0.05, 0.95))
	tip.add_theme_constant_override("outline_size", 5)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tip)
	tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tip.offset_top = -247
	tip.offset_bottom = -216
	bottom = panel(Color(0.045, 0.085, 0.068, 0.97))
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 18
	bottom.offset_right = -18
	bottom.offset_top = -210
	bottom.offset_bottom = -16
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	bottom.add_child(columns)
	minimap = Mini.new()
	minimap.world = world
	minimap.custom_minimum_size = Vector2(162, 162)
	columns.add_child(minimap)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 240
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(info)
	selection_label = label("幸存者", 22, Color("dbc690"))
	info.add_child(selection_label)
	health = ProgressBar.new()
	health.custom_minimum_size.y = 9
	health.show_percentage = false
	var hp_style := StyleBoxFlat.new()
	hp_style.bg_color = Color("8fa877")
	health.add_theme_stylebox_override("fill", hp_style)
	info.add_child(health)
	detail_label = label("", 14, Color("b4c1aa"))
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(detail_label)
	controls_hint = label("", 12, Color("879d85"))
	info.add_child(controls_hint)
	var commands := VBoxContainer.new()
	commands.custom_minimum_size.x = 665
	columns.add_child(commands)
	var command_head := HBoxContainer.new()
	commands.add_child(command_head)
	var title := label("营 地 建 造", 14, Color("cdb983"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_head.add_child(title)
	demolish_button = button("拆除")
	demolish_button.pressed.connect(request_demolition)
	demolish_button.hide()
	command_head.add_child(demolish_button)
	research_button = button("升级实验室  R")
	research_button.pressed.connect(world.research)
	command_head.add_child(research_button)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	commands.add_child(grid)
	for i in range(Catalog.ORDER.size()):
		var kind: String = Catalog.ORDER[i]
		var spec: Dictionary = Catalog.BUILDINGS[kind]
		var b := button("%d  %s\n木 %d   金 %d   电 %d" % [i + 1, spec.name, spec.wood, spec.gold, spec.power])
		b.custom_minimum_size = Vector2(162, 54)
		b.tooltip_text = spec.description
		b.pressed.connect(world.select_build.bind(kind))
		build_buttons[kind] = b
		grid.add_child(b)
	make_pause()
	make_start()
	make_sound_panel()
	make_camera_panel()
	make_tech()
	make_load_panel()
	make_confirmation()
	expedition_panel = ExpeditionPanel.new(self)
	preferences_panel = PreferencesPanel.new(self)
	guide_panel = GuidePanel.new(self)
	refresh_key_hints()
	refresh_save_info()

func make_camera_panel() -> void:
	camera_panel = panel(Color(0.05,0.10,0.08,0.88))
	root.add_child(camera_panel)
	camera_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	camera_panel.offset_left = -294
	camera_panel.offset_right = -18
	camera_panel.offset_top = 84
	var row := HBoxContainer.new()
	camera_panel.add_child(row)
	var center := button("归位")
	center.tooltip_text = "空格：回到并持续跟随幸存者；Home：重置镜头"
	center.pressed.connect(func(): world.camera_rig.center(true))
	row.add_child(center)
	follow_button = button("跟随")
	follow_button.toggle_mode = true
	follow_button.tooltip_text = "F：切换跟随；WASD 或方向键：平移并退出跟随"
	follow_button.pressed.connect(func(): world.camera_rig.center(not world.camera_rig.following))
	row.add_child(follow_button)
	for sign_value in [-1,1]:
		var rotate := button("↶" if sign_value < 0 else "↷")
		rotate.tooltip_text = "Q / E：旋转；中键拖动：旋转与俯仰；Shift + 中键：平移；滚轮：缩放"
		rotate.pressed.connect(func(): world.camera_rig.target_yaw += sign_value * PI / 4)
		row.add_child(rotate)

func make_sound_panel() -> void:
	sound_panel = panel()
	root.add_child(sound_panel)
	sound_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	sound_panel.offset_left = -370
	sound_panel.offset_right = -18
	sound_panel.offset_top = 82
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	sound_panel.add_child(col)
	col.add_child(label("声音", 20))
	for entry in [["Master", "总音量"], ["Ambience", "环境"], ["Effects", "音效"]]:
		var line := HBoxContainer.new()
		col.add_child(line)
		var title := label(entry[1], 14)
		title.custom_minimum_size.x = 70
		line.add_child(title)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = world.sound.levels[entry[0]] * 100
		slider.custom_minimum_size = Vector2(150, 26)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = entry[1]
		line.add_child(slider)
		var amount := label("%d%%" % slider.value, 14)
		amount.custom_minimum_size.x = 42
		line.add_child(amount)
		slider.value_changed.connect(func(value):
			world.sound.set_level(entry[0], value / 100.0)
			amount.text = "%d%%" % value)
	var mute := CheckBox.new()
	mute.text = "静音"
	mute.button_pressed = world.sound.muted
	mute.toggled.connect(world.sound.set_muted)
	col.add_child(mute)
	var actions := HBoxContainer.new()
	col.add_child(actions)
	var preview := button("试听")
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.pressed.connect(world.sound.play_ui.bind("ready"))
	actions.add_child(preview)
	var close := button("关闭")
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(sound_panel.hide)
	actions.add_child(close)
	sound_panel.hide()

func make_start() -> void:
	start_panel = panel()
	root.add_child(start_panel)
	start_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	start_panel.offset_left = -265
	start_panel.offset_right = 265
	start_panel.offset_top = -300
	start_panel.offset_bottom = 300
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	start_panel.add_child(col)
	var title := label("进入侏罗纪公园", 30, Color("d8c38d"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var instructions := label("建造营地，抵御恐龙，等待救援。\n直升机抵达后，5 分钟内完成撤离。", 16)
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(instructions)
	var seed_row := HBoxContainer.new()
	col.add_child(seed_row)
	seed_row.add_child(label("探索编号", 14))
	content_seed_input = LineEdit.new()
	content_seed_input.placeholder_text = "留空随机；输入编号重玩相同事件与委托"
	content_seed_input.max_length = 9
	content_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_seed_input.add_theme_font_override("font", font)
	content_seed_input.add_theme_font_size_override("font_size", 13)
	seed_row.add_child(content_seed_input)
	var profession_row := HBoxContainer.new()
	profession_row.add_theme_constant_override("separation", 10)
	col.add_child(profession_row)
	profession_row.add_child(label("幸存者职业", 14))
	profession_select = OptionButton.new()
	profession_select.custom_minimum_size = Vector2(360, 36)
	profession_select.add_theme_font_override("font", font)
	for id in ["explorer", "doctor", "hunter", "soldier"]:
		var spec: Dictionary = Session.PROFESSIONS[id]
		profession_select.add_item("%s：%s" % [spec.name, spec.description])
		profession_select.set_item_metadata(profession_select.item_count - 1, id)
	profession_row.add_child(profession_select)
	standard_start_button = button("标准生存 · 25 分钟  +  5 分钟撤离")
	standard_start_button.custom_minimum_size.y = 48
	standard_start_button.pressed.connect(start_selected_session.bind(1500.0, "standard"))
	col.add_child(standard_start_button)
	col.add_child(label("渐进威胁 · 随机无线电 · 可选调查委托 · 撤离遭遇", 13, Color("a6b59e")))
	col.add_child(label("长局模式 · 保留原有恐龙刷新节奏", 14, Color("a6b59e")))
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 10)
	col.add_child(choices)
	for minutes in [45, 60, 80]:
		var b := button("%d 分钟%s" % [minutes, ""])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 54
		b.pressed.connect(start_selected_session.bind(minutes * 60.0, "classic"))
		choices.add_child(b)
	continue_button = button("继续上次游戏")
	continue_button.pressed.connect(world.load_game)
	col.add_child(continue_button)
	var browse := button("选择其他存档")
	browse.pressed.connect(request_load)
	col.add_child(browse)
	start_hint = label("", 13, Color("a6b59e"))
	col.add_child(start_hint)
	add_help_settings(col)

func panel(color: Color = Color(0.055, 0.10, 0.082, 0.96)) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("566447")
	style.set_border_width_all(1)
	style.set_content_margin_all(13)
	p.add_theme_stylebox_override("panel", style)
	return p

func label(text: String, point_size: int = 16, color: Color = Color("e7e4cc")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", point_size)
	l.add_theme_color_override("font_color", color)
	return l

func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func(): world.sound.play_ui("click"))
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color("e2dfc5"))
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("243c2f") if state == "normal" else Color("43533b")
		if state == "disabled": style.bg_color = Color("17271f")
		style.border_color = Color("67724e") if state == "hover" else Color("3f523d")
		style.set_border_width_all(1)
		style.set_content_margin_all(8)
		b.add_theme_stylebox_override(state, style)
	return b

func make_pause() -> void:
	pause_panel = panel()
	root.add_child(pause_panel)
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_panel.offset_left = -230
	pause_panel.offset_right = 230
	pause_panel.offset_top = -230
	pause_panel.offset_bottom = 230
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	pause_panel.add_child(col)
	pause_title = label("营地已暂停", 26, Color("dbc690"))
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(pause_title)
	resume_button = button("继续生存")
	resume_button.pressed.connect(world.toggle_pause)
	col.add_child(resume_button)
	save_label = label("", 13, Color("a6b59e"))
	save_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_label.custom_minimum_size.x = 390
	col.add_child(save_label)
	save_button = button("保存游戏  F5")
	save_button.pressed.connect(world.save_game)
	col.add_child(save_button)
	load_button = button("选择存档  F9")
	load_button.pressed.connect(request_load)
	col.add_child(load_button)
	add_help_settings(col)
	var restart := button("重新开始")
	restart.pressed.connect(func(): confirm_discard("返回开始界面？未保存的进度将丢失。", func(): get_tree().reload_current_scene()))
	col.add_child(restart)
	var exit_button := button("保存并退出")
	exit_button.pressed.connect(world.exit_game)
	col.add_child(exit_button)
	pause_panel.hide()

func refresh(dt: float) -> void:
	preferences_panel.update()
	if expedition_panel.panel.visible: expedition_panel.refresh()
	expedition_summary.text = world.adventure.summary()
	if follow_button:
		follow_button.set_pressed_no_signal(world.camera_rig.following)
		follow_button.text = "跟随中" if world.camera_rig.following else "自由视角"
	var s = world.session
	sound_toggle.text = "已静音" if world.sound.muted or world.sound.levels.Master <= 0 else "声音"
	resource_label.text = "木材  %d       黄金  %d       电力  %d / %d" % [s.wood, s.gold, s.demand(), s.supply()]
	clock_label.text = "%s·%s  %02d:%02d" % ["夜" if world.night else "昼", world.weather.NAMES[world.weather.kind], int(s.elapsed) / 60, int(s.elapsed) % 60]
	var left := maxi(0, int(s.duration - s.elapsed))
	objective.text = "坚守营地，等待撤离\n救援倒计时  %02d:%02d" % [left / 60, left % 60]
	var next_step: String = world.director.objective()
	objective.text = "%s\n救援倒计时  %02d:%02d" % [next_step, left / 60, left % 60]
	if s.phase == "evacuate": objective.text = "前往北侧 H 停机坪撤离\n剩余登机时间 %d 秒" % maxi(0, int(Catalog.EVACUATION_SECONDS - s.evacuation_elapsed))
	if s.phase == "evacuate":
		objective.text += "\n" + world.extraction_feedback.status()
		if s.mode == "standard": objective.text += "\n登机 %.1f / %.0f 秒" % [s.boarding_progress, Catalog.BOARDING_SECONDS]
	extraction_button.visible = world.extraction_feedback.available()
	extraction_button.disabled = world.paused
	boarding_bar.visible = s.phase == "evacuate" and s.mode == "standard"
	boarding_bar.value = s.boarding_progress
	status_label.text = "%s · %s · %s · 击退 %d\n%s" % [s.stage_name(), s.profession_name(), world.Regions.NAMES[world.Regions.at(world.hero.position)], s.kills, "断电：防御与研究停止" if s.demand() > s.supply() else "营地供电正常"]
	var b: Dictionary = world.selected_building()
	if b.is_empty():
		selection_label.text = "幸存者"
		health.max_value = world.hero.max_health
		health.value = world.hero.health
		detail_label.text = "生命 %d / %d\n%s\n%s\n携带 %s %d / %d  ·  %s 停止" % [world.hero.health, world.hero.max_health, world.order_description(), s.survival_status(), ("木材" if world.worker.cargo_kind == "wood" else "化石") if world.worker.cargo > 0 else "空载", world.worker.cargo, world.worker.capacity(), world.preferences.key_name("stop")]
	else:
		var spec: Dictionary = Catalog.BUILDINGS[b.kind]
		selection_label.text = spec.name
		health.max_value = spec.hp
		health.value = b.hp
		detail_label.text = "%s\n生命 %d / %d" % ["施工剩余 %.1f 秒 · 右键继续" % b.remaining if b.remaining > 0 else spec.description, b.hp, spec.hp]
	for kind in build_buttons:
		var reason: String = s.can_afford(kind)
		build_buttons[kind].tooltip_text = Catalog.BUILDINGS[kind].description + ("\n" + reason if not reason.is_empty() else "")
		build_buttons[kind].modulate = Color("e6cb89") if world.build_mode == kind else Color.WHITE
	research_button.disabled = b.is_empty() or b.kind != "lab" or b.remaining > 0
	demolish_button.visible = not b.is_empty()
	demolish_button.disabled = world.paused or s.phase not in ["playing", "evacuate"]
	if not b.is_empty():
		var refund: Dictionary = s.demolition_quote(b.id)
		demolish_button.tooltip_text = "返还 %d 木 / %d 金；拆除后立即恢复通路。" % [refund.get("wood", 0), refund.get("gold", 0)]
	notification_time = maxf(0, notification_time - dt)
	if notification_time <= 0 and not world.build_mode.is_empty():
		var reason: String = world.placement_error(world.hover_cell)
		if reason.is_empty(): reason = world.placement_warning(world.hover_cell)
		tip.text = "左键建造 %s · 右键取消%s" % [Catalog.BUILDINGS[world.build_mode].name, "  |  " + reason if not reason.is_empty() else ""]
	elif notification_time <= 0: tip.text = ""
	heal_button.disabled = not world.started or world.paused or world.hero.health >= world.hero.max_health or s.phase not in ["playing", "evacuate"]
	eat_button.disabled = not world.started or world.paused or s.phase not in ["playing", "evacuate"] or (s.food + s.berries + s.cooked_meat) <= 0
	cook_button.disabled = not world.started or world.paused or s.phase not in ["playing", "evacuate"] or s.raw_meat <= 0 or not s.has_completed("fire")
	save_button.disabled = s.phase not in ["playing", "evacuate"]
	save_label.text = world.save_status + "\n每 2 分钟自动保存，保留最近 3 份；%s 手动保存。" % world.preferences.key_name("save")
	if s.phase in ["won", "lost"]:
		save_label.text = "生存 %02d:%02d  ·  击退 %d  ·  科技 %d\n返送资源 %d  ·  医疗消耗 %d 金\n可载入最近存档重试。" % [int(s.elapsed + s.evacuation_elapsed) / 60, int(s.elapsed + s.evacuation_elapsed) % 60, s.kills, s.technologies.size(), world.worker.delivered, s.healing_spent]
	if tech_panel.visible: refresh_tech()
	minimap.queue_redraw()
	start_panel.visible = not world.started and not load_panel.visible and not preferences_panel.panel.visible and not guide_panel.panel.visible
	pause_panel.visible = world.started and not confirmation.visible and not tech_panel.visible and not load_panel.visible and not expedition_panel.panel.visible and not preferences_panel.panel.visible and not guide_panel.panel.visible and (world.paused or s.phase in ["won", "lost"])
	if camera_panel: camera_panel.visible = not sound_panel.visible and not start_panel.visible and not pause_panel.visible and not tech_panel.visible and not load_panel.visible and not expedition_panel.panel.visible and not preferences_panel.panel.visible and not guide_panel.panel.visible
	modal_shade.visible = confirmation.visible or start_panel.visible or pause_panel.visible or tech_panel.visible or load_panel.visible or expedition_panel.panel.visible or preferences_panel.panel.visible or guide_panel.panel.visible
	resume_button.visible = not s.phase in ["won", "lost"]
	pause_title.text = "成功撤离侏罗纪公园" if s.phase == "won" else (("幸存者已阵亡" if world.hero.health <= 0 else "未能及时撤离") if s.phase == "lost" else "营地已暂停")

func toast(message: String) -> void:
	tip.text = message
	notification_time = 4.0

func covers(screen: Vector2) -> bool:
	return top.get_global_rect().has_point(screen) or quest_box.get_global_rect().has_point(screen) or bottom.get_global_rect().has_point(screen) or pause_panel.visible or tech_panel.visible or load_panel.visible or expedition_panel.panel.visible or preferences_panel.panel.visible or guide_panel.panel.visible or confirmation.visible or start_panel.visible or (sound_panel.visible and sound_panel.get_global_rect().has_point(screen)) or (camera_panel and camera_panel.visible and camera_panel.get_global_rect().has_point(screen))

func make_tech() -> void:
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.01, 0.025, 0.02, 0.72)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal_shade)
	root.move_child(modal_shade, pause_panel.get_index())
	tech_panel = panel()
	root.add_child(tech_panel)
	tech_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tech_panel.offset_left = -345
	tech_panel.offset_right = 345
	tech_panel.offset_top = -330
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	tech_panel.add_child(col)
	col.add_child(label("营地科技", 26, Color("d8c38d")))
	tech_status = label("", 14, Color("b4c1aa"))
	tech_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tech_status.custom_minimum_size = Vector2(640, 52)
	col.add_child(tech_status)
	for tech in Catalog.TECH_ORDER:
		var spec: Dictionary = Catalog.TECH[tech]
		var b := button("")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 62
		b.pressed.connect(world.begin_technology.bind(tech))
		b.tooltip_text = spec.description
		tech_buttons[tech] = b
		col.add_child(b)
	col.add_child(label("面板打开时游戏暂停；关闭后研究随游戏时间推进。", 13, Color("a6b59e")))
	var close := button("返回营地  Esc")
	close.pressed.connect(close_tech)
	col.add_child(close)
	tech_panel.hide()

func open_tech() -> void:
	if not world.started or world.session.phase not in ["playing", "evacuate"]: return
	if tech_panel.visible:
		close_tech()
		return
	if preferences_panel.panel.visible: preferences_panel.close()
	if guide_panel.panel.visible: guide_panel.close()
	if expedition_panel.panel.visible: expedition_panel.close()
	if load_panel.visible: close_load()
	tech_was_paused = world.paused
	world.paused = true
	world.build_mode = ""
	sound_panel.hide()
	tech_panel.show()
	refresh_tech()

func close_tech() -> void:
	tech_panel.hide()
	world.paused = tech_was_paused

func refresh_tech() -> void:
	var s = world.session
	tech_status.text = "库存：%d 木材 / %d 黄金    电力：%d / %d\n" % [s.wood, s.gold, s.demand(), s.supply()]
	if s.research_job.is_empty(): tech_status.text += "选择下一项研究。" if s.has_completed("laboratory") else "建造基础建筑 → 选中后按 %s 升级实验室。" % world.preferences.key_name("upgrade")
	else:
		tech_status.text += "%s · 剩余 %.0f 秒%s" % [Catalog.TECH[s.research_job.tech].name, s.research_job.remaining, "（已停止：正在撤离）" if s.phase == "evacuate" else ("（暂停：缺少实验室或电力）" if not s.research_powered() else "")]
	for tech in tech_buttons:
		var spec: Dictionary = Catalog.TECH[tech]
		var error: String = s.research_error(tech)
		var b: Button = tech_buttons[tech]
		b.text = "%s  ·  %d 木 / %d 金 / %d 秒%s\n%s" % [spec.name, spec.wood, spec.gold, spec.time, "  ✓ 已完成" if s.technologies.has(tech) else "", spec.description]
		b.disabled = not error.is_empty()
		b.tooltip_text = error if not error.is_empty() else spec.description

func refresh_save_info() -> void:
	var result: Dictionary = world.SaveStore.latest()
	if continue_button:
		continue_button.disabled = result.has("error")
		if not result.has("error"):
			var s: Dictionary = result.data.session
			continue_button.text = "继续上次游戏 · %s · %02d:%02d%s" % ["标准生存" if s.mode == "standard" else "长局模式", int(s.elapsed) / 60, int(s.elapsed) % 60, "（完好记录）" if result.recovered else ""]
	if load_button: load_button.disabled = result.has("error")
	var names := {"manual": "手动存档", "auto0": "自动存档 A", "auto1": "自动存档 B", "auto2": "自动存档 C", "manual_backup": "上次手动备份"}
	for slot in load_buttons:
		var saved: Dictionary = world.SaveStore.read_slot(slot)
		var b: Button = load_buttons[slot]
		b.disabled = saved.has("error")
		if saved.has("error"):
			b.text = names[slot] + " · " + saved.error
			continue
		var s: Dictionary = saved.data.session
		var timestamp := int(saved.data.saved_at / 1000000) + int(Time.get_time_zone_from_system().bias) * 60
		var date := Time.get_datetime_string_from_unix_time(timestamp, true)
		b.text = "%s · %s\n%s · %02d:%02d · 生命 %d · 木 %d / 金 %d" % [names[slot], date, "撤离中" if s.phase == "evacuate" else ("标准生存" if s.mode == "standard" else "长局模式"), int(s.elapsed + s.evacuation_elapsed) / 60, int(s.elapsed + s.evacuation_elapsed) % 60, saved.data.hero.health, s.wood, s.gold]

func request_demolition() -> void:
	if world.paused or not world.started: return
	var b: Dictionary = world.selected_building()
	if b.is_empty(): return
	var quote: Dictionary = world.session.demolition_quote(b.id)
	if quote.is_empty(): return
	var message := "拆除%s？返还 %d 木材 / %d 黄金。\n按建造投入的 50%% × 剩余耐久比例计算，向下取整；施工中同样适用。" % [Catalog.BUILDINGS[b.kind].name, quote.wood, quote.gold]
	if b.kind == "tent": message += "\n资源将改送其他可用帐篷；没有帐篷时保留携带物，等待重建。治疗会中止。"
	if b.kind == "generator": message += "\n供电减少，电力不足时防御和研究会暂停。"
	if b.kind == "laboratory": message += "\n研究费用不返还；没有其他实验室时保留研究进度，重建后可继续。"
	var id: int = b.id
	confirm_discard(message, func():
		world.paused = confirmation_was_paused
		world.demolish_building(id))

func make_confirmation() -> void:
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认操作"
	confirmation.ok_button_text = "确认"
	confirmation.cancel_button_text = "取消"
	confirmation.add_theme_font_override("font", font)
	root.add_child(confirmation)
	confirmation.confirmed.connect(func():
		if confirmation_action.is_valid(): confirmation_action.call())
	confirmation.canceled.connect(func(): world.paused = confirmation_was_paused)

func confirm_discard(message: String, action: Callable) -> void:
	confirmation_was_paused = world.paused
	world.paused = true
	confirmation_action = action
	confirmation.dialog_text = message
	confirmation.popup_centered(Vector2i(460, 150))

func make_load_panel() -> void:
	load_panel = panel()
	root.add_child(load_panel)
	load_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	load_panel.offset_left = -285
	load_panel.offset_right = 285
	load_panel.offset_top = -270
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	load_panel.add_child(col)
	col.add_child(label("选择存档", 26, Color("d8c38d")))
	col.add_child(label("载入后暂停，可查看营地状态再继续。", 14))
	for slot in ["manual", "auto0", "auto1", "auto2", "manual_backup"]:
		var b := button("")
		b.custom_minimum_size = Vector2(530, 66)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			if world.started and world.session.phase in ["playing", "evacuate"]:
				confirm_discard("载入此存档？未保存的进度将丢失。", world.load_game.bind(slot))
			else: world.load_game(slot))
		load_buttons[slot] = b
		col.add_child(b)
	var close := button("返回  Esc")
	close.pressed.connect(close_load)
	col.add_child(close)
	load_panel.hide()

func request_load() -> void:
	if load_panel.visible:
		close_load()
		return
	if tech_panel.visible: close_tech()
	if preferences_panel.panel.visible: preferences_panel.close()
	if guide_panel.panel.visible: guide_panel.close()
	if expedition_panel.panel.visible: expedition_panel.close()
	load_was_paused = world.paused
	world.paused = true
	sound_panel.hide()
	refresh_save_info()
	load_panel.show()

func close_load() -> void:
	load_panel.hide()
	world.paused = load_was_paused

func add_help_settings(parent: Node) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var guide_button := button("生存手册")
	guide_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_button.pressed.connect(func(): guide_panel.open())
	row.add_child(guide_button)
	var settings_button := button("游戏设置")
	settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_button.pressed.connect(func(): preferences_panel.open())
	row.add_child(settings_button)

func refresh_key_hints() -> void:
	var keys = world.preferences
	tech_button.text = "科技  " + keys.key_name("tech")
	heal_button.text = "治疗  " + keys.key_name("heal")
	journal_button.text = "探索日志  " + keys.key_name("journal")
	research_button.text = "升级实验室  " + keys.key_name("upgrade")
	save_button.text = "保存游戏  " + keys.key_name("save")
	load_button.text = "选择存档  " + keys.key_name("load")
	controls_hint.text = "右键下令 · %s 归位 · %s 手册 · %s 设置" % [keys.key_name("center"), keys.key_name("guide"), keys.key_name("settings")]
	start_hint.text = "右键移动与采集 · %s 跟随角色 · %s 生存手册" % [keys.key_name("center"), keys.key_name("guide")]
	follow_button.tooltip_text = "%s：切换跟随；镜头平移键或方向键可退出跟随" % keys.key_name("follow")
	camera_panel.get_child(0).get_child(0).tooltip_text = "%s：回到并持续跟随角色；%s：重置镜头" % [keys.key_name("center"), keys.key_name("reset_camera")]
	for index in [2, 3]:
		camera_panel.get_child(0).get_child(index).tooltip_text = "%s / %s：旋转；中键拖动：旋转与俯仰；Shift + 中键：平移；滚轮：缩放" % [keys.key_name("rotate_left"), keys.key_name("rotate_right")]
	for i in range(Catalog.ORDER.size()):
		var kind: String = Catalog.ORDER[i]
		var spec: Dictionary = Catalog.BUILDINGS[kind]
		build_buttons[kind].text = "%s  %s\n木 %d   金 %d   电 %d" % [keys.key_name("build_%d" % i), spec.name, spec.wood, spec.gold, spec.power]

func start_selected_session(duration: float, mode: String) -> void:
	var input := content_seed_input.text.strip_edges()
	if not input.is_empty() and (not input.is_valid_int() or int(input) < 1 or int(input) > 999999999):
		toast("探索编号请输入 1–999999999 的整数，或留空随机。")
		return
	var seed_value := int(input)
	if input.is_empty():
		var random := RandomNumberGenerator.new()
		random.randomize()
		seed_value = random.randi_range(1, 999999999)
	var profession := "explorer"
	if profession_select and profession_select.selected >= 0:
		profession = str(profession_select.get_item_metadata(profession_select.selected))
	world.start_session(duration, mode, seed_value, profession)
