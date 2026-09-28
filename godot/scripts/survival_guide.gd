extends RefCounted
## Context is derived from current gameplay, so reloads and destroyed structures stay truthful.
var world: Node

func _init(owner: Node) -> void:
	world = owner

func build_step(kind: String, title: String, text: String) -> Dictionary:
	for b in world.session.buildings:
		if b.kind == kind and b.hp > 0 and b.remaining > 0:
			return {"title": "继续施工：" + world.Catalog.BUILDINGS[kind].name, "text": "这座建筑还剩 %.1f 秒施工。幸存者需到工地工作；移动会中断。右键工地即可接着建，不必再次购买。" % b.remaining, "action": "resume", "id": b.id, "button": "返回这处工地"}
	var spec: Dictionary = world.Catalog.BUILDINGS[kind]
	return {"title": title, "text": text + "\n\n造价 %d 木 / %d 金；当前还缺 %d 木 / %d 金。" % [spec.wood, spec.gold, maxi(0, spec.wood - world.session.wood), maxi(0, spec.gold - world.session.gold)], "action": "build", "kind": kind, "button": "选择建造：" + spec.name}

func current() -> Dictionary:
	var s = world.session
	if not world.started: return {"title": "建立营地，等待救援", "text": "先选标准生存，建立帐篷并采集资源，再发展电力、防线与科技。给营地保留出入口。右键下令；键盘移动的是镜头。", "action": "", "button": ""}
	if s.phase in ["won", "lost"]: return {"title": "本局已经结束", "text": "可以在结算界面读取较早存档重试，或重新开始。下次优先选择道路通畅、有树林且方便返回帐篷的位置。", "action": "", "button": ""}
	if s.phase == "evacuate": return {"title": "前往北侧 H 停机坪", "text": "H 是地图上的撤离标记。标准模式需留在范围内累计准备 12 秒；离开会缓慢丢失准备进度。治疗键是 %s，别将按键和地图标记混淆。" % world.preferences.key_name("heal"), "action": "evacuate", "button": "前往撤离点"}
	if not s.has_completed("tent"): return build_step("tent", "① 建造免费帐篷", "点击下方建造按钮，再在角色附近可见的空地左键放置。角色会走到工地施工；帐篷是木材和化石的返送点。")
	if world.worker.cargo > 0 and world.order == "waiting_dropoff": return {"title": "先恢复返送路线", "text": "携带物还没有进入库存。检查帐篷附近是否被树木、建筑或关闭的电门挡住；恢复道路后角色会继续尝试返送。", "action": "", "button": ""}
	if not s.has_completed("fire"): return build_step("fire", "② 采木并建造营火", "右键一棵已发现的树木，角色会伐木并把木材送回帐篷。初始每趟携带 1 木；画面上方库存只在返送后增加。营火也是后续设施的前置建筑。")
	if not s.has_completed("fossil"): return build_step("fossil", "③ 建立黄金来源", "先采集木材，造好化石挖掘场后右键它。黄金同样需要返送到帐篷才入账，单纯建成挖掘场不会自动产金。")
	if not s.has_completed("generator"): return build_step("generator", "④ 发展电力", "在化石挖掘场采金。发电站完工才供电，防御设施和研究会消耗电力；不要把帐篷出入口堵住。")
	if not s.has_completed("tower"): return build_step("tower", "⑤ 建立第一道防线", "弓箭塔需要供电。把塔放在营地外围，结合电栅栏和可通行电门；给角色返送与撤离留出通道。")
	if not s.has_completed("laboratory"):
		for b in s.buildings:
			if b.hp <= 0: continue
			if b.kind == "laboratory" and b.remaining > 0: return {"title": "实验室正在升级", "text": "升级完成后打开科技面板。科技提供携带容量、工作效率、防御、医疗及提前救援等选择。", "action": "", "button": ""}
			if b.kind == "lab" and b.remaining <= 0: return {"title": "⑥ 升级实验室", "text": "选择基础建筑后使用升级功能。材料不足时会显示具体原因；升级完成后可以研究科技。", "action": "upgrade", "id": b.id, "button": "选中并升级基础建筑"}
		return build_step("lab", "⑥ 准备营地研究", "基础建筑建成后还需要升级成实验室。先保证资源返送与供电正常，再投资研究。")
	return {"title": "⑦ 选择发展路线，准备撤离", "text": "物流科技提高背负容量和工作效率；防御、医疗提升守营地的能力。选中塔可改造远射或速射，围栏和电门可加固。出发前准备治疗，并确认北侧 H 路线通畅。", "action": "tech", "button": "打开科技面板"}

func knowledge() -> String:
	return "资源与施工\n木材和化石先进入携带物，送回已完成且可到达的帐篷才入账。工作途中移动会中断；再次右键目标可继续。建造预览变黄表示可能封路，确认前不会扣资源。\n\n修理与拆除\n选中受损建筑可点击修理，每秒消耗 1 木材恢复 8% 耐久；电门右键开关，用修理按钮维修。拆除返还总投入的 50% × 剩余耐久比例，向下取整，改造投入也计入；免费帐篷与研究费用不返还。拆除后立即恢复通路。\n\n电力与防线\n发电站完工才供电；断电会暂停防御与研究。箭塔可选远射、速射或重弩专精；选中塔还可单独加固，花费 12 木 / 10 金、施工 12 秒，耐久上限从 200 提至 320，保留原有伤势，施工期间停火。攻击专精与加固可叠加。栅栏和电门加固增加 180 耐久上限。选中防御设施可查看覆盖范围。\n\n恐龙与声音\n树林、地形和距离可以切断追踪。采集、施工和开火产生局部噪声。标准模式迅猛龙会利用可通行缺口追击看见的幸存者，成年霸王龙会集中攻击已选建筑；橙色圈是重击预警。困难模式首领的范围重击越靠近中心越危险，错开塔位可减少连带伤害。攻击恐龙仍会引起反击。交战结束后可利用短暂间隔修整，野外恐龙仍会活动。\n\n治疗与撤离\n帐篷治疗花费黄金。冰原减缓恐龙，山地防线有区域加成，部分建筑在沼泽施工更快。救援到达后前往北侧 H 停机坪，标准模式累计守住 12 秒。\n\n保存与失败\n每 2 分钟自动保存，轮换三份记录，也可手动保存。载入后先暂停，失败时可读较早记录重试。"
