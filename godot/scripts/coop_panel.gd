extends RefCounted
var hud: CanvasLayer
var net: Node
var panel: PanelContainer
var address: LineEdit
var port: SpinBox
var password: LineEdit
var duration: OptionButton
var mode: OptionButton
var message: Label
var host_button: Button
var join_button: Button
var resume_button: Button
var close_button: Button
var room_button: Button
var revive_button: Button
var room_addresses := ""
var entry_button: Button

func _init(owner_hud: CanvasLayer, start_column: VBoxContainer) -> void:
	hud=owner_hud
	net=hud.world.coop
	net.ui=self
	var open_button: Button = hud.button("双人合作 · 创建 / 加入房间")
	entry_button=open_button
	open_button.pressed.connect(open)
	start_column.add_child(open_button)
	panel=hud.panel()
	hud.root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-260
	panel.offset_right=260
	panel.offset_top=-260
	panel.offset_bottom=260
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	panel.add_child(column)
	column.add_child(hud.label("双人合作营地",24,Color("dbc690")))
	var description: Label = hud.label("每人一个角色，共享营地、资源和科技。\n同一局域网或虚拟局域网内，通过房主地址加入。",14)
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x=480
	column.add_child(description)
	address=LineEdit.new()
	address.placeholder_text="房主 IP，例如 192.168.1.20"
	address.max_length=253
	column.add_child(address)
	var port_row := HBoxContainer.new()
	column.add_child(port_row)
	port_row.add_child(hud.label("端口",14))
	port=SpinBox.new()
	port.min_value=1024
	port.max_value=65535
	port.value=net.DEFAULT_PORT
	port.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	port_row.add_child(port)
	mode=OptionButton.new()
	mode.add_item("标准合作")
	mode.add_item("困难合作")
	port_row.add_child(mode)
	duration=OptionButton.new()
	for minutes in [25,45,60,80]: duration.add_item("%d 分钟" % minutes,minutes)
	port_row.add_child(duration)
	password=LineEdit.new()
	password.placeholder_text="房间口令（可选，双方填写一致）"
	password.secret=true
	password.max_length=64
	column.add_child(password)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	host_button=hud.button("创建房间")
	host_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	host_button.pressed.connect(func(): host(false))
	actions.add_child(host_button)
	join_button=hud.button("加入房间")
	join_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(join_room)
	actions.add_child(join_button)
	resume_button=hud.button("继续合作存档并开房")
	resume_button.pressed.connect(func(): host(true))
	column.add_child(resume_button)
	message=hud.label("",14,Color("a6b59e"))
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size=Vector2(480,110)
	column.add_child(message)
	close_button=hud.button("返回")
	close_button.pressed.connect(func():
		if net.connecting: net.close_transport()
		panel.hide())
	column.add_child(close_button)
	panel.hide()
	room_button=hud.button("")
	hud.root.add_child(room_button)
	room_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	room_button.offset_left=-205
	room_button.offset_right=205
	room_button.offset_top=8
	room_button.offset_bottom=36
	room_button.custom_minimum_size=Vector2(410,28)
	room_button.pressed.connect(open)
	room_button.hide()
	revive_button=hud.button("救起队友 · 10 金（需靠近）")
	revive_button.pressed.connect(net.revive)
	hud.root.add_child(revive_button)
	revive_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	revive_button.offset_left=-125
	revive_button.offset_right=125
	revive_button.offset_top=42
	revive_button.offset_bottom=70
	revive_button.hide()
	var leave: Button = hud.button("离开房间 / 返回菜单")
	leave.pressed.connect(func(): hud.confirm_discard("离开合作房间？房主离开会结束房间，并尝试保存合作局。",net.menu))
	hud.pause_panel.get_child(0).add_child(leave)
	leave.set_meta("coop_leave",true)
	leave.visible=false

func open() -> void:
	var addresses := PackedStringArray()
	for value in IP.get_local_addresses():
		if value.contains(":") or value.begins_with("127.") or value.begins_with("169.254."): continue
		addresses.append(value)
	room_addresses=", ".join(addresses)
	panel.show()
	panel.move_to_front()
	refresh()

func host(resume: bool) -> void:
	var result: String = net.host("hard" if mode.selected==1 else "standard",int(port.value),password.text,resume,float(duration.get_selected_id())*60.0)
	if result.is_empty(): panel.hide()
	else: net.status=result
	refresh()

func join_room() -> void:
	var result: String = net.join(address.text,int(port.value),password.text)
	if not result.is_empty(): net.status=result
	refresh()

func refresh() -> void:
	var busy: bool = net.active or net.connecting
	host_button.disabled=busy
	join_button.disabled=busy
	resume_button.disabled=busy or not FileAccess.file_exists(net.save_path)
	address.editable=not busy
	password.editable=not busy
	mode.disabled=busy
	duration.disabled=busy
	port.editable=not busy
	message.text=net.status
	if net.active and net.hosting:
		message.text+="\n房主地址："+room_addresses+"\n端口：%d（UDP）\n朋友使用相同版本；跨网络时使用虚拟局域网地址。" % net.port
	room_button.visible=net.active and not hud.pause_panel.visible and not panel.visible
	var count: int = 1+int(net.guest_peer>0) if net.hosting else 2
	room_button.text="合作 %d/2 · %s" %[count,"房间已暂停" if net.room_paused() else ("房主" if net.hosting else "队友")]
	if net.active and not net.connected: room_button.text="连接已断开 · 返回菜单重新加入"
	elif net.hosting and net.guest_peer==0: room_button.text="合作 1/2 · 等待队友 · 点击查看地址"
	room_button.tooltip_text=net.status
	var down: bool = net.active and net.pawns.values().any(func(p): return p!=hud.world.hero and p.health<=0)
	revive_button.visible=down and hud.world.hero.health>0 and not hud.world.paused and not panel.visible and hud.world.session.phase in ["playing","evacuate"]
	if net.active:
		hud.pause_panel.get_child(0).get_node("RestartGame").hide()
		hud.pause_panel.get_child(0).get_node("ExitGame").text="保存合作局并退出" if net.hosting else "离开房间并退出"
		hud.save_button.disabled=not net.hosting or hud.world.session.phase not in ["playing","evacuate"]
		hud.load_button.disabled=true
		hud.save_label.text=("合作局由房主保存，双方暂停面板会暂停整局。\n队友倒下：靠近后花费 10 金救起；全员倒下失败。\n"+hud.world.save_status if net.connected else net.status)
		if hud.world.hero.health<=0 and hud.world.session.phase!="lost": room_button.text="你已倒下 · 等待队友靠近救援"
	for child in hud.pause_panel.get_child(0).get_children():
		if child.has_meta("coop_leave"): child.visible=net.active
	if panel.visible: hud.start_panel.hide()
