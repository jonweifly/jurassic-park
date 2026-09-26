extends RefCounted
## Contextual tower commands share the existing build area; no added HUD height.
const Catalog = preload("res://scripts/catalog.gd")
const ROLES = {"range": "远程压制 · 20 米", "rapid": "入口清群 · 0.6 秒", "heavy": "破甲猎巨 · 36 伤害"}
const COLORS = {"range": Color("96c7c2"), "rapid": Color("e0bc6d"), "heavy": Color("d9987d")}
var hud: Node
var panel: VBoxContainer
var cards: HBoxContainer
var status: Label
var title: Label
var camp_button: Button
var engineering_button: Button
var completed: HBoxContainer
var completed_icon: TextureRect
var completed_text: Label
var grid: Control
var portraits: Dictionary = {}

func _init(owner_hud: Node, commands: VBoxContainer, head: HBoxContainer, heading: Label, build_grid: Control) -> void:
	hud = owner_hud
	title = heading
	grid = build_grid
	engineering_button = hud.button("箭塔工程")
	engineering_button.pressed.connect(hud.open_tech)
	engineering_button.tooltip_text = "在实验室研究箭塔工程，解锁三种箭塔升级。"
	head.add_child(engineering_button)
	camp_button = hud.button("营地建造")
	camp_button.pressed.connect(func():
		if hud.world.paused: return
		hud.world.selected_id = -1
		hud.world.build_mode = ""
		hud.refresh(0))
	head.add_child(camp_button)
	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 3)
	commands.add_child(panel)
	status = hud.label("", 12, Color("b4c1aa"))
	status.clip_text = true
	panel.add_child(status)
	cards = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 5)
	panel.add_child(cards)
	for option in ["range", "rapid", "heavy"]:
		var spec: Dictionary = Catalog.REFITS[option]
		portraits[option] = load("res://assets/ui/towers/%s.png" % option)
		var card: Button = hud.button("")
		card.custom_minimum_size = Vector2(120, 98)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(hud.world.refit_selected.bind(option))
		cards.add_child(card)
		hud.refit_buttons[option] = card
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 4
		col.offset_right = -4
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(col)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(row)
		var preview := TextureRect.new()
		preview.texture = portraits[option]
		preview.custom_minimum_size = Vector2(57, 57)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(preview)
		var name_label: Label = hud.label(spec.name + "塔", 15, COLORS[option])
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_label)
		for text in [ROLES[option], "%d 木 · %d 金 · %d 秒" % [spec.wood, spec.gold, spec.time]]:
			var line: Label = hud.label(text, 11)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(line)
	completed = HBoxContainer.new()
	completed.custom_minimum_size.y = 98
	panel.add_child(completed)
	completed_icon = TextureRect.new()
	completed_icon.custom_minimum_size = Vector2(90, 90)
	completed_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	completed_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	completed.add_child(completed_icon)
	completed_text = hud.label("", 14)
	completed_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	completed_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	completed.add_child(completed_text)

func refresh(b: Dictionary) -> void:
	var active: bool = not b.is_empty() and b.kind == "tower" and hud.world.build_mode.is_empty()
	panel.visible = active
	grid.visible = not active
	engineering_button.visible = active
	camp_button.visible = active
	camp_button.disabled = hud.world.paused
	title.text = "箭 塔 升 级" if active else "营 地 建 造"
	if not active:
		for option in ["range", "rapid", "heavy"]: hud.refit_buttons[option].hide()
		return
	var refit: String = b.get("refit", "")
	cards.visible = refit.is_empty()
	completed.visible = not refit.is_empty()
	var s = hud.world.session
	if refit.is_empty():
		var error: String = s.refit_error(b.id, "range")
		status.text = "选择一种专精 · 升级期间停火 · 选定后不可更换"
		if not s.technologies.has("tower_engineering"):
			status.text = "需实验室研究「箭塔工程」 · 点击上方查看"
		elif b.remaining > 0: status.text = "箭塔施工中 · 完工后可选择升级"
		elif s.supply() < s.demand(): status.text = error
	else:
		status.text = "专精已选定 · 改造完成后自动恢复防御"
		completed_icon.texture = portraits.get(refit)
		completed_text.text = "%s塔%s\n%s" % [Catalog.REFITS[refit].name, " · 施工剩余 %.0f 秒" % b.remaining if b.remaining > 0 else " · 已就绪", Catalog.REFITS[refit].description]
		if b.remaining <= 0: status.text = "保持供电 · 可在中部调整目标优先级和集火"
	engineering_button.text = "科技已解锁" if s.technologies.has("tower_engineering") else "箭塔工程"
