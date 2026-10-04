extends SceneTree
const Maps = preload("res://scripts/map_catalog.gd")
const SaveStore = preload("res://scripts/save_store.gd")
const TerrainData = preload("res://scripts/terrain_data.gd")
const Regions = preload("res://scripts/regions.gd")
const MAP_ID := "organic-island-v3"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func position(marker: Dictionary) -> Vector3:
	return Vector3(float(marker.world[0]), 0, float(marker.world[1]))

func flood(board: RefCounted, origin: Vector2i) -> Dictionary:
	var seen := {origin: true}
	var queue: Array[Vector2i] = [origin]
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if board.is_open(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen

func make_world() -> Node:
	var w: Node = load("res://scenes/main.tscn").instantiate()
	w.persistence_enabled = false
	root.add_child(w)
	w.set_process(false)
	w.set_physics_process(false)
	return w

func run() -> void:
	var previous := Maps.selected_id
	Maps.selected_id = MAP_ID
	expect(Maps.MAPS.size() == 1 and Maps.MAPS[0].id == MAP_ID, "Only the original island remains selectable")
	expect(Maps.is_valid(MAP_ID), "Natural island is selectable")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/organic_island_v3.json"))
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_candidates/organic_island_v3.json"))
	expect(data.id == MAP_ID and not data.opening_overlay, "Runtime loads the natural island without the old opening overlay")
	var w := make_world()
	await process_frame
	expect(w.map_id == MAP_ID and w.board.layout.placements == data.placements, "Live world and scenery use the new terrain file")
	var live_spawn: Vector2i = w.board.cell_at(w.hero.position)
	expect(w.board.can_build(live_spawn), "Random survival spawn is buildable")
	var spawn_wood := 0
	for tree_cell in w.trees:
		if w.board.point(tree_cell).distance_to(w.hero.position) <= 24.0: spawn_wood += 1
	expect(spawn_wood >= 8, "Random survival spawn has nearby harvestable timber")
	var selected := false
	for index in range(w.hud.map_select.item_count):
		if w.hud.map_select.get_item_metadata(index) == MAP_ID:
			selected = w.hud.map_select.selected == index
	expect(selected and w.hud.start_title.text == "进入原始荒岛", "Menu displays the map loaded by the world")
	var reachable := flood(w.board, w.board.cell_at(w.hero.position))
	var open_count := 0
	var wood := 0
	var all_flat_trees := true
	for y in range(128):
		for x in range(128):
			if w.board.is_open(Vector2i(x, y)): open_count += 1
	for cell in w.trees:
		wood += int(w.trees[cell].wood)
		var p: Vector3 = w.board.point(cell)
		all_flat_trees = all_flat_trees and not w.board.layout.submerged_at(p.x, p.z)
	expect(reachable.size() == open_count, "No disconnected open-looking areas exist at the start")
	expect(w.trees.size() == design.metrics.harvestable_trees and wood == design.metrics.total_wood and wood >= 54000 and wood <= 60000, "Live forest keeps the comparable finite timber reserve")
	expect(all_flat_trees, "Harvestable trees stand on dry terrain")
	for site in data.camp_sites:
		var cell: Vector2i = w.board.cell_at(position(site))
		expect(w.board.can_build(cell) and reachable.has(cell), "Natural camp is reachable and buildable: " + str(site.id))
		var player_route: PackedVector3Array = w.board.route(w.hero.position, w.board.point(cell), false, w.hero.body_radius)
		var previous_point: Vector3 = w.hero.position
		var passable: bool = w.hero.position.distance_to(w.board.point(cell)) < .05 or not player_route.is_empty()
		for point in player_route:
			passable = passable and w.board.body_segment_open(previous_point, point, w.hero.body_radius)
			previous_point = point
		expect(passable, "Player body can pass into each clearing before harvesting: " + str(site.id))
		var trees_near_site := 0
		var plots := 0
		for y in range(cell.y - 7, cell.y + 8):
			for x in range(cell.x - 7, cell.x + 8):
				var nearby := Vector2i(x, y)
				if w.board.can_build(nearby): plots += 1
				if w.trees.has(nearby): trees_near_site += 1
		expect(plots >= 24, "Each clearing has usable base space rather than just a passable center: " + str(site.id))
		if site.get("kind", "") == "forest_interior":
			expect(trees_near_site >= 45, "Forest interior retains dense timber beside base space: " + str(site.id))
		if site.get("kind", "") == "rock_hollow":
			var rock_sides := 0
			for offset in [Vector2i(-8, 0), Vector2i(8, 0), Vector2i(0, -8), Vector2i(0, 8)]:
				if not w.board.is_open(cell + offset): rock_sides += 1
			expect(rock_sides >= 2, "Rock hollow keeps visible protective sides around an accessible floor: " + str(site.id))
			var local_wood := 0
			for tree_cell in w.trees:
				if w.board.point(tree_cell).distance_to(w.board.point(cell)) < 30: local_wood += int(w.trees[tree_cell].wood)
			expect(local_wood >= 2400, "Rock hollow has nearby timber to supply a base: " + str(site.id))
	for site in data.stepping_sites:
		var cell: Vector2i = w.board.cell_at(position(site))
		expect(w.board.can_build(cell) and reachable.has(cell), "Forest stepping space can be reached and used: " + str(site.id))
		var route: PackedVector3Array = w.board.route(w.hero.position, w.board.point(cell), false, w.hero.body_radius)
		var start_point: Vector3 = w.hero.position
		var route_valid := not route.is_empty()
		for p in route:
			route_valid = route_valid and w.board.body_segment_open(start_point, p, w.hero.body_radius)
			start_point = p
		expect(route_valid, "Live player can traverse a route to each stepping space: " + str(site.id))
	var all_route_cells := true
	for route in data.routes:
		for coords in route.world:
			if not reachable.has(w.board.cell_at(Vector3(float(coords[0]), 0, float(coords[1])))): all_route_cells = false
	expect(all_route_cells, "All forest, coast, valley and pocket links are connected in the actual world")
	expect(design.metrics.connected_pocket_links > 0, "Isolated understory pockets are connected through natural openings")
	expect(w.board.layout.authored_surface.size() == 257 * 257, "Picking and terrain use the authored smooth river banks")
	var river_is_continuous := true
	var narrow_width := INF
	var wide_width := 0.0
	for coords in design.waterways[0].path:
		var center := Vector2(float(coords[0]), float(coords[1]))
		if center.y > 70: continue
		var width := 0.0
		for dx in range(-7, 8):
			if w.board.layout.submerged_at(center.x + dx, center.y): width += 1
		narrow_width = minf(narrow_width, width)
		wide_width = maxf(wide_width, width)
		var left: float = w.board.layout.water_level_at(center.x - .001, center.y)
		var right: float = w.board.layout.water_level_at(center.x + .001, center.y)
		river_is_continuous = river_is_continuous and absf(left - right) < .005
	expect(river_is_continuous and wide_width > narrow_width, "River varies in width with continuous water levels at cell boundaries")
	var interior_regions := 0
	for region in design.metrics.forest_regions:
		if region.id == "marsh_edge_forest": continue
		interior_regions += 1
		expect(region.interior_open_cells >= 20 and region.tree_cells >= 150, "Large forest combines deep accessible spaces and thick timber: " + str(region.id))
	expect(interior_regions >= 4, "Accessible forest interiors are distributed across the island")
	var tight_gaps := 0
	for entry in design.forest_entrances:
		var p: Vector3 = w.board.point(w.board.cell_at(position(entry)))
		expect(w.board.body_open(p, w.hero.body_radius) and not w.board.route(w.hero.position, p).is_empty(), "Forest approach is reachable by the actual player: " + str(entry.route))
		if not w.board.body_open(p, w.Board.species_radius("trex")): tight_gaps += 1
	expect(tight_gaps >= 2, "Some forest gaps admit the player while restricting larger dinosaurs")
	var rescue_cell: Vector2i = w.board.cell_at(position(data.extraction_sites[0]))
	expect(w.board.cell_at(w.extraction) == rescue_cell, "Rescue uses the new map's authored clearing")
	expect(not w.board.route(w.hero.position, w.extraction, true).is_empty(), "West landing can reach rescue")
	expect(w.board.layout.free_fossil_placement, "Organic island enables free fossil placement")
	var creek := Vector2i(-1, -1)
	for cell in reachable:
		var p: Vector3 = w.board.point(cell)
		if w.board.layout.wading_at(p.x, p.z):
			creek = cell
			break
	expect(creek != Vector2i(-1, -1), "Island has accessible shallow water")
	if creek != Vector2i(-1, -1):
		var p: Vector3 = w.board.point(creek)
		expect(not w.board.can_build(creek) and w.board.layout.movement_factor_at(p.x, p.z) < 1, "Shallows allow wading while excluding construction")
	expect(not w.board.is_open(w.board.cell_at(Vector3(119, 0, 105))) and w.board.layout.submerged_at(119, 105), "Sea visibly marks the unreachable island boundary")
	expect(Regions.at(Vector3(-57, 0, -53)) == "rainforest" and Regions.at(Vector3(60, 0, 54)) == "swamp", "Biomes follow actual forest and wetland shapes")
	var nearest := Vector2i(-1, -1)
	var distance := INF
	for cell in w.trees:
		var p: Vector3 = w.board.point(cell)
		if p.distance_to(w.hero.position) >= distance: continue
		if w.worker.wood_route(p).is_empty(): continue
		nearest = cell
		distance = p.distance_to(w.hero.position)
	expect(nearest != Vector2i(-1, -1) and distance <= 18, "Landing camp has timber reachable by the actual harvesting approach")
	if nearest != Vector2i(-1, -1):
		w.start_session(3600)
		w.trees[nearest].wood = 1
		w.command(w.board.point(nearest))
		for i in range(420): w._physics_process(1.0 / 30)
		expect(not w.trees.has(nearest) and w.worker.cargo == 1, "Survivor can walk to a tree and harvest it")
		expect(w.board.is_open(nearest) and w.board.can_build(nearest), "Harvesting opens dry forest for construction")
		var snapshot := SaveStore.snapshot(w)
		expect(SaveStore.validate(snapshot).is_empty(), "Natural island save validates")
		w.free()
		await process_frame
		w = make_world()
		SaveStore.apply(w, snapshot)
		expect(w.map_id == MAP_ID and not w.trees.has(nearest) and w.board.can_build(nearest), "Reload retains the correct map and cleared forest")
		# Check the player-facing placement rules, not only the terrain's build mask.
		w.paused = false
		w.session.wood = 100
		var start: Vector2i = w.board.cell_at(position(data.spawn_points[0]))
		w.hero.position = w.board.point(start)
		w.hero.route.clear()
		w.select_build("tent")
		var plot: Vector2i = start + Vector2i(2, 0)
		w.vision.visible_cells[plot] = true
		expect(w.placement_error(plot).is_empty(), "Landing clearing accepts a tent through normal placement rules")
		w.place_building(plot, true)
		var tent: Dictionary = w.building_at(plot)
		expect(not tent.is_empty() and tent.kind == "tent" and w.board.structures.has(plot), "Building a tent creates the actual camp and occupancy")
		if not tent.is_empty():
			tent.remaining = 0.0
			# Supply the prerequisite fire, then place an excavation through the live API.
			var fire: Dictionary = w.session.build("fire", start + Vector2i(0, 2))
			fire.remaining = 0.0
			var mine: Vector2i = start + Vector2i(3, 0)
			w.hero.position = w.board.point(mine + Vector2i.LEFT)
			w.hero.route.clear()
			w.vision.visible_cells[mine] = true
			w.select_build("fossil")
			expect(w.placement_error(mine).is_empty(), "Natural deposit accepts excavation after camp prerequisites")
			w.place_building(mine, true)
			var field: Dictionary = w.building_at(mine)
			expect(not field.is_empty() and not field.has("deposit_id"), "Excavation remains unbound on a free placement map")
	# Exercise player-facing construction inside both forest and rock enclosures.
	for site in data.camp_sites:
		if site.id not in ["north_inner_grove", "west_rock_hollow"]: continue
		var cell: Vector2i = w.board.cell_at(position(site))
		w.hero.position = w.board.point(cell + Vector2i.RIGHT * 2)
		w.hero.route.clear()
		w.session.wood = 1000
		w.vision.visible_cells[cell] = true
		w.select_build("tent")
		expect(w.placement_error(cell).is_empty(), "Live placement accepts a base inside an enclosure: " + str(site.id))
		w.place_building(cell, true)
		expect(w.building_at(cell).get("kind", "") == "tent", "Base is created inside the enclosure: " + str(site.id))
	w.free()
	Maps.selected_id = previous
	print("ORGANIC ISLAND: ", checks, " checks, ", failures, " failures; timber=", wood, " open=", open_count)
	quit(0 if failures == 0 else 1)
