extends RefCounted
const Catalog = preload("res://scripts/outfitting_catalog.gd")
var hud: Node
var world: Node
var panel: PanelContainer
var tabs: TabContainer
var inventory: Label
var stock: Label
var status: Label
var workshop_select: OptionButton
var job_label: Label
var saw_button: Button
var collect_button: Button
var close_button: Button
var buttons := {}
var item_art := {}
var gear_icons := {}
var gear_labels := {}
var site_labels := {}
var site_buttons := {}
var was_paused := false
var workshop_id := -1

func _init(owner_hud: Node) -> void:
	hud = owner_hud
	world = hud.world
	panel = hud.panel()
	hud.root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -450
	panel.offset_right = 450
	panel.offset_top = -330
	panel.offset_bottom = 330
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(hud.label("野外行动 · 装备与补给", 25, Color("dfc691")))
	stock = hud.label("", 14)
	column.add_child(stock)
	var equipped := HBoxContainer.new()
	equipped.add_theme_constant_override("separation", 8)
	column.add_child(equipped)
	for slot in ["boots", "vest", "rifle"]:
		var gear_card: PanelContainer = hud.panel(Color("152920"))
		gear_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gear_card.custom_minimum_size.y = 62
		equipped.add_child(gear_card)
		var gear_row := HBoxContainer.new()
		gear_row.add_theme_constant_override("separation", 8)
		gear_card.add_child(gear_row)
		var picture := TextureRect.new()
		picture.custom_minimum_size = Vector2(48, 48)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gear_row.add_child(picture)
		gear_icons[slot] = picture
		var caption := VBoxContainer.new()
		caption.add_theme_constant_override("separation", 1)
		gear_row.add_child(caption)
		caption.add_child(hud.label({"boots":"鞋子", "vest":"护甲", "rifle":"武器"}[slot], 11, Color("96b4a7")))
		var name_label: Label = hud.label("", 14, Color("e4c184"))
		caption.add_child(name_label)
		gear_labels[slot] = name_label
	inventory = hud.label("", 12, Color("bcd3bd"))
	column.add_child(inventory)
	saw_button = hud.button("电锯开路")
	saw_button.pressed.connect(submit.bind("saw"))
	column.add_child(saw_button)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	var workshop := page("装备工坊")
	var line := HBoxContainer.new()
	workshop.add_child(line)
	workshop_select = OptionButton.new()
	workshop_select.custom_minimum_size = Vector2(260, 34)
	workshop_select.item_selected.connect(func(index): workshop_id = workshop_select.get_item_id(index); refresh())
	line.add_child(workshop_select)
	collect_button = hud.icon_button("前往领取", "collect")
	collect_button.pressed.connect(submit.bind("collect"))
	line.add_child(collect_button)
	job_label = hud.label("", 14, Color("dec68f"))
	job_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	workshop.add_child(job_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workshop.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for item in Catalog.ITEMS:
		var spec: Dictionary = Catalog.ITEMS[item]
		var card: PanelContainer = hud.panel(Color("152920"))
		card.custom_minimum_size.y = 78
		list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var picture := TextureRect.new()
		picture.texture = load("res://assets/ui/items/%s.svg" % item)
		item_art[item] = picture.texture
		picture.custom_minimum_size = Vector2(58, 58)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(picture)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 2)
		row.add_child(copy)
		copy.add_child(hud.label(spec.name + ("  ·  机械工程" if item == "repair_bot" else "  ·  高级改良" if spec.rank == 2 else "  ·  基础制作"), 15, Color("e4c184")))
		copy.add_child(hud.label("木 %d   /   金 %d   /   %.0f 秒" % [spec.wood, spec.gold, spec.time], 12, Color("9fc4ab")))
		var description: Label = hud.label(spec.description, 12, Color("c0d0bd"))
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.add_child(description)
		var button: Button = hud.icon_button("制作", "workshop")
		button.custom_minimum_size = Vector2(106, 52)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(submit.bind("craft", item))
		row.add_child(button)
		buttons[item] = button
	item_art["vest_empty"] = load("res://assets/ui/items/vest_empty.svg")
	workshop.add_child(hud.label("领取后自动装备；高级款替换基础款。断电暂停制作，工坊被毁会损失待领物品。", 12, Color("9aae9d")))
	var field := page("探索路线")
	field.add_child(hud.label("坐标来自园区地图，现场仍有未知危险。重要物资与图纸需要带回帐篷。", 14))
	for id in Catalog.SITES:
		var card: PanelContainer = hud.panel(Color("152920"))
		field.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var text: Label = hud.label("", 14)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 520
		row.add_child(text)
		site_labels[id] = text
		var button: Button = hud.icon_button("前往搜寻", "explore")
		button.pressed.connect(submit.bind("explore", id))
		row.add_child(button)
		site_buttons[id] = button
	var return_button: Button = hud.icon_button("返回帐篷 · 自动结算携带物资", "return")
	return_button.pressed.connect(submit.bind("return"))
	field.add_child(return_button)
	status = hud.label("", 13, Color("e0c38e"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 40
	column.add_child(status)
	close_button = hud.button("关闭")
	close_button.pressed.connect(close)
	column.add_child(close_button)
	panel.hide()

func page(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = title
	box.add_theme_constant_override("separation", 12)
	tabs.add_child(box)
	return box

func open(tab: int = 0) -> void:
	if not world.started or world.session.phase not in ["playing", "evacuate"] or panel.visible: return
	if hud.kill_stats.panel.visible: hud.kill_stats.close()
	if hud.preferences_panel.panel.visible: hud.preferences_panel.close()
	if hud.guide_panel.panel.visible: hud.guide_panel.close()
	if hud.tech_panel.visible: hud.close_tech()
	if hud.expedition_panel.panel.visible: hud.expedition_panel.close()
	was_paused = world.paused
	world.paused = true
	world.camera_rig.dragging = false
	var b: Dictionary = world.selected_building()
	if not b.is_empty() and b.kind == "workshop": workshop_id = b.id
	workshop_select.clear()
	for building in world.session.buildings:
		if building.hp > 0 and building.kind == "workshop": workshop_select.add_item("装备工坊 #%d%s" % [building.id, " · 施工中" if building.remaining > 0 else ""], building.id)
	if workshop_select.item_count == 0:
		workshop_select.add_item("尚无工坊 · 升级基础建筑", -1)
		workshop_id = -1
	elif workshop_select.get_item_index(workshop_id) < 0: workshop_id = workshop_select.get_item_id(0)
	workshop_select.select(maxi(0, workshop_select.get_item_index(workshop_id)))
	tabs.current_tab = tab
	refresh()
	panel.show()

func close() -> void:
	if not panel.visible: return
	panel.hide()
	world.paused = was_paused

func submit(action: String, item: String = "") -> void:
	close()
	# Choosing an action explicitly resumes this local panel; room pause is still authoritative.
	world.paused = false
	world.outfit_action(action, workshop_id, item)

func refresh() -> void:
	close_button.text = "关闭  Esc / " + world.preferences.key_name("journal")
	var gear: RefCounted = world.outfitting
	var state: Dictionary = gear.actor()
	stock.text = "库存  %d 木 / %d 金     电力 %d / %d     制作与搜寻随游戏时间推进" % [world.session.wood, world.session.gold, world.session.demand(), world.session.supply()]
	gear_labels["boots"].text = ["普通鞋", "探险靴 +10%", "越野靴 +15%"][state.boots]
	gear_labels["vest"].text = ["无护甲", "防护背心 -15%", "强化背心 -25%"][state.vest]
	gear_labels["rifle"].text = ["原装步枪", "改良步枪 +25%", "精校步枪 +50%"][state.rifle]
	gear_icons["boots"].texture = item_art["boots_2" if state.boots == 2 else "boots"]
	gear_icons["vest"].texture = item_art["vest_2" if state.vest == 2 else "vest" if state.vest == 1 else "vest_empty"]
	gear_icons["rifle"].texture = item_art["rifle_2" if state.rifle == 2 else "rifle"]
	inventory.text = "急救包 %d / 3（%s）%s" % [state.kits, world.preferences.key_name("kit"), " · 冷却 %.0f 秒" % ceilf(state.cooldown) if state.cooldown > 0 else ""]
	saw_button.visible = state.chainsaw > 0
	saw_button.text = "当前：电锯开路 · 点击切回采木" if state.saw_enabled else "当前：普通采木 · 点击使用电锯"
	inventory.text += " · 维修机器人 %d / 3" % gear.data().robots.size()
	var job: Dictionary = gear.data().jobs.get(str(workshop_id), {})
	job_label.text = "工坊空闲 · 基础装备直接制作；高级改良需图纸，机器人需「机械工程」"
	if workshop_id < 0: job_label.text = "先建基础建筑，选中后选择「升级工坊」。工坊与实验室可分别建造。"
	if not job.is_empty(): job_label.text = "%s：%s%s" % [Catalog.ITEMS[job.item].name, "制作剩余 %.0f 秒" % ceilf(job.remaining) if job.remaining > 0 else ("制作完成 · 自动部署" if job.item == "repair_bot" else "制作完成 · 待领取"), " · 断电暂停" if world.session.supply() < world.session.demand() and job.remaining > 0 else ""]
	collect_button.disabled = job.get("item", "") == "repair_bot" or job.is_empty() or job.get("remaining", 1.0) > 0 or job.get("owner", "") != gear.owner_slot() or (job.get("item", "") == "medkit" and state.kits >= 3)
	for item in buttons:
		var error: String = gear.craft_error(workshop_id, item)
		buttons[item].disabled = not error.is_empty()
		buttons[item].tooltip_text = error if not error.is_empty() else "扣除材料开始制作；制作完成后前往工坊领取。"
		buttons[item].text = "已装备" if Catalog.ITEMS[item].rank > 0 and state[Catalog.ITEMS[item].slot] >= Catalog.ITEMS[item].rank else ("未解锁" if not Catalog.ITEMS[item].blueprint.is_empty() and (Catalog.ITEMS[item].blueprint not in gear.data().blueprints or not world.session.technologies.has("field_equipment")) else "制作")
	for id in site_labels:
		var site: Dictionary = gear.data().sites.get(id, {})
		var spec: Dictionary = Catalog.SITES[id]
		var distance: float = world.hero.position.distance_to(world.board.point(site.cell)) if not site.is_empty() else 0.0
		site_labels[id].text = "%s · 直线 %.0f 米\n%s\n%s" % [spec.name, distance, spec.description, {"known":"可搜寻", "carried":"已取走 · 等待返营", "completed":"已结算"}.get(site.get("status", ""), "尚无坐标")]
		site_buttons[id].disabled = site.is_empty() or site.status != "known" or world.session.phase != "playing"
	status.text = gear.brief() + "\n" + ("高级图纸已入库：" + "、".join(gear.data().blueprints.map(func(id): return Catalog.SITES[id].name)) if not gear.data().blueprints.is_empty() else "基础款就能支持第一次短途探索；也可以先完善营地防线。")
