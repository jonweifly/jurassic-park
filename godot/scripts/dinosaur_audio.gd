extends RefCounted
## Cue timing uses presentation state only and does not consume combat randomness.
var sound: Node
var heard := {}
var last_seen := {}
var serial := 0
var gap := 0.0
var last_key := ""
var cue_count := 0
func _init(owner_sound: Node) -> void: sound = owner_sound

func cue(d: Node3D, attack: bool = false) -> bool:
	if not sound.audible(d.position) or d.health <= 0: return false
	var id: int = d.get_instance_id()
	var now: float = sound.world.session.game_time()
	if now-heard.get(id,-100.0) < (4.0 if attack else 8.0): return false
	if gap > 0: return false
	var species: String = d.get_meta("species","raptor")
	last_key = "%s_call_%d" % [species,1+serial%2]
	serial += 1
	cue_count += 1
	heard[id] = now
	gap = maxf(2.2,sound.streams[last_key].get_length()+0.25)
	sound.play_at(last_key,d.position,1.5 if species == "trex" else (-0.5 if species == "young_trex" else -2.0),true)
	return true

func update(dt: float) -> void:
	gap = maxf(0,gap-dt)
	var world: Node = sound.world
	var now: float = world.session.game_time()
	var best: Node3D
	var score := -INF
	var live := {}
	for d in world.dinosaurs:
		var id: int = d.get_instance_id()
		live[id] = true
		if d.health <= 0 or not d.visible or not sound.audible(d.position): continue
		var fresh: bool = now-last_seen.get(id,-100.0) > 12
		last_seen[id] = now
		if fresh: heard.erase(id)
		var interval := 15.0 if d.get_meta("species","") == "trex" else 11.0
		if now-heard.get(id,-100.0) < interval: continue
		var value: float = (20 if d.get_meta("species","") == "trex" else 8)-d.position.distance_to(world.camera_focus)*.3
		if d.get_meta("ai_state","") == "alert": value += 6
		if value > score:
			best = d
			score = value
	if best: cue(best)
	for id in heard.keys():
		if not live.has(id): heard.erase(id)
	for id in last_seen.keys():
		if not live.has(id): last_seen.erase(id)
