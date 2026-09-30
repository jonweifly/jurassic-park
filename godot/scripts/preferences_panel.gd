extends RefCounted
const Preferences = preload("res://scripts/preferences.gd")
var hud: Node
var world: Node
var panel: PanelContainer
var tabs: TabContainer
var message: Label
var countdown: Label
var apply_button: Button
var keep_button: Button
var undo_button: Button
var controls := {}
var key_buttons := {}
var draft := {}
var draft_keys := {}
var baseline := {}
var baseline_keys := {}
var listening := ""
var was_paused := false
var preview := false
var preview_deadline := 0
var syncing := false

func _init(owner_hud: Node) -> void:
	hud = owner_hud
	world = hud.world
	panel = hud.panel()
	panel.add_theme_font_override("font", hud.font)
	hud.root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -430
	panel.offset_right = 430
	panel.offset_top = -340
	panel.offset_bottom = 340
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(hud.label("游戏设置", 26, Color("d8c38d")))
	column.add_child(hud.label("画面、镜头、声音与操作习惯，集中在这里调整。", 14, Color("a6b59e")))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	var graphics := page("画面")
	option(graphics, "quality", "画质", ["流畅 · 关闭阴影和装饰草丛", "均衡 · 2×抗锯齿 / 标准阴影", "精细 · 4×抗锯齿 / 高清阴影"])
	check(graphics, "fullscreen", "全屏显示（切换后需在 15 秒内确认）")
	check(graphics, "vsync", "垂直同步")
	option(graphics, "fps", "帧率上限", ["不限帧率", "30 FPS", "60 FPS", "120 FPS"], [0, 30, 60, 120])
	var info: Label = hud.label("画质只影响阴影、抗锯齿和装饰草丛；树木、恐龙、地形和通行规则保持一致。", 14, Color("a6b59e"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	graphics.add_child(info)
	var sample: Button = hud.button("01 美术样板 · 独立预览")
	sample.name = "CinematicSampleEntry"
	sample.pressed.connect(hud.open_art_sample)
	graphics.add_child(sample)

	var camera := page("镜头与提示")
	for entry in [["pan_speed", "镜头平移速度"], ["rotation_speed", "镜头旋转灵敏度"], ["zoom_speed", "滚轮缩放速度"]]: slider(camera, entry[0], entry[1])
	check(camera, "invert_y", "反转中键拖动的上下俯仰")
	check(camera, "route_dots", "显示角色行走路线点")
	check(camera, "perspective", "立体战术视角（关闭后使用原俯视效果）")
	check(camera, "impact_motion", "大型恐龙重击时轻微镜头震动")
	camera.add_child(hud.label("默认跟随角色；手动平移可查看地图，归位键恢复持续跟随。", 14, Color("a6b59e")))
	var keys := page("键位")
	keys.add_child(hud.label("点击键位后按新键。重复键位会提示冲突；Esc 取消录入。", 14))
	keys.add_child(hud.label("鼠标、Esc、方向键和组合键保留；使用字母、数字、功能键或空格等单键。", 13, Color("a6b59e")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	keys.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 7)
	scroll.add_child(grid)
	for action in Preferences.ACTIONS:
		var title: Label = hud.label(Preferences.ACTIONS[action][0], 14)
		title.custom_minimum_size.x = 190
		grid.add_child(title)
		var b: Button = hud.button("")
		b.custom_minimum_size = Vector2(105, 34)
		b.pressed.connect(listen.bind(action))
		key_buttons[action] = b
		grid.add_child(b)
	var audio := page("声音")
	hud.sound_panel.reparent(audio)
	hud.sound_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.sound_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.sound_panel.show()
	message = hud.label("", 14, Color("dfc693"))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 38
	column.add_child(message)
	countdown = hud.label("", 14, Color("efb795"))
	column.add_child(countdown)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var reset: Button = hud.button("恢复默认（应用后生效）")
	reset.pressed.connect(reset_draft)
	actions.add_child(reset)
	apply_button = hud.button("应用并保存")
	apply_button.pressed.connect(apply_draft)
	actions.add_child(apply_button)
	keep_button = hud.button("保留显示设置")
	keep_button.pressed.connect(confirm_preview)
	actions.add_child(keep_button)
	undo_button = hud.button("还原")
	undo_button.pressed.connect(rollback)
	actions.add_child(undo_button)
	var close_button: Button = hud.button("关闭  Esc")
	close_button.pressed.connect(close)
	actions.add_child(close_button)
	panel.hide()

func page(title: String) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.name = title
	container.add_theme_constant_override("separation", 18)
	tabs.add_child(container)
	return container

func option(parent: Node, key: String, title: String, labels: Array, values: Array = []) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label: Label = hud.label(title, 16)
	label.custom_minimum_size.x = 180
	row.add_child(label)
	var choice := OptionButton.new()
	choice.add_theme_font_size_override("font_size", 16)
	choice.custom_minimum_size = Vector2(450, 38)
	for i in range(labels.size()): choice.add_item(labels[i], i if values.is_empty() else values[i])
	choice.item_selected.connect(func(index):
		if not syncing: draft[key] = choice.get_item_id(index))
	controls[key] = choice
	row.add_child(choice)

func check(parent: Node, key: String, title: String) -> void:
	var box := CheckBox.new()
	box.text = title
	box.add_theme_font_size_override("font_size", 16)
	box.toggled.connect(func(value):
		if not syncing: draft[key] = value)
	controls[key] = box
	parent.add_child(box)

func slider(parent: Node, key: String, title: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label: Label = hud.label(title, 16)
	label.custom_minimum_size.x = 180
	row.add_child(label)
	var scale := HSlider.new()
	scale.min_value = 0.5
	scale.max_value = 2.0
	scale.step = 0.05
	scale.custom_minimum_size = Vector2(350, 32)
	var amount: Label = hud.label("", 16)
	scale.value_changed.connect(func(value):
		amount.text = "  %.2f×" % value
		if not syncing: draft[key] = value)
	controls[key] = scale
	row.add_child(scale)
	row.add_child(amount)

func open() -> void:
	if panel.visible: return
	if hud.kill_stats.panel.visible: hud.kill_stats.close()
	if hud.expedition_panel.panel.visible: hud.expedition_panel.close()
	if hud.guide_panel.panel.visible: hud.guide_panel.close()
	if hud.tech_panel.visible: hud.close_tech()
	if hud.load_panel.visible: hud.close_load()
	was_paused = world.paused
	world.paused = true
	world.camera_rig.dragging = false
	hud.sound_panel.show()
	baseline = world.preferences.values.duplicate()
	baseline_keys = world.preferences.bindings.duplicate()
	draft = baseline.duplicate()
	draft_keys = baseline_keys.duplicate()
	preview = false
	listening = ""
	message.text = world.preferences.diagnostic
	panel.show()
	sync()

func sync() -> void:
	syncing = true
	for key in controls:
		var control: Control = controls[key]
		if control is OptionButton:
			control.select(control.get_item_index(draft[key]))
			control.disabled = preview
		elif control is CheckBox:
			control.set_pressed_no_signal(draft[key])
			control.disabled = preview
		elif control is HSlider:
			control.editable = not preview
			control.value = draft[key]
			control.value_changed.emit(control.value)
	for action in key_buttons:
		key_buttons[action].disabled = preview
		key_buttons[action].text = "请按新键…" if action == listening else ("空格" if draft_keys[action] == KEY_SPACE else OS.get_keycode_string(draft_keys[action]))
	keep_button.visible = preview
	undo_button.visible = preview
	apply_button.disabled = preview or not listening.is_empty()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE if preview else Control.MOUSE_FILTER_STOP
	syncing = false

func listen(action: String) -> void:
	if preview: return
	listening = action
	message.text = "为“%s”指定按键；Esc 取消。" % Preferences.ACTIONS[action][0]
	sync()

func handle(event: InputEvent) -> bool:
	if not panel.visible or not event is InputEventKey: return false
	if not event.pressed or event.echo: return not listening.is_empty()
	if event.keycode == KEY_ESCAPE:
		if not listening.is_empty():
			listening = ""
			message.text = "已取消按键录入。"
			sync()
		else: close()
		return true
	if listening.is_empty(): return false
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed or not Preferences.valid_key(code):
		message.text = "这个按键已保留或不是受支持的单键，请换一个。"
		return true
	for action in draft_keys:
		if action != listening and draft_keys[action] == code:
			message.text = "与“%s”冲突；请先修改该功能，或选择其他按键。" % Preferences.ACTIONS[action][0]
			return true
	draft_keys[listening] = code
	listening = ""
	message.text = "键位已修改，点击应用并保存后生效。"
	sync()
	return true

func reset_draft() -> void:
	if preview: return
	draft = Preferences.DEFAULTS.duplicate()
	draft_keys = Preferences.default_bindings()
	listening = ""
	message.text = "已载入默认画面、镜头和键位；尚未应用。"
	sync()

func apply_draft() -> void:
	if preview or not listening.is_empty(): return
	if not Preferences.valid_bindings(draft_keys):
		message.text = "键位无效或存在冲突，请恢复默认后重试。"
		return
	world.preferences.values = Preferences.clean_values(draft)
	world.preferences.bindings = draft_keys.duplicate()
	world.preferences.apply(world)
	if draft.fullscreen != baseline.fullscreen:
		preview = true
		preview_deadline = Time.get_ticks_msec() + 15000
		message.text = "请确认画面可见。未确认、关闭或倒计时结束都会还原本次更改。"
		sync()
	else: commit()

func commit() -> void:
	var error: String = world.preferences.save_file()
	if not error.is_empty():
		rollback()
		message.text = error
		return
	baseline = world.preferences.values.duplicate()
	baseline_keys = world.preferences.bindings.duplicate()
	draft = baseline.duplicate()
	draft_keys = baseline_keys.duplicate()
	preview = false
	message.text = "设置已保存。"
	world.preferences.diagnostic = ""
	hud.refresh_key_hints()
	sync()

func confirm_preview() -> void:
	if preview: commit()

func rollback() -> void:
	world.preferences.values = baseline.duplicate()
	world.preferences.bindings = baseline_keys.duplicate()
	world.preferences.apply(world)
	draft = baseline.duplicate()
	draft_keys = baseline_keys.duplicate()
	preview = false
	message.text = "已还原应用前的设置。"
	hud.refresh_key_hints()
	sync()

func update() -> void:
	if not panel.visible: return
	if preview:
		var left := preview_deadline - Time.get_ticks_msec()
		countdown.text = "%d 秒内确认，否则自动还原" % ceili(left / 1000.0)
		if left <= 0: rollback()
	else: countdown.text = ""

func close() -> void:
	if preview: rollback()
	listening = ""
	panel.hide()
	world.paused = was_paused
