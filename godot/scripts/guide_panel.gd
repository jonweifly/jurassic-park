extends RefCounted
const Guide = preload("res://scripts/survival_guide.gd")
var hud: Node
var world: Node
var guide: RefCounted
var panel: PanelContainer
var pages: TabContainer
var current_text: RichTextLabel
var controls_text: RichTextLabel
var action_button: Button
var was_paused := false
var step := {}

func _init(owner: Node) -> void:
	hud = owner
	world = hud.world
	guide = Guide.new(world)
	panel = hud.panel()
	panel.add_theme_font_override("font", hud.font)
	hud.root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -310
	panel.offset_bottom = 310
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(hud.label("生存手册", 26, Color("d8c38d")))
	pages = TabContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pages)
	current_text = text_page("当前目标")
	controls_text = text_page("操作速查")
	text_page("生存知识").text = guide.knowledge()
	action_button = hud.button("")
	action_button.pressed.connect(execute)
	column.add_child(action_button)
	var close_button: Button = hud.button("返回  Esc")
	close_button.pressed.connect(close)
	column.add_child(close_button)
	panel.hide()

func text_page(title: String) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.name = title
	text.add_theme_font_override("normal_font", hud.font)
	text.add_theme_font_size_override("normal_font_size", 17)
	pages.add_child(text)
	return text

func open() -> void:
	if panel.visible: close(); return
	if hud.kill_stats.panel.visible: hud.kill_stats.close()
	if hud.preferences_panel.panel.visible: hud.preferences_panel.close()
	if hud.expedition_panel.panel.visible: hud.expedition_panel.close()
	if hud.tech_panel.visible: hud.close_tech()
	if hud.load_panel.visible: hud.close_load()
	was_paused = world.paused
	world.paused = true
	world.camera_rig.dragging = false
	hud.sound_panel.hide()
	panel.show()
	refresh()

func refresh() -> void:
	step = guide.current()
	current_text.text = step.title + "\n\n" + step.text
	if world.started:
		current_text.text += "\n\n当前库存：%d 木 / %d 金\n携带：%d / %d（未返送部分不计入库存）\n电力：需求 %d / 供给 %d" % [world.session.wood, world.session.gold, world.worker.cargo, world.worker.capacity(), world.session.demand(), world.session.supply()]
	controls_text.text = "鼠标\n右键下令；左键选择或放置；中键拖动旋转，Shift + 中键平移，滚轮缩放。Esc 取消放置 / 关闭面板 / 暂停。方向键始终可平移镜头。\n\n键盘控制镜头，不直接控制角色行走。以下按键随你的设置同步：\n\n"
	for action in world.preferences.ACTIONS:
		controls_text.text += "%s    %s\n" % [world.preferences.key_name(action), world.preferences.ACTIONS[action][0]]
	action_button.visible = not step.action.is_empty()
	action_button.text = step.button
	action_button.disabled = false
	action_button.tooltip_text = ""
	if step.action == "build":
		var reason: String = world.session.can_afford(step.kind)
		action_button.disabled = not reason.is_empty()
		action_button.tooltip_text = reason

func execute() -> void:
	refresh()
	if step.action.is_empty() or action_button.disabled: return
	var action := step.duplicate()
	close()
	# User explicitly selects a gameplay action; return from any prior pause to carry it out.
	world.paused = false
	match action.action:
		"build": world.select_build(action.kind)
		"resume": world.command(world.board.point(world.session.building(action.id).cell))
		"upgrade":
			world.selected_id = action.id
			world.research()
		"tech": hud.open_tech()
		"evacuate": world.command(world.extraction)

func close() -> void:
	panel.hide()
	world.paused = was_paused
