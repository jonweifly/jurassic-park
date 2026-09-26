extends RefCounted
const Dinosaurs = preload("res://scripts/dinosaur_catalog.gd")
var hud: Node
var world: Node
var panel: PanelContainer
var total_label: Label
var counts: Dictionary = {}
var legacy_name: Label
var legacy_count: Label
var close_button: Button
var list_view: ScrollContainer
var was_paused := false

func _init(owner: Node) -> void:
	hud = owner
	world = hud.world
	panel = hud.panel()
	hud.root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -270
	panel.offset_bottom = 270
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(hud.label("本局恐龙击杀", 25, Color("dbc690")))
	total_label = hud.label("", 20, Color("e7dcae"))
	column.add_child(total_label)
	column.add_child(hud.label("包含幸存者与防御设施的击杀", 13, Color("a6b59e")))
	list_view = ScrollContainer.new()
	list_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(list_view)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_right", 12)
	list_view.add_child(inset)
	var rows := GridContainer.new()
	rows.columns = 2
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("h_separation", 24)
	rows.add_theme_constant_override("v_separation", 8)
	inset.add_child(rows)
	var name_header: Label = hud.label("恐龙种类", 13, Color("a6b59e"))
	name_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(name_header)
	var count_header: Label = hud.label("击杀数量", 13, Color("a6b59e"))
	count_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(count_header)
	for species in Dinosaurs.SPECIES:
		var name_label: Label = hud.label(Dinosaurs.spec(species).name, 16)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(name_label)
		var count: Label = hud.label("0", 17)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		counts[species] = count
		rows.add_child(count)
	legacy_name = hud.label("旧记录（未分类）", 15, Color("a6b59e"))
	legacy_name.tooltip_text = "旧存档未记录物种明细；继续游戏后的新击杀会按物种累计。"
	rows.add_child(legacy_name)
	legacy_count = hud.label("0", 17, Color("a6b59e"))
	legacy_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(legacy_count)
	column.add_child(hud.label("查看时暂停；关闭后恢复之前的状态。", 13, Color("a6b59e")))
	close_button = hud.button("返回  Esc")
	close_button.pressed.connect(close)
	column.add_child(close_button)
	panel.hide()

func open() -> void:
	if not world.started or hud.confirmation.visible: return
	if panel.visible: return
	if hud.preferences_panel.panel.visible: hud.preferences_panel.close()
	if hud.guide_panel.panel.visible: hud.guide_panel.close()
	if hud.expedition_panel.panel.visible: hud.expedition_panel.close()
	if hud.tech_panel.visible: hud.close_tech()
	if hud.load_panel.visible: hud.close_load()
	was_paused = world.paused
	world.paused = true
	world.camera_rig.dragging = false
	hud.sound_panel.hide()
	refresh()
	panel.show()

func refresh() -> void:
	total_label.text = "累计击杀  %d" % world.session.kills
	for species in counts:
		var amount: int = world.session.kills_by_species.get(species, 0)
		counts[species].text = str(amount)
		counts[species].modulate = Color.WHITE if amount > 0 else Color("879d85")
	var unknown: int = world.session.unclassified_kills()
	legacy_name.visible = unknown > 0
	legacy_count.visible = unknown > 0
	legacy_count.text = str(unknown)

func close() -> void:
	if not panel.visible: return
	panel.hide()
	world.paused = was_paused
