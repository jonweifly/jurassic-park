extends CanvasLayer
## Small native HUD for the art sample; values reflect the sample's controls.
const AMBER := Color("d8b879")
const WHITE := Color("e5ebe6")
const MUTED := Color("a8b8b2")
var stage: Node3D
var controls := {}
var canvas: Control
var power_status: Label
var gate_status: Label
var weather_status: Label
var message: Label
var message_left := 0.0
var view_buttons: Array[Button] = []

func _init(sample: Node3D = null) -> void:
	stage = sample

func _ready() -> void:
	name = "CinematicHUD"
	layer = 10
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next", "PingFang SC", "Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 14
	canvas.theme = theme
	var gradient := Gradient.new()
	gradient.set_color(0,Color(.012,.025,.023,.85))
	gradient.set_color(1,Color(.012,.025,.023,0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0,0)
	texture.fill_to = Vector2(0,1)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shade.offset_bottom = 170
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(shade)
	var header := HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 34
	header.offset_right = -34
	header.offset_top = 26
	header.add_theme_constant_override("separation",14)
	canvas.add_child(header)
	var mark := Label.new()
	mark.text = "◈"
	mark.add_theme_font_size_override("font_size",40)
	mark.add_theme_color_override("font_color",AMBER)
	header.add_child(mark)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation",0)
	header.add_child(titles)
	label(titles,"JURASSIC  /  FIELD STATION",21,WHITE)
	label(titles,"雨林检修站     ·     01 电影写实样板",13,MUTED)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var meta := VBoxContainer.new()
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(meta)
	weather_status = label(meta,"雨后黄昏  /  17:40",15,WHITE)
	weather_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var sector := label(meta,"独立美术样板 · 尚未接入人物与建造",11,MUTED)
	sector.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var rule := ColorRect.new()
	rule.color = Color(0.8,0.88,0.83,.17)
	rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rule.offset_left = 34
	rule.offset_right = -34
	rule.offset_top = 94
	rule.offset_bottom = 95
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(rule)
	var back := button(canvas,"返回主菜单",stage.return_to_menu)
	back.name = "ReturnToMenu"
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -168
	back.offset_right = -34
	back.offset_top = 110
	back.offset_bottom = 145
	var panel := PanelContainer.new()
	panel.name = "StationControls"
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 34
	panel.offset_right = 312
	panel.offset_top = -249
	panel.offset_bottom = -74
	panel.add_theme_stylebox_override("panel",panel_style())
	canvas.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation",10)
	panel.add_child(v)
	label(v,"B–07   /   围栏控制",16,WHITE)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation",20)
	v.add_child(stats)
	power_status = label(stats,"● 供电正常",13,AMBER)
	gate_status = label(stats,"电门已关闭",13,MUTED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	v.add_child(row)
	controls.gate = button(row,"G  开启电门",stage.toggle_gate)
	controls.power = button(row,"P  切断电源",stage.toggle_power)
	label(v,"可操作：电门、供电、天气与镜头",11,MUTED)
	var views := HBoxContainer.new()
	views.name = "ViewControls"
	views.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	views.offset_left = -607
	views.offset_right = -34
	views.offset_top = -114
	views.offset_bottom = -74
	views.add_theme_constant_override("separation",8)
	canvas.add_child(views)
	for i in range(3):
		var index := i
		var b := button(views,["1  俯视","2  恐龙","3  氛围"][i],func(): stage.set_view(index))
		b.toggle_mode = true
		view_buttons.append(b)
	controls.weather = button(views,"N  雨夜",stage.toggle_weather)
	controls.audio = button(views,"M  声音关",stage.toggle_audio)
	var footer := HBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 34
	footer.offset_right = -34
	footer.offset_top = -48
	footer.offset_bottom = -24
	canvas.add_child(footer)
	label(footer,"中键拖动  旋转     滚轮  缩放     WASD  平移     Home  归位",12,MUTED)
	var blank := Control.new()
	blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(blank)
	label(footer,"Tab  隐藏界面     Esc  暂停",12,MUTED)
	message = Label.new()
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message.offset_left = -350
	message.offset_right = 350
	message.offset_top = 113
	message.offset_bottom = 150
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_color",AMBER)
	message.add_theme_font_size_override("font_size",15)
	canvas.add_child(message)
	refresh()

func panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(.025,.047,.043,.91)
	s.border_color = Color(.57,.66,.60,.32)
	s.set_border_width_all(1)
	s.border_width_top = 2
	s.content_margin_left = 17
	s.content_margin_right = 17
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	s.set_corner_radius_all(3)
	return s

func label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

func button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0,35)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size",13)
	b.add_theme_color_override("font_color",WHITE)
	b.add_theme_color_override("font_hover_color",AMBER)
	var normal := panel_style()
	normal.bg_color = Color(.045,.075,.068,.93)
	normal.border_width_top = 1
	normal.content_margin_left = 11
	normal.content_margin_right = 11
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var hover := normal.duplicate()
	hover.border_color = AMBER
	hover.bg_color = Color(.11,.14,.11,.97)
	b.add_theme_stylebox_override("normal",normal)
	b.add_theme_stylebox_override("hover",hover)
	b.add_theme_stylebox_override("pressed",hover)
	b.add_theme_stylebox_override("disabled",normal)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func refresh() -> void:
	if not is_instance_valid(power_status): return
	power_status.text = "● 供电正常" if stage.powered else "● 供电中断"
	power_status.modulate = Color.WHITE if stage.powered else Color("df8975")
	gate_status.text = "电门已开启" if stage.gate_amount > .99 else ("电门已关闭" if stage.gate_amount < .01 else ("电门已停止" if not stage.powered or stage.paused else "电门移动中"))
	controls.gate.text = "G  关闭电门" if stage.gate_open else "G  开启电门"
	controls.gate.disabled = not stage.powered
	controls.power.text = "P  切断电源" if stage.powered else "P  恢复供电"
	controls.weather.text = "N  黄昏" if stage.night else "N  雨夜"
	controls.audio.text = "M  声音开" if stage.audio_on else "M  声音关"
	weather_status.text = "热带雨夜  /  21:10" if stage.night else "雨后黄昏  /  17:40"
	for i in range(view_buttons.size()): view_buttons[i].set_pressed_no_signal(stage.view_index == i)

func notify(text: String) -> void:
	message.text = text
	message_left = 3.2

func _process(dt: float) -> void:
	message_left = maxf(0,message_left-dt)
	message.modulate.a = clampf(message_left,0,1)
