extends RefCounted
## Authored opening basin. Heights, water and navigation use the same profile.
const WATER_LEVEL := 0.7
const MAX_WADING_DEPTH := 0.42

static func lake_distance(x: float, z: float) -> float:
	var bend := 1.8*sin((z+14.0)*.16)
	var q := Vector2((x-18.0-bend)/6.6,(z+14.0)/9.5)
	var angle := atan2(q.y,q.x)
	return (q.length()-1.0-.045*sin(angle*3.0+.7)-.025*cos(angle*5.0))*6.6

static func ground_height(x: float, z: float) -> float:
	var meadow := 1.65+.18*sin(x*.09+z*.035)+.12*cos(z*.11-x*.04)
	var distance := lake_distance(x,z)
	if distance >= 5.5: return meadow
	if distance >= 0: return lerpf(WATER_LEVEL,meadow,smoothstep(0,5.5,distance))
	# A broad sandy shelf crosses the southern end of the lake. Its two banks
	# remain connected for both actors and the navigation grid.
	var shelf := 1.0-smoothstep(3.4,5.8,absf(z+7.0+.35*sin(x*.21)))
	var depth := lerpf(1.45,.26,shelf)*smoothstep(0,3.3,-distance)
	return WATER_LEVEL-depth

static func apply(layout: RefCounted) -> void:
	for y in range(129):
		for x in range(129):
			var px := x*2.0-128.0
			var pz := y*2.0-128.0
			var radius := Vector2(px,pz).length()
			if radius >= 46.0: continue
			var i := y*129+x
			var influence := 1.0-smoothstep(35.0,46.0,radius)
			layout.heights[i] = lerpf(layout.heights[i],ground_height(px,pz),influence)
			if radius < 35.0:
				# The entire lake domain receives one plane. Its actual contour is
				# the continuous ground/water intersection, never a tile boundary.
				layout.water[i] = WATER_LEVEL if lake_distance(px,pz) < 6.0 else -100.0
				layout.tiles[i] = 4 if lake_distance(px,pz) < 1.7 else (6 if sin(px*.14+pz*.08) > -.2 else 0)
	for y in range(128):
		for x in range(128):
			var px := x*2.0-127.0
			var pz := y*2.0-127.0
			if Vector2(px,pz).length() >= 34.0: continue
			var lowest := INF
			# Every point of a traversable cell must stay within wading depth.
			for dz in [-1.0,0.0,1.0]:
				for dx in [-1.0,0.0,1.0]: lowest = minf(lowest,ground_height(px+dx,pz+dz))
			layout.walk[y*128+x] = lowest >= WATER_LEVEL-MAX_WADING_DEPTH
			layout.build[y*128+x] = lowest > WATER_LEVEL+.22
