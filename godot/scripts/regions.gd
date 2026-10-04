extends RefCounted
## Authored biomes around the central camp meadow.
const MapCatalog = preload("res://scripts/map_catalog.gd")
const NAMES = {"rainforest": "雨林", "mountain": "山地", "ice": "冰原", "swamp": "沼泽", "center": "中央空地"}
const SWAMP_FAST = ["tent", "fire", "fossil", "generator", "shelter", "lab", "gate"]
static var authored_regions: Dictionary = {}

static func authored_at(p: Vector3, path: String) -> String:
	if not authored_regions.has(path):
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var polygons: Array = []
		for region in data.get("biome_regions", []):
			var polygon := PackedVector2Array()
			for coords in region.polygon: polygon.append(Vector2(float(coords[0]), float(coords[1])))
			polygons.append({"biome": str(region.biome), "polygon": polygon})
		authored_regions[path] = {"regions": polygons, "default": str(data.get("default_biome", "rainforest"))}
	var shape: Dictionary = authored_regions[path]
	for region in shape.regions:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), region.polygon): return region.biome
	return shape.default

static func at(p: Vector3) -> String:
	var definition := MapCatalog.definition(MapCatalog.selected_id)
	var source := str(definition.get("biome_source", ""))
	# The central camp remains its own gameplay space even when an authored map
	# provides surrounding biome polygons without a dedicated centre polygon.
	if not source.is_empty() and Vector2(p.x, p.z).length() < 18.0: return "center"
	if not source.is_empty(): return authored_at(p, source)
	if definition.get("region_profile", "") == "rainforest":
		return "center" if Vector2(p.x, p.z).length() < 18.0 else "rainforest"
	if p.x < -18.0 and p.z < -12.0: return "ice"
	if p.x > 18.0 and p.z < -12.0: return "mountain"
	if p.x > 14.0 and p.z > 14.0: return "swamp"
	if p.x < -14.0 and p.z > 10.0: return "rainforest"
	return "center"

static func construction_remaining(kind: String, p: Vector3, seconds: float) -> float:
	return seconds * 0.3 if at(p) == "swamp" and kind in SWAMP_FAST else seconds
