extends RefCounted
## Continuous banks on a one-metre grid. Navigation masks stay authoritative.
const SIZE := 257
const Regions = preload("res://scripts/regions.gd")
const PALETTE := [Color("726c47"), Color("8c815a"), Color("81724e"), Color("444840"), Color("b7a87e"), Color("777e75"), Color("596c40"), Color("3a5735"), Color("bccdd0")]

static func weights(t: float) -> Vector4:
	var s := 1.0-t
	return Vector4(s*s*s, 3.0*t*t*t-6.0*t*t+4.0, -3.0*t*t*t+3.0*t*t+3.0*t+1.0, t*t*t)/6.0

static func prepare(layout: RefCounted, authored_opening: bool = false) -> PackedFloat32Array:
	var strengths := PackedFloat32Array()
	strengths.resize(129*129)
	strengths.fill(1.0)
	# Every corner of a walkable/buildable cell is pinned. Interpolation of these
	# weights keeps the entire cell at its exact original collision height.
	for y in range(129):
		for x in range(129):
			for dy in [-1,0]:
				for dx in [-1,0]:
					var cx := clampi(x+dx,0,127)
					var cy := clampi(y+dy,0,127)
					if layout.walk[cy*128+cx] or layout.build[cy*128+cx]: strengths[y*129+x] = 0.0
	# Existing resource roots/rocks are authored anchors too. A shoreline pass
	# must not sink harvestable trees or expose their foundations.
	for entry in layout.placements:
		var x := clampi(floori(float(entry[1])*.5+64),0,127)
		var y := clampi(floori(float(entry[2])*.5+64),0,127)
		for offset in [0,1,129,130]: strengths[y*129+x+offset] = 0.0
	var result := PackedFloat32Array()
	result.resize(SIZE*SIZE)
	for y in range(SIZE):
		for x in range(SIZE):
			var px := float(x)-128.0
			var pz := float(y)-128.0
			var original: float = layout.source_height_at(px,pz)
			if authored_opening and Vector2(px,pz).length() < 34.0:
				result[y*SIZE+x] = preload("res://scripts/opening_terrain.gd").ground_height(px,pz)
				continue
			var gx := mini(x/2,127)
			var gy := mini(y/2,127)
			var u := float(x)*.5-gx
			var v := float(y)*.5-gy
			var strength := lerpf(lerpf(strengths[gy*129+gx],strengths[gy*129+gx+1],u),lerpf(strengths[(gy+1)*129+gx],strengths[(gy+1)*129+gx+1],u),v)
			if strength > 0.0:
				# Bounded, smooth coordinate bends break long grid-aligned banks.
				var wx := (sin(px*.17+pz*.11)+sin(pz*.31-px*.07))*.23*strength
				var wz := (sin(pz*.15-px*.13)+sin(px*.27+pz*.05))*.23*strength
				var sx := clampf((px+wx+128.0)*.5,0.0,127.999)
				var sz := clampf((pz+wz+128.0)*.5,0.0,127.999)
				var ix := floori(sx)
				var iz := floori(sz)
				var bx := weights(sx-ix)
				var bz := weights(sz-iz)
				var smooth_height := 0.0
				for j in range(4):
					for i in range(4): smooth_height += float(layout.heights[clampi(iz+j-1,0,128)*129+clampi(ix+i-1,0,128)])*bx[i]*bz[j]
				# Preserve ridge elevation and basin depth; no overshoot or new cliffs.
				original += clampf(smooth_height-original,-.72,.72)*strength
			result[y*SIZE+x] = original
	return result

static func vertex_color(layout: RefCounted, x: int, y: int) -> Color:
	var result := Color(0,0,0,0)
	for dy in [-1,0]:
		for dx in [-1,0]: result += PALETTE[int(layout.tiles[clampi(y+dy,0,128)*129+clampi(x+dx,0,128)])]*.25
	var biome := Regions.at(Vector3(x*2-128,0,y*2-128))
	if biome == "ice": result = result.lerp(Color("bacbce"),.62)
	elif biome == "swamp": result = result.lerp(Color("415c43"),.3)
	elif biome == "rainforest": result = result.lerp(Color("375d32"),.22)
	return result

static func build(layout: RefCounted) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var palette := PackedColorArray()
	for y in range(129):
		for x in range(129): palette.append(vertex_color(layout,x,y))
	for y in range(SIZE):
		for x in range(SIZE):
			var h: PackedFloat32Array = layout.surface_heights
			vertices.append(Vector3(x-128,h[y*SIZE+x],y-128))
			var dx := h[y*SIZE+mini(x+1,256)]-h[y*SIZE+maxi(x-1,0)]
			var dz := h[mini(y+1,256)*SIZE+x]-h[maxi(y-1,0)*SIZE+x]
			normals.append(Vector3(-dx,2,-dz).normalized())
			var gx := mini(x/2,127)
			var gy := mini(y/2,127)
			var u := float(x)*.5-gx
			var v := float(y)*.5-gy
			colors.append(palette[gy*129+gx].lerp(palette[gy*129+gx+1],u).lerp(palette[(gy+1)*129+gx].lerp(palette[(gy+1)*129+gx+1],u),v))
			if x < 256 and y < 256:
				var i := y*SIZE+x
				indices.append_array(PackedInt32Array([i,i+1,i+SIZE,i+1,i+SIZE+1,i+SIZE]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
