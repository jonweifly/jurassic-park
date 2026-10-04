extends RefCounted
const SIDE := 128
const Surface = preload("res://scripts/terrain_surface.gd")
const Opening = preload("res://scripts/opening_terrain.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")
var surface_heights := PackedFloat32Array()
var water_cells := PackedFloat32Array()
var shore_field := PackedFloat32Array()
var heights: Array = []
var tiles: Array = []
var water: Array = []
var walk: Array = []
var build: Array = []
var placements: Array = []
var spawn_points: Array = []
var extraction_sites: Array = []
var gold_zones: Array = []
var free_fossil_placement := false
var preserve_source_surface := false
var authored_surface := PackedFloat32Array()
var surface_water_levels := PackedFloat32Array()
var authored_shore := PackedFloat32Array()

func _init(map_id: String = "") -> void:
	var selected := map_id if not map_id.is_empty() else MapCatalog.selected_id
	var definition := MapCatalog.definition(selected)
	var path := str(definition.get("source", ""))
	if path.is_empty(): path = "res://data/maps/" + str(definition.file)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	heights = data.heights
	tiles = data.tiles
	water = data.water
	walk = data.walk
	build = data.build
	placements = data.placements
	spawn_points = data.get("spawn_points", [])
	extraction_sites = data.get("extraction_sites", [])
	gold_zones = data.get("gold_zones", [])
	free_fossil_placement = bool(data.get("free_fossil_placement", definition.get("free_fossil_placement", false)))
	authored_surface = PackedFloat32Array(data.get("surface_heights", []))
	surface_water_levels = PackedFloat32Array(data.get("surface_water_levels", []))
	authored_shore = PackedFloat32Array(data.get("surface_shore_field", []))
	preserve_source_surface = bool(definition.get("preserve_source_surface", false))
	var opening_overlay: bool = definition.get("opening_overlay", data.get("opening_overlay", true))
	if opening_overlay: Opening.apply(self)
	rebuild_surface(opening_overlay)

func gold_zone_at(position: Vector3) -> Dictionary:
	for zone in gold_zones:
		var coords: Array = zone.world
		if Vector2(position.x - float(coords[0]), position.z - float(coords[1])).length() <= float(zone.radius): return zone
	return {}

func rebuild_surface(authored_opening: bool = false) -> void:
	if authored_surface.size() == 257 * 257 and surface_water_levels.size() == 257 * 257 and authored_shore.size() == 257 * 257:
		# Authored river banks use the exact same fine grid for picking and water.
		surface_heights = authored_surface.duplicate()
		# Keep the authored one-metre river profile on blocked ground, while
		# preserving the original coarse terrain exactly anywhere a survivor can
		# walk or build.  The map masks are two-metre cells, so patch every fine
		# vertex touching a protected cell with the same bilinear source height.
		for y in range(257):
			for x in range(257):
				var cell_x := floori(float(x) * 0.5)
				var cell_y := floori(float(y) * 0.5)
				var protected := false
				for dy in [-1, 0]:
					for dx in [-1, 0]:
						var cx := clampi(cell_x + dx, 0, 127)
						var cy := clampi(cell_y + dy, 0, 127)
						if walk[cy * 128 + cx] or build[cy * 128 + cx]: protected = true
				if protected:
					var fx := float(x) * 0.5
					var fz := float(y) * 0.5
					var ix := mini(floori(fx), 127)
					var iz := mini(floori(fz), 127)
					var u := fx - ix
					var v := fz - iz
					var a: float = heights[iz * 129 + ix]
					var b: float = heights[iz * 129 + ix + 1]
					var c: float = heights[(iz + 1) * 129 + ix]
					var d: float = heights[(iz + 1) * 129 + ix + 1]
					surface_heights[y * 257 + x] = a + (b - a) * u + (c - a) * v if u + v <= 1.0 else d + (c - d) * (1.0 - u) + (b - d) * (1.0 - v)
				else:
					# Blocked banks can carry a subtle continuous bend between the
					# authored river samples. It breaks up the old two-metre grid while
					# remaining below the bounded relief used by the map contract.
					var px := float(x) - 128.0
					var pz := float(y) - 128.0
					surface_heights[y * 257 + x] += (sin(px * 0.17 + pz * 0.11) + sin(pz * 0.23 - px * 0.09)) * 0.11
		shore_field = authored_shore.duplicate()
		water_cells.resize(128 * 128)
		for y in range(128):
			for x in range(128): water_cells[y * 128 + x] = surface_water_levels[(y * 2 + 1) * 257 + x * 2 + 1]
		return
	surface_heights = Surface.prepare(self,authored_opening)
	water_cells.resize(128*128)
	var wet := PackedFloat32Array()
	wet.resize(128*128)
	for y in range(128):
		for x in range(128):
			var i := y*129+x
			var level: float = water[i]
			wet[y*128+x] = 1.0 if level > -90 and minf(minf(heights[i],heights[i+1]),minf(heights[i+129],heights[i+130])) < level else 0.0
	# A continuous basin field rounds corners even where the imported water
	# flag ends above a deep bed. It is clipped into geometry, not pixel tiles.
	shore_field.resize(257*257)
	for y in range(257):
		for x in range(257):
			var gx := float(x)*.5-.5
			var gy := float(y)*.5-.5
			var ix := floori(gx)
			var iy := floori(gy)
			var wx := Surface.weights(gx-ix)
			var wy := Surface.weights(gy-iy)
			var density := 0.0
			for dy in range(4):
				for dx in range(4): density += wet[clampi(iy+dy-1,0,127)*128+clampi(ix+dx-1,0,127)]*wx[dx]*wy[dy]
			shore_field[y*257+x] = (density-.36)*4.0
			if authored_opening and Vector2(x-128,y-128).length() < 34.0: shore_field[y*257+x] = 1.0
	var anchors := {}
	for entry in placements:
		var x := clampi(floori(float(entry[1])*.5+64),0,127)
		var y := clampi(floori(float(entry[2])*.5+64),0,127)
		anchors[y*128+x] = true
	for y in range(128):
		for x in range(128):
			var level: float = water[y*129+x]
			# Permit only adjacent blocked bank cells to receive the same lake
			# plane. Terrain clipping defines its edge, not an absent tile flag.
			if level <= -90 and not walk[y*128+x] and not build[y*128+x] and not anchors.has(y*128+x):
				var candidate := INF
				for dy in [-1,0,1]:
					for dx in [-1,0,1]:
						var near: float = water[clampi(y+dy,0,127)*129+clampi(x+dx,0,127)]
						if near > -90: candidate = minf(candidate,near)
				if candidate < INF: level = candidate
			water_cells[y*128+x] = level

func height_at(x: float, z: float) -> float:
	var fx := clampf(x+128.0,0.0,255.9999)
	var fz := clampf(z+128.0,0.0,255.9999)
	var ix := floori(fx)
	var iz := floori(fz)
	var u := fx-ix
	var v := fz-iz
	var a := surface_heights[iz*257+ix]
	var b := surface_heights[iz*257+ix+1]
	var c := surface_heights[(iz+1)*257+ix]
	var d := surface_heights[(iz+1)*257+ix+1]
	return a+(b-a)*u+(c-a)*v if u+v <= 1 else d+(c-d)*(1-u)+(b-d)*(1-v)

func height_image() -> Image:
	return Image.create_from_data(257,257,false,Image.FORMAT_RF,surface_heights.to_byte_array())

func source_height_at(x: float, z: float) -> float:
	var fx := clampf(x / 2.0 + 64.0, 0, 127.999)
	var fy := clampf(z / 2.0 + 64.0, 0, 127.999)
	var ix := floori(fx)
	var iy := floori(fy)
	var a: float = heights[iy * 129 + ix]
	var b: float = heights[iy * 129 + ix + 1]
	var c: float = heights[(iy + 1) * 129 + ix]
	var d: float = heights[(iy + 1) * 129 + ix + 1]
	# Match the triangles emitted by the island bake, including slopes.
	var u := fx - ix
	var v := fy - iy
	if u + v <= 1: return a + (b - a) * u + (c - a) * v
	return d + (c - d) * (1 - u) + (b - d) * (1 - v)

func water_level_at(x: float, z: float) -> float:
	if not surface_water_levels.is_empty():
		var fx := clampf(x + 128, 0, 255.9999)
		var fz := clampf(z + 128, 0, 255.9999)
		var ix := floori(fx)
		var iz := floori(fz)
		var u := fx - ix
		var v := fz - iz
		var a := surface_water_levels[iz * 257 + ix]
		var b := surface_water_levels[iz * 257 + ix + 1]
		var c := surface_water_levels[(iz + 1) * 257 + ix]
		var d := surface_water_levels[(iz + 1) * 257 + ix + 1]
		return a + (b - a) * u + (c - a) * v if u + v <= 1 else d + (c - d) * (1 - u) + (b - d) * (1 - v)
	var cell_x := clampi(floori(x / 2.0 + 64.0), 0, 127)
	var cell_z := clampi(floori(z / 2.0 + 64.0), 0, 127)
	return water_cells[cell_z * 128 + cell_x]

func submerged_at(x: float, z: float) -> bool:
	var level := water_level_at(x,z)
	return level > -90.0 and level > height_at(x, z) + 0.08

func wading_at(x: float, z: float) -> bool:
	var cell_x := clampi(floori(x*.5+64),0,127)
	var cell_z := clampi(floori(z*.5+64),0,127)
	return walk[cell_z*128+cell_x] and submerged_at(x,z)

func movement_factor_at(x: float, z: float) -> float:
	return .70 if wading_at(x,z) else 1.0
