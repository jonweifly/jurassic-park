extends RefCounted
const SIDE := 128
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

func height_at(x: float, z: float) -> float:
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

func submerged_at(x: float, z: float) -> bool:
	var cell_x := clampi(floori(x / 2.0 + 64.0), 0, 127)
	var cell_z := clampi(floori(z / 2.0 + 64.0), 0, 127)
	var level: float = water[cell_z * 129 + cell_x]
	return level > -90.0 and level > height_at(x, z) + 0.08
