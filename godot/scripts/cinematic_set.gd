extends RefCounted
## Reproducible native set dressing for the isolated visual study.
## Run tools/build_cinematic_set.gd to bake an editable PackedScene.
const FoliageShader = preload("res://shaders/cinematic_foliage.gdshader")
var rng := RandomNumberGenerator.new()
var root: Node3D
var mats := {}
var foliage: ShaderMaterial
var terrain_noise := FastNoiseLite.new()

func build() -> Node3D:
	rng.seed = 27092026
	terrain_noise.seed = 701
	terrain_noise.frequency = .055
	root = Node3D.new()
	root.name = "RainforestSet"
	foliage = ShaderMaterial.new()
	foliage.shader = FoliageShader
	foliage.resource_name = "CinematicFoliage"
	mats.steel = mat("Steel", Color("394643"), .57, .7)
	mats.concrete = mat("Concrete", Color("74796b"), .95)
	mats.dark = mat("DarkMetal", Color("202d2b"), .59, .6)
	mats.ceramic = mat("Ceramic", Color("9ba194"), .36)
	mats.amber = mat("SafetyPaint", Color("b08038"), .68, .1)
	mats.rubber = mat("Rubber", Color("17211e"), .89)
	ground()
	structures()
	forest()
	understory()
	props()
	return root

func mat(label: String, color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "Cinematic" + label
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

func elevation(x: float, z: float) -> float:
	var edge := smoothstep(14.0, 44.0, absf(x))
	return terrain_noise.get_noise_2d(x,z)*(.16 + edge*4.0) + .06

func group(label: String) -> Node3D:
	var n := Node3D.new()
	n.name = label
	root.add_child(n)
	return n

func mesh_node(parent: Node3D, label: String, mesh: Mesh, p: Vector3, material: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = label
	n.mesh = mesh
	n.position = p
	n.material_override = material
	parent.add_child(n)
	return n

func box(parent: Node3D, label: String, p: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh_node(parent,label,mesh,p,material)

func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 8
	var n := mesh_node(parent,"Cable",mesh,(a+b)*.5,material)
	var y := (b-a).normalized()
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < .95 else Vector3.FORWARD
	var x := y.cross(ref).normalized()
	n.basis = Basis(x,y,x.cross(y).normalized())
	return n

func asset(parent: Node3D, path: String, label: String, p: Vector3, scale_value: float = 1.0, yaw: float = 0.0) -> Node3D:
	var n: Node3D = load(path).instantiate()
	n.name = label
	n.position = p
	n.rotation.y = yaw
	n.scale = Vector3.ONE*scale_value
	parent.add_child(n)
	return n

func ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-48,48):
		for x in range(-48,48):
			for o in [Vector2(0,0),Vector2(1,1),Vector2(0,1),Vector2(0,0),Vector2(1,0),Vector2(1,1)]:
				var xx: float = x+o.x
				var zz: float = z+o.y
				st.set_uv(Vector2(xx,zz))
				st.add_vertex(Vector3(xx,elevation(xx,zz),zz))
	st.generate_normals()
	st.generate_tangents()
	var material := ShaderMaterial.new()
	material.resource_name = "CinematicGround"
	material.shader = load("res://shaders/cinematic_ground.gdshader")
	material.set_shader_parameter("soil_map",load("res://assets/materials/camp_soil.png"))
	material.set_shader_parameter("litter_map",load("res://assets/materials/forest_floor.png"))
	material.set_shader_parameter("rock_map",load("res://assets/materials/terrain/rock.png"))
	mesh_node(root,"Ground",st.commit(),Vector3.ZERO,material)
	var puddles := group("Puddles")
	var water := ShaderMaterial.new()
	water.resource_name = "CinematicWater"
	water.shader = load("res://shaders/cinematic_water.gdshader")
	for i in range(12):
		var p := Vector3(rng.randf_range(-2.0,2.0),0,rng.randf_range(-15,19))
		var radius := rng.randf_range(.45,1.1)
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(32):
			for k in [-1,j,j+1]:
				var a: float = k*TAU/32
				var r: float = 0.0 if k < 0 else radius*(1.0+.15*sin(a*5.0+i))
				var x: float = p.x+cos(a)*r
				var z: float = p.z+sin(a)*r*.54
				s.set_uv(Vector2(x,z))
				s.add_vertex(Vector3(x,elevation(x,z)+.018,z))
		s.generate_normals()
		s.generate_tangents()
		mesh_node(puddles,"Puddle",s.commit(),Vector3.ZERO,water)

func structures() -> void:
	var g := group("Structures")
	asset(g,"res://assets/cinematic/security_gate.glb","SecurityGate",Vector3(0,elevation(0,-2),-2))
	asset(g,"res://assets/cinematic/diesel_generator.glb","Generator",Vector3(-6.0,elevation(-6.0,5.0),5.0),1,-.18)
	asset(g,"res://assets/cinematic/service_cabin.glb","FieldStation",Vector3(-10.5,elevation(-10.5,-.6),-.6),1,.20)
	var fence := group("ElectricFence")
	for side: int in [-1,1]:
		var last := float(side)*3.5
		for i in range(1,7):
			var x := side*(3.5+i*3.1)
			var y := elevation(x,-2)
			box(fence,"Footing",Vector3(x,y+.14,-2),Vector3(.62,.28,.7),mats.concrete)
			box(fence,"FenceWeb",Vector3(x,y+1.85,-2),Vector3(.10,3.4,.25),mats.steel)
			for z in [-2.13,-1.87]: box(fence,"FenceFlange",Vector3(x,y+1.85,z),Vector3(.25,3.4,.035),mats.steel)
			rod(fence,Vector3(x,y+3.53,-2),Vector3(x,y+4.06,-2.37),.04,mats.steel)
			for h in [.65,1.2,1.75,2.3,2.85,3.4,3.94]:
				var z := -2.33 if h > 3.5 else -1.81
				box(fence,"Insulator",Vector3(x,y+h,z),Vector3(.15,.10,.12),mats.ceramic)
				rod(fence,Vector3(last,elevation(last,-2)+h,z),Vector3(x,y+h,z),.011,mats.steel)
			if i%2 == 1:
				rod(fence,Vector3(x,y+2.7,-2.04),Vector3(x-side*.85,y+.07,-3.0),.033,mats.dark)
				box(fence,"WarningPlate",Vector3(x,y+1.94,-1.7),Vector3(.48,.32,.04),mats.amber)
			last = x
	# The canopy follows the pole structure rather than floating over the generator.
	for x in [-8.25,-3.8]:
		for z in [3.25,6.7]:
			box(g,"GeneratorAwningPost",Vector3(x,1.8,z),Vector3(.09,3.6,.09),mats.dark)
	box(g,"GeneratorAwning",Vector3(-6.02,3.61,4.99),Vector3(4.85,.12,4.04),mats.steel)
	for z in [3.2,6.76]: box(g,"AwningBeam",Vector3(-6.02,3.45,z),Vector3(4.8,.20,.12),mats.dark)
	for i in range(20): box(g,"AwningSeam",Vector3(-8.35+i*.245,3.69,4.99),Vector3(.022,.04,4),mats.dark)
	# Service cable follows the ground to the electric gate.
	for i in range(24):
		var a := Vector3(-4.9+i*.07,0,4.5-i*.27)
		var b := Vector3(-4.9+(i+1)*.07,0,4.5-(i+1)*.27)
		a.y = elevation(a.x,a.z)+.055
		b.y = elevation(b.x,b.z)+.055
		rod(g,a,b,.022,mats.rubber)

func multimesh_asset(path: String, label: String, positions: Array[Transform3D], material: Material = null) -> void:
	var source: Node3D = load(path).instantiate()
	var nodes := source.find_children("*","MeshInstance3D",true,false)
	var parent := group(label)
	for part: MeshInstance3D in nodes:
		var local: Transform3D = part.transform
		var ancestor := part.get_parent()
		while ancestor != source and ancestor is Node3D:
			local = ancestor.transform*local
			ancestor = ancestor.get_parent()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part.mesh
		mm.instance_count = positions.size()
		for i in range(positions.size()): mm.set_instance_transform(i,positions[i]*local)
		var n := MultiMeshInstance3D.new()
		n.name = part.name
		n.multimesh = mm
		if material:
			if material == foliage and not (part.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR):
				var colored := foliage.duplicate() as ShaderMaterial
				var original := part.get_active_material(0) as StandardMaterial3D
				colored.set_shader_parameter("base_tint",original.albedo_color if original else Color("415330"))
				n.material_override = colored
			else:
				n.material_override = material
		elif "Foliage" in str(part.name) or "Crown" in str(part.name):
			n.material_override = foliage
		parent.add_child(n)
	source.free()

func forest() -> void:
	var near: Array[Transform3D] = []
	var far: Array[Transform3D] = []
	for i in range(105):
		var x := rng.randf_range(-44,44)
		var z := rng.randf_range(-45,20)
		# Preserve the station sight line and the entire playable apron.
		if z > -18 and absf(x) < 17: continue
		if x > 12 and z > 4 and x < 27: continue
		var size := rng.randf_range(.88,1.44)
		var at := Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size),Vector3(x,elevation(x,z),z))
		if z > -28 and near.size() < 22: near.append(at)
		else:
			at.basis = at.basis.scaled(Vector3.ONE*1.4)
			far.append(at)
	multimesh_asset("res://assets/cinematic/rainforest_canopy.glb","CanopyTrees",near)
	multimesh_asset("res://assets/cinematic/rainforest_canopy.glb","BackgroundTrees",far)
	var palms: Array[Transform3D] = []
	for p in [Vector3(-20,0,8),Vector3(23,0,-14),Vector3(-18,0,-8),Vector3(11,0,-25),Vector3(-9,0,-23)]:
		p.y = elevation(p.x,p.z)
		palms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*1.65),p))
	multimesh_asset("res://assets/models/palm_tree.glb","Palms",palms)

func understory() -> void:
	var ferns: Array[Transform3D] = []
	for i in range(730):
		var x := rng.randf_range(-34,34)
		var z := rng.randf_range(-34,23)
		if absf(x-sin(z*.12)*1.4) < 3.8 and z > -16: continue
		if x > -13 and x < -2.7 and z > -3 and z < 8: continue
		if x > 2.5 and x < 10.5 and z > -13 and z < -4: continue
		var size := rng.randf_range(.7,1.9)
		ferns.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size),Vector3(x,elevation(x,z),z)))
	multimesh_asset("res://assets/cinematic/rainforest_fern.glb","Ferns",ferns,foliage)
	# Curved grass blades, densely clumped outside the maintenance road.
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(9):
		var a := i*2.399
		var d := Vector3(cos(a),0,sin(a))
		var r := Vector3(-sin(a),0,cos(a))
		var h := .36+(i%4)*.1
		for j in range(4):
			var f := j/4.0
			var g := (j+1)/4.0
			var p := Vector3.UP*f*h + d*f*f*.22
			var q := Vector3.UP*g*h + d*g*g*.22
			var w := .022*(1-f)
			var v := .022*(1-g)
			for point: Vector3 in [p-r*w,q-r*v,q+r*v,p-r*w,q+r*v,p+r*w]:
				s.set_color(Color("35472b").lerp(Color("8a8b56"),point.y/h*.5))
				s.set_uv(Vector2(point.y/h,0.5))
				s.add_vertex(point)
	s.generate_normals()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = s.commit()
	var positions: Array[Transform3D] = []
	for i in range(7500):
		var x := rng.randf_range(-37,37)
		var z := rng.randf_range(-36,27)
		if absf(x-sin(z*.12)*1.4) < 3.7: continue
		if x > -13 and x < -2.7 and z > -3 and z < 8: continue
		if terrain_noise.get_noise_2d(x*7,z*7) < -.1: continue
		var sc := rng.randf_range(.6,1.25)
		positions.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*sc),Vector3(x,elevation(x,z),z)))
	mm.instance_count = positions.size()
	for i in range(positions.size()): mm.set_instance_transform(i,positions[i])
	var n := MultiMeshInstance3D.new()
	n.name = "GrassClumps"
	n.multimesh = mm
	n.material_override = foliage
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(n)

func props() -> void:
	var rocks: Array[Transform3D] = []
	for i in range(60):
		var x := rng.randf_range(-30,30)
		var z := rng.randf_range(-28,20)
		if absf(x) < 12 and z > -14: continue
		var sc := rng.randf_range(.5,2.4)
		rocks.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(sc,sc*.68,sc)),Vector3(x,elevation(x,z)-.10,z)))
	var rock_mat := mat("Rock",Color("798174"),.97)
	rock_mat.albedo_texture = load("res://assets/materials/terrain/rock.png")
	rock_mat.uv1_triplanar = true
	rock_mat.uv1_scale = Vector3.ONE*1.5
	multimesh_asset("res://assets/models/rock.glb","Rocks",rocks,rock_mat)
	var g := group("ServiceProps")
	asset(g,"res://assets/models/generator_dressing.glb","FuelAndCables",Vector3(-9.1,.05,5.1),1.35)
	asset(g,"res://assets/models/tent_dressing.glb","SupplyCrates",Vector3(-9.6,.10,2.2),1.7,.25)
	for x in [-2.8,2.8]:
		for z in [2.5,7.5,12.5]:
			box(g,"RoadsideMarker",Vector3(x,.38,z),Vector3(.09,.70,.09),mats.dark)
			box(g,"Reflector",Vector3(x,.62,z+.048),Vector3(.075,.12,.013),mats.amber)
