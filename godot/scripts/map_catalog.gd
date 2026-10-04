extends RefCounted
## The playable maps share the same survival rules but use independent terrain data.
const MAPS: Array[Dictionary] = [
	{"id": "organic-island-v3", "name": "原始荒岛", "subtitle": "连通林隙 · 林岩交错 · 岩谷补给 · 自然浅溪", "file": "organic_island_v3.json", "biome_source": "res://data/map_candidates/organic_island_v3.json"},
]
static var selected_id := "organic-island-v3"
static var pending_start: Dictionary = {}

static func definition(id: String) -> Dictionary:
	for item in MAPS:
		if item.id == id: return item
	return MAPS[0]

static func is_valid(id: String) -> bool:
	return not definition(id).is_empty() and definition(id).id == id
