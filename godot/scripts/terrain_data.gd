extends RefCounted
const SIDE := 128
const Surface = preload("res://scripts/terrain_surface.gd")
const Opening = preload("res://scripts/opening_terrain.gd")
var surface_heights := PackedFloat32Array()
var water_cells := PackedFloat32Array()
var shore_field := PackedFloat32Array()
var heights: Array = []
var tiles: Array = []
var water: Array = []
var walk: Array = []
var build: Array = []
var placements: Array = []

func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain.json"))
	heights = data.heights
	tiles = data.tiles
	water = data.water
	walk = data.walk
	build = data.build
	placements = data.placements
	Opening.apply(self)
	rebuild_surface(true)

func rebuild_surface(authored_opening: bool = false) -> void:
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
	# Match the triangles emitted by reference_island.gd, including slopes.
	var u := fx - ix
	var v := fy - iy
	if u + v <= 1: return a + (b - a) * u + (c - a) * v
	return d + (c - d) * (1 - u) + (b - d) * (1 - v)

func water_level_at(x: float, z: float) -> float:
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
