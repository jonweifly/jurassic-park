extends "res://scripts/board.gd"
## Profiler wrapper, never used by gameplay.
var profile := {"route_us":0,"route_calls":0,"grid_us":0,"grid_calls":0,"slowest":[]}
func route(from: Vector3, to: Vector3, adjacent: bool = false, radius: float = 0.0) -> PackedVector3Array:
	var t := Time.get_ticks_usec()
	var path := super.route(from,to,adjacent,radius)
	var elapsed := Time.get_ticks_usec() - t
	profile.route_us += elapsed
	profile.route_calls += 1
	if elapsed > 3000:
		profile.slowest.append({"us":elapsed,"from":str(cell_at(from)),"to":str(cell_at(to)),"radius":radius,"adjacent":adjacent,"length":path.size()})
		profile.slowest.sort_custom(func(a,b): return a.us>b.us)
		if profile.slowest.size()>12: profile.slowest.resize(12)
	return path
func grid_for_radius(radius: float) -> AStarGrid2D:
	var t := Time.get_ticks_usec()
	var result := super.grid_for_radius(radius)
	profile.grid_us += Time.get_ticks_usec()-t
	profile.grid_calls += 1
	return result
