extends RefCounted
## war3map.j 15714–15730. Warcraft Y is north; Godot -Z is north.
const BOUNDS = {
	"rainforest": [Rect2(-7520, -8128, 7200, 6208), Rect2(-7552, -1888, 6112, 3488)],
	"mountain": [Rect2(1696, -512, 6336, 2272), Rect2(256, 1760, 7744, 5408)],
	"ice": [Rect2(-7520, 1952, 7360, 5280)],
	"swamp": [Rect2(128, -7968, 7840, 6112)]
}
const NAMES = {"rainforest": "雨林", "mountain": "山地", "ice": "冰原", "swamp": "沼泽", "center": "中央空地"}
const SWAMP_FAST = ["tent", "fire", "fossil", "generator", "shelter", "lab", "gate"]

static func at(p: Vector3) -> String:
	var point := Vector2(p.x * 64.0, -p.z * 64.0)
	for kind in BOUNDS:
		for rect in BOUNDS[kind]:
			if rect.has_point(point): return kind
	return "center"

static func construction_remaining(kind: String, p: Vector3, seconds: float) -> float:
	return seconds * 0.3 if at(p) == "swamp" and kind in SWAMP_FAST else seconds
