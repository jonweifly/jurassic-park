extends RefCounted
## Presentation masks only. Never modifies map, routes, visibility or gameplay RNG.
const SIZE := 256
var world: Node
var texture: ImageTexture
var image: Image
var forest_image: Image
var last_trees := -1
var last_buildings := ""

func _init(owner_world: Node) -> void:
	world = owner_world
	texture = ImageTexture.create_from_image(Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8))
	update()

func stamp(image: Image, at: Vector3, radius: float, channel: int, amount: float) -> void:
	var center := Vector2(at.x + 128, at.z + 128)
	for y in range(maxi(0, floori(center.y-radius)), mini(SIZE, ceili(center.y+radius))):
		for x in range(maxi(0, floori(center.x-radius)), mini(SIZE, ceili(center.x+radius))):
			var strength := (1.0-smoothstep(radius*.3,radius,Vector2(x+.5,y+.5).distance_to(center)))*amount
			var value := image.get_pixel(x,y)
			value[channel] = maxf(value[channel], strength)
			image.set_pixel(x,y,value)

func update() -> void:
	var key := ""
	for b in world.session.buildings:
		if b.hp > 0: key += "%d," % b.id
	if last_trees == world.trees.size() and last_buildings == key: return
	if last_trees != world.trees.size():
		forest_image = Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
		forest_image.fill(Color(0,0,0,1))
		for cell in world.trees: stamp(forest_image,world.board.point(cell),3.8,1,.9)
		last_trees = world.trees.size()
	image = forest_image.duplicate() as Image
	for b in world.session.buildings:
		if b.hp <= 0: continue
		var radius := 2.0 if b.kind in ["gate","shelter"] else 3.0
		stamp(image,world.board.point(b.cell),radius,0,1.0)
	texture.update(image)
	last_buildings = key
