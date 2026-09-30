extends CanvasLayer
const PreferencesPanel = preload("res://scripts/preferences_panel.gd")
const GuidePanel = preload("res://scripts/guide_panel.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Session = preload("res://scripts/session.gd")
const ExpeditionPanel = preload("res://scripts/expedition_panel.gd")
const Features = preload("res://scripts/feature_policy.gd")
const Mini = preload("res://scripts/minimap.gd")
const KillStatsPanel = preload("res://scripts/kill_stats_panel.gd")
var kill_stats: RefCounted
var kill_stats_button: Button
var pause_stats_button: Button
var content_seed_input: LineEdit
var profession_select: OptionButton
var duration_select: OptionButton
var difficulty_select: OptionButton
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
var priority_button: OptionButton
var focus_button: Button
var clear_focus_button: Button
var health: ProgressBar
var objective: Label
var tip: Label
var minimap: Control
var build_buttons: Dictionary = {}
var build_key_labels: Dictionary = {}
var pause_panel: PanelContainer
var pause_title: Label
var resume_button: Button
var research_button: Button
var demolish_button: Button
var bottom: PanelContainer
var start_panel: PanelContainer
var notification_time := 0.0
var font: SystemFont
var sound_panel: PanelContainer
var settings_button: Button
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
const TowerCommands = preload("res://scripts/tower_commands.gd")
var tower_commands: RefCounted
var refit_buttons: Dictionary = {}
var outfit_panel: RefCounted
var outfit_button: Button
var kit_button: Button
var workshop_button: Button
var camp_view_button: Button
var field_notice: Label
var reinforce_button: Button
var repair_button: Button
var rotate_build_button: Button

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_font_override("font", font)
	root.add_theme_color_override("font_color", Color("e7e4cc"))
	root.theme = preload("res://scripts/ui_theme.gd").make(font)
	add_child(root)
	var status_line := HBoxContainer.new()
	status_line.add_theme_constant_override("separation", 14)
	resource_label = label("", 16)
	resource_label.custom_minimum_size.x = 300
	resource_label.size_flags_horizontal = Control.SIZE_FILL
	resource_label.clip_text = true
	resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_line.add_child(resource_label)
	clock_label = label("", 14)
	clock_label.custom_minimum_size.x = 150
	clock_label.size_flags_horizontal = Control.SIZE_FILL
	status_line.add_child(clock_label)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 4)
	settings_button = icon_button("设置  F10", "settings")
	settings_button.tooltip_text = "画面、镜头、声音和键位"
	settings_button.pressed.connect(func(): preferences_panel.open())
	tech_button = icon_button("科技  T", "tech")
	tech_button.pressed.connect(open_tech)
	action_row.add_child(tech_button)
	heal_button = icon_button("治疗  H", "heal")
	heal_button.tooltip_text = "前往帐篷，每秒消耗 1 黄金恢复 10 生命；医疗研究后恢复 25。"
	heal_button.pressed.connect(world.heal)
	action_row.add_child(heal_button)
	eat_button = icon_button("进食", "eat")
	eat_button.tooltip_text = "食用熟肉、浆果或补给，恢复饱腹度。"
	eat_button.pressed.connect(world.eat_food)
	action_row.add_child(eat_button)
	cook_button = icon_button("烤肉", "cook")
	cook_button.tooltip_text = "在已建成的营火消耗生肉制作熟肉。"
	cook_button.pressed.connect(world.cook_food)
	action_row.add_child(cook_button)
	action_row.add_child(settings_button)
	var pause := icon_button("暂停  Esc", "pause")
	pause.pressed.connect(world.toggle_pause)
	action_row.add_child(pause)
	kill_stats_button = icon_button("击杀统计", "stats")
	kill_stats_button.tooltip_text = "查看本局各类恐龙的击杀数量；打开时暂停。"
	kill_stats_button.pressed.connect(func(): kill_stats.open())
	action_row.add_child(kill_stats_button)
	for action_button in [tech_button, heal_button, eat_button, cook_button, settings_button]:
		action_button.custom_minimum_size.x = 52
	pause.custom_minimum_size.x = 72
	quest_box = panel(Color(0.05, 0.10, 0.08, 0.86))
	root.add_child(quest_box)
	quest_box.position = Vector2(18, 18)
	quest_box.custom_minimum_size = Vector2(260, 104)
	quest_box.tooltip_text = "营地目标与供电状态"
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
	journal_button = icon_button("探索 / 任务  L", "journal")
	journal_button.pressed.connect(func(): expedition_panel.open())
	quest_column.add_child(journal_button)
	camp_view_button = icon_button("查看营地", "camp")
	camp_view_button.pressed.connect(world.outfitting.view_camp)
	camp_view_button.tooltip_text = "只切换镜头；空格回到人物，不中断当前命令。"
	quest_column.add_child(camp_view_button)
	field_notice = label("", 12, Color("d6be88"))
	field_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	field_notice.custom_minimum_size.x = 250
	quest_column.add_child(field_notice)
	boarding_bar = ProgressBar.new()
	boarding_bar.custom_minimum_size.y = 8
	boarding_bar.max_value = Catalog.BOARDING_SECONDS
	boarding_bar.show_percentage = false
	boarding_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boarding_bar.hide()
	quest_column.add_child(boarding_bar)
	extraction_button = icon_button("前往 H 撤离点", "return")
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
	tip.offset_bottom = -220
	bottom = panel(Color(0.045, 0.085, 0.068, 0.97))
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	# Wrapped status/building text may raise the minimum height on narrow windows.
	# Keep the lower edge anchored while letting the panel grow toward the playfield.
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_left = 8
	bottom.offset_right = -8
	# The compact three-column layout needs a small allowance for wrapped
	# building labels on short windows; it remains close to the original height.
	# Content now drives a shorter panel; the right building grid no longer
	# reserves the old tall column beneath its last row.
	bottom.offset_top = -202
	bottom.offset_bottom = -6
	(bottom.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(8)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(columns)
	var left := HBoxContainer.new()
	left.custom_minimum_size.x = 300
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	minimap = Mini.new()
	minimap.world = world
	minimap.custom_minimum_size = Vector2(150, 96)
	minimap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(minimap)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 140
	left.add_child(info)
	info.add_child(label("选中单位", 11, Color("82998e")))
	selection_label = label("幸存者", 19, Color("dbc690"))
	info.add_child(selection_label)
	health = ProgressBar.new()
	health.custom_minimum_size.y = 7
	health.show_percentage = false
	var hp_style := StyleBoxFlat.new()
	hp_style.bg_color = Color("8fa877")
	health.add_theme_stylebox_override("fill", hp_style)
	hp_style.set_corner_radius_all(2)
	var hp_track := StyleBoxFlat.new()
	hp_track.bg_color = Color("0c1716")
	hp_track.set_corner_radius_all(2)
	health.add_theme_stylebox_override("background", hp_track)
	info.add_child(health)
	detail_label = label("", 12, Color("b4c1aa"))
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(detail_label)
	controls_hint = label("", 11, Color("879d85"))
	info.add_child(controls_hint)
	columns.add_child(section_divider())
	var middle := VBoxContainer.new()
	middle.custom_minimum_size.x = 470
	middle.add_theme_constant_override("separation", 7)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_stretch_ratio = 1.15
	# Status details belong to the bottom panel; keeping their width fixed also
	# prevents resource/time text from moving neighboring controls every frame.
	quest_column.remove_child(status_label)
	middle.add_child(status_line)
	status_label.custom_minimum_size.x = 340
	middle.add_child(status_label)
	middle.add_child(label("营地行动", 11, Color("91aa9c")))
	middle.add_child(action_row)
	var tactics := HFlowContainer.new()
	tactics.add_theme_constant_override("h_separation", 4)
	tactics.add_theme_constant_override("v_separation", 4)
	middle.add_child(tactics)
	priority_button = OptionButton.new()
	priority_button.icon = load("res://assets/ui/actions/focus.svg")
	priority_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for text in world.DefenseCombat.LABELS: priority_button.add_item(text)
	priority_button.item_selected.connect(func(index):
		var selected: Dictionary = world.selected_building()
		if not world.paused and not selected.is_empty(): world.set_tower_priority(selected.id,index))
	priority_button.tooltip_text = "设置选中箭塔的目标优先级；没有对应目标时攻击最近的恐龙。集火标记优先。"
	tactics.add_child(priority_button)
	focus_button = icon_button("集火标记", "focus")
	focus_button.tooltip_text = "点击后在场景中左键选择恐龙；不改变人物命令。右键或 Esc 取消选择。"
	focus_button.pressed.connect(func():
		if world.paused: return
		world.build_mode = ""
		world.defense.marking = not world.defense.marking)
	tactics.add_child(focus_button)
	clear_focus_button = icon_button("取消集火", "clear")
	clear_focus_button.pressed.connect(func():
		if world.paused: return
		world.clear_focus()
		world.defense.marking = false)
	tactics.add_child(clear_focus_button)
	outfit_button = icon_button("装备 / 探索  L", "outfit")
	outfit_button.pressed.connect(func(): outfit_panel.open())
	tactics.add_child(outfit_button)
	kit_button = icon_button("急救包  J", "heal")
	kit_button.pressed.connect(world.use_medkit)
	tactics.add_child(kit_button)
	columns.add_child(middle)
	columns.add_child(section_divider())
	var commands := VBoxContainer.new()
	commands.custom_minimum_size.x = 430
	commands.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commands.size_flags_stretch_ratio = 1.55
	columns.add_child(commands)
	var command_head := HBoxContainer.new()
	commands.add_child(command_head)
	var title := label("营地建造", 15, Color("d8c398"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_head.add_child(title)
	demolish_button = icon_button("拆除", "demolish")
	demolish_button.pressed.connect(request_demolition)
	demolish_button.hide()
	command_head.add_child(demolish_button)
	repair_button = icon_button("修理", "repair")
	repair_button.tooltip_text = "派幸存者修理；每秒消耗 1 木材恢复 8% 耐久。电门也可修理。"
	repair_button.pressed.connect(world.repair_selected)
	command_head.add_child(repair_button)
	for option in ["brace"]:
		var refit_button := icon_button(Catalog.REFITS[option].name, "brace")
		refit_button.pressed.connect(world.refit_selected.bind(option))
		refit_button.visible = false
		refit_buttons[option] = refit_button
		tactics.add_child(refit_button)
	reinforce_button = icon_button("加固箭塔", "brace")
	reinforce_button.pressed.connect(world.reinforce_selected)
	reinforce_button.hide()
	tactics.add_child(reinforce_button)
	research_button = icon_button("升级实验室  R", "tech")
	research_button.pressed.connect(world.research)
	command_head.add_child(research_button)
	workshop_button = icon_button("升级工坊", "workshop")
	workshop_button.tooltip_text = "基础建筑升级为装备工坊 · 10 木 / 8 金 / 15 秒 · 额外 1 点电力"
	workshop_button.pressed.connect(world.research.bind("workshop"))
	command_head.add_child(workshop_button)
	rotate_build_button = icon_button("旋转", "rotate")
	rotate_build_button.pressed.connect(world.rotate_building_preview)
	rotate_build_button.hide()
	command_head.add_child(rotate_build_button)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	commands.add_child(grid)
	for i in range(Catalog.ORDER.size()):
		var kind: String = Catalog.ORDER[i]
		var spec: Dictionary = Catalog.BUILDINGS[kind]
		var b := button("")
		b.custom_minimum_size = Vector2(98, 70)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = spec.description
		var tile: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
		tile.border_color = Color("506659")
		tile.border_width_left = 3
		b.add_theme_stylebox_override("normal", tile)
		var card := VBoxContainer.new()
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.offset_left = 4
		card.offset_right = -4
		card.offset_top = 3
		card.offset_bottom = -2
		card.add_theme_constant_override("separation", 0)
		b.add_child(card)
		var headline := HBoxContainer.new()
		headline.add_theme_constant_override("separation", 2)
		card.add_child(headline)
		var picture := TextureRect.new()
		picture.texture = load("res://assets/ui/buildings/%s.svg" % kind)
		picture.custom_minimum_size = Vector2(39, 39)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		headline.add_child(picture)
		var names := VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_theme_constant_override("separation", 0)
		headline.add_child(names)
		var shortcut := label(str(i + 1), 11, Color("e4c184"))
		names.add_child(shortcut)
		build_key_labels[kind] = shortcut
		var name_label := label(spec.name, 11, Color("e8e8d3"))
		name_label.clip_text = true
		names.add_child(name_label)
		var cost := label("木%d · 金%d · 电%d" % [spec.wood, spec.gold, spec.power], 10, Color("aac1ac"))
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost.clip_text = true
		card.add_child(cost)
		for part in [card, headline, picture, names, shortcut, name_label, cost]:
			part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.pressed.connect(world.select_build.bind(kind))
		build_buttons[kind] = b
		grid.add_child(b)
	tower_commands = TowerCommands.new(self, commands, command_head, title, grid)
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
	kill_stats = KillStatsPanel.new(self)
	outfit_panel = preload("res://scripts/outfitting_panel.gd").new(self)
	refresh_key_hints()
	refresh_save_info()

func make_camera_panel() -> void:
	camera_panel = panel(Color(0.05,0.10,0.08,0.88))
	root.add_child(camera_panel)
	camera_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	camera_panel.offset_left = -294
	camera_panel.offset_right = -18
	camera_panel.offset_top = 18
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
	sound_panel.offset_top = 18
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
	col.add_child(label("音量调整立即生效并保存。", 13, Color("91aa9c")))
	sound_panel.hide()

func make_start() -> void:
	start_panel = panel()
	root.add_child(start_panel)
	start_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	start_panel.offset_left = -265
	start_panel.offset_right = 265
	start_panel.offset_top = -260
	start_panel.offset_bottom = 260
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
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
	seed_row.visible = Features.peripheral_enabled
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
	profession_row.visible = Features.peripheral_enabled
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	col.add_child(choices)
	var time_column := VBoxContainer.new()
	time_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_child(time_column)
	time_column.add_child(label("游戏时长", 14, Color("a6b59e")))
	duration_select = OptionButton.new()
	duration_select.custom_minimum_size = Vector2(220, 42)
	for minutes in [25, 45, 60, 80]:
		duration_select.add_item("%d 分钟" % minutes, minutes)
	time_column.add_child(duration_select)
	var difficulty_column := VBoxContainer.new()
	difficulty_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_child(difficulty_column)
	difficulty_column.add_child(label("游戏难度", 14, Color("a6b59e")))
	difficulty_select = OptionButton.new()
	difficulty_select.custom_minimum_size = Vector2(220, 42)
	difficulty_select.add_item("普通")
	difficulty_select.add_item("困难")
	difficulty_select.tooltip_text = "困难：恐龙群随时间与营地成长增强。两种难度均可自由选择时长。"
	difficulty_column.add_child(difficulty_select)
	col.add_child(label("时长结束后，另有 5 分钟前往 H 区撤离。", 13, Color("a6b59e")))
	standard_start_button = button("开始游戏")
	standard_start_button.custom_minimum_size.y = 48
	standard_start_button.pressed.connect(func(): start_selected_session(selected_duration(), selected_difficulty()))
	col.add_child(standard_start_button)
	continue_button = button("继续上次游戏")
	continue_button.pressed.connect(world.load_game)
	col.add_child(continue_button)
	var browse := button("选择其他存档")
	browse.pressed.connect(request_load)
	col.add_child(browse)
	start_hint = label("", 13, Color("a6b59e"))
	col.add_child(start_hint)
	add_help_settings(col)
	load("res://scripts/coop_panel.gd").new(self,col)

func panel(color: Color = Color(0.055, 0.10, 0.082, 0.96)) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("526357")
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0, 0, 0, .28)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	style.set_content_margin_all(13)
	p.add_theme_stylebox_override("panel", style)
	return p

func section_divider() -> VSeparator:
	var divider := VSeparator.new()
	var style := StyleBoxLine.new()
	style.color = Color("3c5148")
	style.thickness = 1
	style.vertical = true
	divider.add_theme_stylebox_override("separator", style)
	divider.add_theme_constant_override("separation", 1)
	return divider

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
		style.bg_color = Color("23392f") if state == "normal" else Color("354d3e")
		if state == "pressed": style.bg_color = Color("172b24")
		if state == "disabled": style.bg_color = Color("14241e")
		style.border_color = Color("b5a477") if state == "hover" else Color("475e4e")
		style.set_border_width_all(1)
		style.border_width_top = 2 if state != "pressed" else 1
		style.set_corner_radius_all(3)
		style.set_content_margin_all(7)
		b.add_theme_stylebox_override(state, style)
	return b

func icon_button(text: String, icon_name: String) -> Button:
	var b := button(text)
	b.icon = load("res://assets/ui/actions/%s.svg" % icon_name)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("h_separation", 5)
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
	var resume_row := HBoxContainer.new()
	col.add_child(resume_row)
	resume_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume_row.add_child(resume_button)
	pause_stats_button = button("击杀统计")
	pause_stats_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_stats_button.pressed.connect(func(): kill_stats.open())
	resume_row.add_child(pause_stats_button)
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
	restart.name="RestartGame"
	restart.pressed.connect(func(): confirm_discard("返回开始界面？未保存的进度将丢失。", func(): get_tree().reload_current_scene()))
	col.add_child(restart)
	var exit_button := button("保存并退出")
	exit_button.name="ExitGame"
	exit_button.pressed.connect(world.exit_game)
	col.add_child(exit_button)
	pause_panel.hide()

func refresh(dt: float) -> void:
	preferences_panel.update()
	if outfit_panel.panel.visible: outfit_panel.refresh()
	outfit_button.disabled = not world.started
	outfit_button.text = "装备 / 探索 " + world.preferences.key_name("journal")
	var gear: Dictionary = world.outfitting.actor()
	kit_button.text = "急救包 %d  %s" % [gear.kits, world.preferences.key_name("kit")]
	kit_button.disabled = world.paused or not world.started or gear.kits <= 0 or gear.cooldown > 0 or world.hero.health >= world.hero.max_health
	kit_button.tooltip_text = "恢复 50 生命；冷却 %.0f 秒" % ceilf(gear.cooldown)
	camp_view_button.visible = world.started
	camp_view_button.text = "营地受袭！点击查看" if not world.outfitting.recent_hits.is_empty() else "查看营地"
	camp_view_button.modulate = Color("f1ac8b") if not world.outfitting.recent_hits.is_empty() else Color.WHITE
	field_notice.visible = world.started
	field_notice.text = world.director.field_window()
	if kill_stats.panel.visible: kill_stats.refresh()
	kill_stats_button.disabled = not world.started
	if expedition_panel.panel.visible: expedition_panel.refresh()
	expedition_summary.text = world.adventure.summary()
	if follow_button:
		follow_button.set_pressed_no_signal(world.camera_rig.following)
		follow_button.text = "跟随中" if world.camera_rig.following else "自由视角"
	var s = world.session
	settings_button.text = "设置  " + world.preferences.key_name("settings")
	resource_label.text = "木材 %d   黄金 %d   电力 %d/%d" % [s.wood, s.gold, s.demand(), s.supply()]
	clock_label.text = "%s·%s  %02d:%02d" % ["夜" if world.night else "昼", world.weather.NAMES[world.weather.kind], int(s.elapsed) / 60, int(s.elapsed) % 60]
	var left := maxi(0, int(s.duration - s.elapsed))
	objective.text = "坚守营地，等待撤离\n救援倒计时  %02d:%02d" % [left / 60, left % 60]
	var next_step: String = world.director.objective()
	objective.text = "%s\n救援倒计时  %02d:%02d" % [next_step, left / 60, left % 60]
	if s.phase == "evacuate": objective.text = "前往北侧 H 停机坪撤离\n剩余登机时间 %d 秒" % maxi(0, int(Catalog.EVACUATION_SECONDS - s.evacuation_elapsed))
	if s.phase == "evacuate":
		objective.text += "\n" + world.extraction_feedback.status()
		if s.mode in ["standard", "hard"]: objective.text += "\n登机 %.1f / %.0f 秒" % [s.boarding_progress, Catalog.BOARDING_SECONDS]
	extraction_button.visible = world.extraction_feedback.available()
	extraction_button.disabled = world.paused
	boarding_bar.visible = s.phase == "evacuate" and s.mode in ["standard", "hard"]
	boarding_bar.value = s.boarding_progress
	status_label.text = "%s · %s · 击退 %d\n%s" % [s.stage_name(), world.Regions.NAMES[world.Regions.at(world.hero.position)], s.kills, "断电：防御与研究停止" if s.demand() > s.supply() else "营地供电正常"]
	var b: Dictionary = world.selected_building()
	if b.is_empty():
		selection_label.text = "幸存者"
		health.max_value = world.hero.max_health
		health.value = world.hero.health
		detail_label.text = "生命 %d / %d\n%s\n携带 %s %d / %d  ·  %s 停止" % [world.hero.health, world.hero.max_health, world.order_description(), ("木材" if world.worker.cargo_kind == "wood" else "化石") if world.worker.cargo > 0 else "空载", world.worker.cargo, world.worker.capacity(), world.preferences.key_name("stop")]
	else:
		var spec: Dictionary = Catalog.BUILDINGS[b.kind]
		var maximum := Catalog.max_health(b)
		selection_label.text = spec.name
		health.max_value = maximum
		health.value = b.hp
		detail_label.text = "%s\n生命 %d / %d%s" % ["施工剩余 %.1f 秒 · 左键继续" % b.remaining if b.remaining > 0 else spec.description, b.hp, maximum, " · 改造：" + Catalog.REFITS[b.refit].name if b.get("refit", "") in Catalog.REFITS else ""]
		if b.get("refit", "") in Catalog.REFITS:
			detail_label.text = "%s\n生命 %d / %d · %s" % [Catalog.REFITS[b.refit].description, b.hp, maximum, "改造剩余 %.0f 秒" % b.remaining if b.remaining > 0 else Catalog.REFITS[b.refit].name]
		if b.kind == "tower" and b.remaining <= 0:
			var damage: float = Catalog.attack_damage(b) * s.defense_multiplier() * (1.5 if world.Regions.at(world.board.point(b.cell)) == "mountain" else 1.0)
			var target: Node3D = world.defense.choose(b, world.board.point(b.cell))
			var status: String = "断电" if s.supply() < s.demand() else ("等待目标" if target == null else "攻击：" + world.Dinosaurs.spec(target.get_meta("species")).name)
			detail_label.text = "生命 %d / %d%s\n%.1f 伤害 / %.2f 秒 · %.1f 米\n%s" % [b.hp, maximum, " · 已加固" if b.get("reinforced", false) else "", damage, Catalog.attack_interval(b), Catalog.attack_range(b), status]
			if b.get("refit", "") in Catalog.REFITS: selection_label.text = Catalog.REFITS[b.refit].name + "塔"
	priority_button.visible = not b.is_empty() and b.kind == "tower"
	priority_button.disabled = world.paused
	if priority_button.visible: priority_button.select(world.DefenseCombat.PRIORITIES.find(Catalog.target_priority(b)))
	focus_button.disabled = world.paused
	focus_button.text = "点击恐龙…" if world.defense.marking else "集火标记"
	clear_focus_button.visible = world.defense.focused() != null or world.defense.marking
	clear_focus_button.disabled = world.paused
	for kind in build_buttons:
		var reason: String = s.can_afford(kind)
		build_buttons[kind].tooltip_text = Catalog.BUILDINGS[kind].description + ("\n" + reason if not reason.is_empty() else "")
		build_buttons[kind].modulate = Color("e6cb89") if world.build_mode == kind else Color.WHITE
	workshop_button.visible = not b.is_empty() and b.kind == "lab" and world.build_mode.is_empty()
	workshop_button.disabled = world.paused or b.get("remaining", 1) > 0
	research_button.disabled = b.is_empty() or b.kind != "lab" or b.remaining > 0
	research_button.visible = b.is_empty() or b.kind == "lab"
	rotate_build_button.visible = world.build_mode in ["shelter", "gate"]
	rotate_build_button.disabled = world.paused or not world.started or s.phase != "playing"
	rotate_build_button.text = "旋转  " + world.preferences.key_name("upgrade")
	rotate_build_button.tooltip_text = "每次旋转 90°；预览显示实际朝向，Shift 连续建造会保留朝向。"
	if rotate_build_button.visible: research_button.hide()
	repair_button.visible = not b.is_empty() and b.remaining <= 0 and b.hp < Catalog.max_health(b)
	repair_button.disabled = world.paused or s.wood < 1
	demolish_button.visible = not b.is_empty()
	demolish_button.disabled = world.paused or s.phase not in ["playing", "evacuate"]
	if not b.is_empty():
		var refund: Dictionary = s.demolition_quote(b.id)
		demolish_button.tooltip_text = "返还 %d 木 / %d 金；拆除后立即恢复通路。" % [refund.get("wood", 0), refund.get("gold", 0)]
	for option in refit_buttons:
		var can_show: bool = not b.is_empty() and b.remaining <= 0 and b.get("refit", "") == "" and b.kind in Catalog.REFITS[option].kinds
		refit_buttons[option].visible = can_show
		var error: String = s.refit_error(b.get("id", -1), option)
		refit_buttons[option].disabled = world.paused or not error.is_empty()
		refit_buttons[option].tooltip_text = "%s\n%d 木 / %d 金 / %.0f 秒；方向不可更换%s" % [Catalog.REFITS[option].description, Catalog.REFITS[option].wood, Catalog.REFITS[option].gold, Catalog.REFITS[option].time, "\n" + error if not error.is_empty() else ""]
	reinforce_button.visible = not b.is_empty() and b.kind == "tower" and b.remaining <= 0 and not b.get("reinforced", false)
	if reinforce_button.visible:
		var reinforce_error: String = s.reinforce_error(b.id)
		reinforce_button.disabled = world.paused or not reinforce_error.is_empty()
		reinforce_button.tooltip_text = "耐久上限 +120，保留原有伤势；可与攻击专精叠加。\n12 木 / 10 金 / 12 秒；施工期间停火。" + ("\n" + reinforce_error if not reinforce_error.is_empty() else "")
	tower_commands.refresh(b)
	eat_button.visible = Features.peripheral_enabled
	cook_button.visible = Features.peripheral_enabled
	journal_button.visible = Features.peripheral_enabled
	notification_time = maxf(0, notification_time - dt)
	if world.defense.marking:
		tip.text = "左键恐龙：标记集火 · 右键 / Esc：取消"
	elif notification_time <= 0 and not world.build_mode.is_empty():
		var reason: String = world.placement_error(world.hover_cell)
		if reason.is_empty(): reason = world.placement_warning(world.hover_cell)
		var rotate_hint := " · %s 旋转 · Shift 连建" % world.preferences.key_name("upgrade") if world.build_mode in ["shelter", "gate"] else ""
		tip.text = "左键建造 %s%s · 右键取消%s" % [Catalog.BUILDINGS[world.build_mode].name, rotate_hint, "  |  " + reason if not reason.is_empty() else ""]
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
	pause_panel.visible = world.started and not outfit_panel.panel.visible and not kill_stats.panel.visible and not confirmation.visible and not tech_panel.visible and not load_panel.visible and not expedition_panel.panel.visible and not preferences_panel.panel.visible and not guide_panel.panel.visible and (world.paused or s.phase in ["won", "lost"])
	if camera_panel: camera_panel.visible = not outfit_panel.panel.visible and not kill_stats.panel.visible and not start_panel.visible and not pause_panel.visible and not tech_panel.visible and not load_panel.visible and not expedition_panel.panel.visible and not preferences_panel.panel.visible and not guide_panel.panel.visible
	modal_shade.visible = outfit_panel.panel.visible or kill_stats.panel.visible or confirmation.visible or start_panel.visible or pause_panel.visible or tech_panel.visible or load_panel.visible or expedition_panel.panel.visible or preferences_panel.panel.visible or guide_panel.panel.visible
	resume_button.visible = not s.phase in ["won", "lost"]
	pause_title.text = "成功撤离侏罗纪公园" if s.phase == "won" else (("幸存者已阵亡" if world.hero.health <= 0 else "未能及时撤离") if s.phase == "lost" else "营地已暂停")
	if world.coop.ui: world.coop.ui.refresh()

func toast(message: String) -> void:
	if world.coop and world.coop.forward_notice(message): return
	tip.text = message
	notification_time = 4.0

func covers(screen: Vector2) -> bool:
	if world.coop.ui:
		var ui = world.coop.ui
		if ui.panel.visible or (ui.room_button.visible and ui.room_button.get_global_rect().has_point(screen)) or (ui.revive_button.visible and ui.revive_button.get_global_rect().has_point(screen)): return true
	if outfit_panel.panel.visible or kill_stats.panel.visible: return true
	return quest_box.get_global_rect().has_point(screen) or bottom.get_global_rect().has_point(screen) or pause_panel.visible or tech_panel.visible or load_panel.visible or expedition_panel.panel.visible or preferences_panel.panel.visible or guide_panel.panel.visible or confirmation.visible or start_panel.visible or (camera_panel and camera_panel.visible and camera_panel.get_global_rect().has_point(screen))

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
	tech_panel.offset_top = -300
	tech_panel.offset_bottom = 300
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	tech_panel.add_child(col)
	col.add_child(label("营地科技", 26, Color("d8c38d")))
	tech_status = label("", 14, Color("b4c1aa"))
	tech_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tech_status.custom_minimum_size = Vector2(640, 52)
	col.add_child(tech_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var entries := VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries.add_theme_constant_override("separation", 5)
	scroll.add_child(entries)
	for tech in Catalog.TECH_ORDER:
		var spec: Dictionary = Catalog.TECH[tech]
		var b := button("")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 62
		b.pressed.connect(world.begin_technology.bind(tech))
		b.tooltip_text = spec.description
		tech_buttons[tech] = b
		entries.add_child(b)
	col.add_child(label("面板打开时游戏暂停；关闭后研究随游戏时间推进。", 13, Color("a6b59e")))
	var close := button("返回营地  Esc")
	close.pressed.connect(close_tech)
	col.add_child(close)
	tech_panel.hide()

func open_tech() -> void:
	if not world.started or world.session.phase not in ["playing", "evacuate"]: return
	if kill_stats.panel.visible: kill_stats.close()
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
			continue_button.text = "继续上次游戏 · %s · %02d:%02d%s" % [Session.mode_name(s.mode), int(s.elapsed) / 60, int(s.elapsed) % 60, "（完好记录）" if result.recovered else ""]
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
		b.text = "%s · %s\n%s · %02d:%02d · 生命 %d · 木 %d / 金 %d" % [names[slot], date, "撤离中" if s.phase == "evacuate" else (Session.mode_name(s.mode)), int(s.elapsed + s.evacuation_elapsed) / 60, int(s.elapsed + s.evacuation_elapsed) % 60, saved.data.hero.health, s.wood, s.gold]

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
	confirmation.theme = root.theme
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
	if world.coop.active:
		toast("合作局请返回菜单后选择继续合作存档。")
		return
	if kill_stats.panel.visible: kill_stats.close()
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

func open_art_sample() -> void:
	if world.started or world.coop.active: return
	var result := get_tree().change_scene_to_file("res://scenes/cinematic_sample.tscn")
	if result != OK: toast("美术样板暂时无法打开：" + str(result))

func add_help_settings(parent: Node, allow_art_preview: bool = false) -> void:
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
	if allow_art_preview:
		var preview := button("01 美术样板")
		preview.name = "CinematicSampleEntry"
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.tooltip_text = "独立场景：俯视检查新美术，也可切换近景。尚未接入人物操控与建造。"
		preview.pressed.connect(open_art_sample)
		row.add_child(preview)

func refresh_key_hints() -> void:
	var keys = world.preferences
	tech_button.text = "科技  " + keys.key_name("tech")
	heal_button.text = "治疗  " + keys.key_name("heal")
	journal_button.text = "探索日志  " + keys.key_name("journal")
	research_button.text = "升级实验室  " + keys.key_name("upgrade")
	save_button.text = "保存游戏  " + keys.key_name("save")
	load_button.text = "选择存档  " + keys.key_name("load")
	controls_hint.text = "左键使用工具 · 右键移动 · %s 归位 · %s 手册 · %s 设置" % [keys.key_name("center"), keys.key_name("guide"), keys.key_name("settings")]
	start_hint.text = "左键使用工具 · 右键移动 · %s 跟随角色 · %s 生存手册" % [keys.key_name("center"), keys.key_name("guide")]
	follow_button.tooltip_text = "%s：切换跟随；镜头平移键或方向键可退出跟随" % keys.key_name("follow")
	camera_panel.get_child(0).get_child(0).tooltip_text = "%s：回到并持续跟随角色；%s：重置镜头" % [keys.key_name("center"), keys.key_name("reset_camera")]
	for index in [2, 3]:
		camera_panel.get_child(0).get_child(index).tooltip_text = "%s / %s：旋转；中键拖动：旋转与俯仰；Shift + 中键：平移；滚轮：缩放" % [keys.key_name("rotate_left"), keys.key_name("rotate_right")]
	for i in range(Catalog.ORDER.size()):
		var kind: String = Catalog.ORDER[i]
		var spec: Dictionary = Catalog.BUILDINGS[kind]
		build_key_labels[kind].text = keys.key_name("build_%d" % i)

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

func selected_duration() -> float:
	return float(duration_select.get_selected_id()) * 60.0

func selected_difficulty() -> String:
	return "hard" if difficulty_select.selected == 1 else "standard"
