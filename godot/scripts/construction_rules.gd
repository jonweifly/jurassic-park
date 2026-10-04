extends RefCounted
class_name ConstructionRules
## Placement policy kept separate from the input/UI flow in world.gd.
## The world adapter is intentionally explicit for this first migration step.

static func placement_error(world: Node, cell: Vector2i, kind: String) -> String:
	if kind.is_empty(): return ""
	if not world.vision.is_visible(cell): return "需要先探索此处"
	if world.board.structures.has(cell) or not world.building_at(cell).is_empty(): return "此处已有建筑或设施"
	if not world.board.is_open(cell): return "此处被障碍、水域或陡坡阻挡"
	if not world.board.can_build(cell): return "坡地或地表不适合建造，请选择平坦区域"
	var p: Vector3 = world.board.point(cell)
	if kind == "fossil" and not world.board.layout.free_fossil_placement and not world.board.layout.gold_zones.is_empty():
		var zone: Dictionary = world.board.layout.gold_zone_at(p)
		if zone.is_empty(): return "化石挖掘场只能建在标记的矿区"
		if int(world.session.deposit_reserves.get(str(zone.id), 0)) <= 0: return "这片矿区已枯竭"
		var fields := 0
		for building in world.session.buildings:
			if building.kind == "fossil" and building.hp > 0 and building.get("deposit_id", "") == zone.id: fields += 1
		if fields >= int(zone.fields): return "这片矿区的挖掘场已达到上限"
	if p.distance_to(world.extraction) < 5: return "请保持撤离区畅通"
	for survivor in world.survivors():
		if p.distance_to(survivor.position) < 1.5: return "幸存者占据此位置"
	for dinosaur in world.dinosaurs:
		if dinosaur.health > 0 and p.distance_to(dinosaur.position) < 1.7: return "恐龙占据此位置"
	if world.board.route(world.hero.position, p, true).is_empty() and p.distance_to(world.hero.position) > 3: return "无法到达施工位置"
	if p.distance_to(world.hero.position) > 12: return "距离过远，请让幸存者靠近"
	return world.session.can_afford(kind)

static func placement_warning(world: Node, cell: Vector2i, kind: String) -> String:
	if kind.is_empty(): return ""
	var warning: String = world.build_access.warning(cell)
	if not warning.is_empty() and kind == "gate": warning += "；电门施工完成并打开后可通行"
	return warning
