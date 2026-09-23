extends RefCounted
const Features = preload("res://scripts/feature_policy.gd")
const Catalog = preload("res://scripts/expedition_catalog.gd")
var hud: Node
var world: Node
var panel: PanelContainer
var tabs: TabContainer
var selected := ""
var was_paused := false
var summary: Label
var detail: RichTextLabel
var site_buttons: Dictionary = {}
var choice_buttons: Array[Button] = []
var event_buttons: Array[Button] = []
var event_text: Label
var history: RichTextLabel
var go_button: Button
var return_button: Button
var message: Label
var previous_history := ""
var close_button: Button
var contract_status: Label
var contract_details: Array[Label] = []
var contract_buttons: Array[Button] = []
var contract_next: Button
var contract_return: Button
var route_cache := ""
var route_text := ""

func _init(owner_hud: Node) -> void:
	hud = owner_hud
	world = hud.world
	panel = hud.panel()
	panel.add_theme_font_override("font", hud.font)
	hud.root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -430
	panel.offset_right = 430
	panel.offset_top = -355
	panel.offset_bottom = 355
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(hud.label("岛屿探索日志", 26, Color("d8c38d")))
	summary = hud.label("", 14)
	column.add_child(summary)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(830, 440)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	var places := HBoxContainer.new()
	places.name = "地点调查"
	places.add_theme_constant_override("separation", 16)
	tabs.add_child(places)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 225
	places.add_child(list)
	for id in Catalog.SITE_ORDER:
		var b: Button = hud.button("")
		b.custom_minimum_size.y = 51
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(select_site.bind(id))
		site_buttons[id] = b
		list.add_child(b)
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = 580
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	places.add_child(body)
	detail = RichTextLabel.new()
	detail.add_theme_font_override("normal_font", hud.font)
	detail.add_theme_font_size_override("normal_font_size", 16)
	detail.custom_minimum_size = Vector2(560, 240)
	body.add_child(detail)
	for index in range(2):
		var b: Button = hud.button("")
		b.custom_minimum_size.y = 40
		b.pressed.connect(start_choice.bind(index))
		choice_buttons.append(b)
		body.add_child(b)
	go_button = hud.button("前往调查")
	go_button.pressed.connect(go_to_site)
	body.add_child(go_button)
	return_button = hud.button("带资料返回帐篷")
	return_button.pressed.connect(return_to_camp)
	body.add_child(return_button)
	var radio := VBoxContainer.new()
	radio.name = "无线电"
	radio.add_theme_constant_override("separation", 16)
	tabs.add_child(radio)
	event_text = hud.label("", 18)
	event_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_text.custom_minimum_size = Vector2(790, 190)
	radio.add_child(event_text)
	for index in range(2):
		var b: Button = hud.button("")
		b.custom_minimum_size.y = 48
		b.pressed.connect(choose_event.bind(index))
		event_buttons.append(b)
		radio.add_child(b)
	radio.add_child(hud.label("消息过期视为忽略，不扣资源。面板打开时游戏暂停。", 14))
	make_contracts()
	var records := VBoxContainer.new()
	records.name = "记录与提示"
	tabs.add_child(records)
	history = RichTextLabel.new()
	history.add_theme_font_override("normal_font", hud.font)
	history.add_theme_font_size_override("normal_font_size", 16)
	history.custom_minimum_size = Vector2(790, 420)
	history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	records.add_child(history)
	message = hud.label("", 14, Color("e1c58f"))
	message.custom_minimum_size.y = 24
	column.add_child(message)
	close_button = hud.button("返回营地  Esc / L")
	close_button.pressed.connect(close)
	column.add_child(close_button)
	panel.hide()

func open(id: String = "") -> void:
	if not Features.peripheral_enabled: return
	if not world.started: return
	if panel.visible and id.is_empty():
		close()
		return
	if hud.tech_panel.visible: hud.close_tech()
	if hud.load_panel.visible: hud.close_load()
	if hud.preferences_panel.panel.visible: hud.preferences_panel.close()
	if hud.guide_panel.panel.visible: hud.guide_panel.close()
	was_paused = world.paused
	world.paused = true
	world.build_mode = ""
	hud.sound_panel.hide()
	route_cache = ""
	panel.show()
	message.text = ""
	if not id.is_empty():
		selected = id
		tabs.current_tab = 0
	elif not world.adventure.data().get("offer", "").is_empty(): tabs.current_tab = 1
	refresh()

func close() -> void:
	panel.hide()
	world.paused = was_paused

func select_site(id: String) -> void:
	selected = id
	route_cache = ""
	message.text = ""
	refresh()

func refresh() -> void:
	close_button.text = "返回营地  Esc / " + world.preferences.key_name("journal")
	var state: Dictionary = world.adventure.data()
	if state.is_empty(): return
	var statuses := {"hidden": "未知", "known": "已获坐标", "discovered": "可调查", "carried": "待返送", "completed": "已完成"}
	summary.text = "木材 %d  /  黄金 %d   ·   调查 %d / 6   ·   急救包 %d（%s 使用）" % [world.session.wood, world.session.gold, state.records.size(), state.kits, world.preferences.key_name("kit")]
	for id in site_buttons:
		var site: Dictionary = state.sites.get(id, {})
		var known: bool = not site.is_empty() and site.status != "hidden"
		site_buttons[id].text = (Catalog.SITES[id].name + "\n" + statuses[site.status]) if known else "未知地点\n探索地图或收听无线电"
		site_buttons[id].disabled = not known
		site_buttons[id].modulate = Color("e6cb89") if selected == id else Color.WHITE
	var site: Dictionary = state.sites.get(selected, {})
	var valid: bool = not site.is_empty() and site.status != "hidden"
	detail.text = "离开营地，在迷雾中寻找旧设施。\n\n获得坐标后可点击“前往调查”；抵达现场后选择方案。\n\n搜寻可直接回收物资；修复需要材料和安全环境；样本与档案必须带回帐篷。\n\n所有地点均可跳过，等待救援仍可完成本局。"
	if valid:
		var spec: Dictionary = Catalog.SITES[selected]
		var cache_key := "%s/%s/%s" % [selected, world.hero.position, world.board.revision]
		if route_cache != cache_key:
			route_cache = cache_key
			route_text = world.adventure.route_brief(selected)
		detail.text = "%s · %s\n\n%s\n\n距离 %.0f 米 · 调查 %.0f / %.0f 秒%s" % [spec.name, statuses[site.status], spec.description, world.hero.position.distance_to(world.board.point(site.cell)), site.progress, spec.seconds, "\n已投入材料；中断后可继续，不重复收费。" if site.paid and site.status == "discovered" else ""]
		detail.text += "\n\n" + route_text
		if site.status == "completed": detail.text += "\n\n" + spec.lore
	for index in range(choice_buttons.size()):
		var b := choice_buttons[index]
		b.visible = valid and site.status == "discovered" and index < Catalog.SITES[selected].choices.size()
		if b.visible:
			b.text = Catalog.SITES[selected].choices[index].name
			var error: String = world.adventure.choice_error(selected, index)
			b.disabled = not error.is_empty()
			b.tooltip_text = error
	go_button.visible = valid and site.status not in ["carried", "completed"]
	go_button.disabled = world.session.phase not in ["playing", "evacuate"]
	return_button.visible = not state.cargo.is_empty()
	return_button.disabled = world.session.phase not in ["playing", "evacuate"]
	var offer := Catalog.event(state.offer)
	var active: bool = not offer.is_empty() and world.session.phase == "playing"
	event_text.text = "频道暂时安静。\n\n无线电消息会提供资源取舍和探索线索，不会自动改变营地状态。" if not active else "%s\n\n%s\n\n有效时间：%.0f 秒游戏时间" % [offer.title, offer.text, maxf(0, state.offer_until - world.session.elapsed)]
	for index in range(event_buttons.size()):
		var b := event_buttons[index]
		b.visible = active
		if active:
			b.text = offer.choices[index].name
			var error: String = world.adventure.event_error(index)
			b.disabled = not error.is_empty()
			b.tooltip_text = error
	refresh_contracts()
	var text := "生存提示\n迅猛龙：近处同伴会收到警告，并尝试从两侧接近。树林和距离可以切断追踪。\n成年霸王龙：标准模式下先蓄力再重击，橙色范围提示后及时后撤；对建筑破坏更强。\n急救包：%s 恢复 50 生命，20 秒冷却；满生命不消耗。\n\n调查记录\n" % world.preferences.key_name("kit")
	for id in state.records: text += Catalog.SITES[id].name + "\n" + Catalog.SITES[id].lore + "\n\n"
	text += "\n行动记录\n"
	for entry in state.history:
		text += "%02d:%02d  %s\n\n" % [int(entry.at) / 60, int(entry.at) % 60, entry.text]
	if previous_history != text:
		history.text = text
		previous_history = text

func start_choice(choice: int) -> void:
	var error: String = world.adventure.begin(selected, choice)
	if error.is_empty():
		close()
		world.paused = false
	else: message.text = error

func go_to_site() -> void:
	var error: String = world.adventure.go_to(selected)
	if error.is_empty():
		close()
		world.paused = false
	else: message.text = error

func return_to_camp() -> void:
	var error: String = world.adventure.return_samples()
	if error.is_empty():
		close()
		world.paused = false
	else: message.text = error

func choose_event(choice: int) -> void:
	var error: String = world.adventure.choose_event(choice)
	message.text = "已执行所选方案。" if error.is_empty() else error
	refresh()

func make_contracts() -> void:
	var page := VBoxContainer.new()
	page.name = "调查委托"
	page.add_theme_constant_override("separation", 10)
	tabs.add_child(page)
	contract_status = hud.label("", 15, Color("e1c58f"))
	contract_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(contract_status)
	page.add_child(hud.label("每局择一，可跳过且无罚款；本局撤离前完成并返营，调查仍需投入。", 14))
	for i in range(2):
		var text: Label = hud.label("", 15)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(790, 105)
		page.add_child(text)
		contract_details.append(text)
		var button: Button = hud.button("接受此委托")
		button.pressed.connect(accept_contract.bind(i))
		page.add_child(button)
		contract_buttons.append(button)
	var row := HBoxContainer.new()
	page.add_child(row)
	contract_next = hud.button("查看下一处地点")
	contract_next.pressed.connect(show_contract_site)
	row.add_child(contract_next)
	contract_return = hud.button("返回帐篷领取补给")
	contract_return.pressed.connect(func():
		var error: String = world.adventure.return_samples(false)
		if error.is_empty(): close(); world.paused = false
		else: message.text = error)
	row.add_child(contract_return)

func refresh_contracts() -> void:
	var run: Dictionary = world.adventure.contracts.data()
	contract_status.text = world.adventure.contracts.status_text()
	for i in range(2):
		var valid := not run.is_empty()
		contract_details[i].visible = valid
		contract_buttons[i].visible = valid
		if not valid: continue
		var id: String = run.offers[i]
		var spec: Dictionary = Catalog.Run.CONTRACTS[id]
		var places := []
		for site in spec.sites: places.append(Catalog.SITES[site].name + (" ✓" if world.session.adventure.records.has(site) else ""))
		contract_details[i].text = "%s\n%s\n%s\n%s" % [spec.name, " → ".join(places), spec.text, world.adventure.contracts.reward_text(id)]
		contract_buttons[i].text = ("已领取补给" if run.claimed else "已接受 · %d / 2" % world.adventure.contracts.completed_count(id)) if run.active == id else ("本局已选择另一项" if not run.active.is_empty() else "接受此委托 · 记录地点坐标")
		contract_buttons[i].disabled = not run.active.is_empty() or world.session.phase != "playing"
	var active: bool = not run.is_empty() and not run.active.is_empty() and not run.claimed
	contract_next.visible = active and world.adventure.contracts.completed_count(run.active) < 2
	contract_return.visible = active and world.adventure.contracts.completed_count(run.active) == 2
	contract_return.disabled = world.session.phase not in ["playing", "evacuate"]

func accept_contract(index: int) -> void:
	var run: Dictionary = world.adventure.contracts.data()
	if run.is_empty() or index < 0 or index >= run.offers.size(): return
	message.text = world.adventure.contracts.accept(run.offers[index])
	refresh()

func show_contract_site() -> void:
	var run: Dictionary = world.adventure.contracts.data()
	if run.is_empty() or run.active.is_empty(): return
	for id in Catalog.Run.CONTRACTS[run.active].sites:
		if not world.session.adventure.records.has(id):
			select_site(id)
			tabs.current_tab = 0
			return
