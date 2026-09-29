extends RefCounted
## Synchronous compatibility boundary for the existing single-survivor actions.
## Never await, emit frame callbacks, or run global simulation inside run().
## Only per-player fields are scoped; the board, economy and AI remain shared.
const FIELDS := ["hero", "worker", "order", "order_target", "hero_route_revision", "selected_id", "build_mode", "build_rotation", "destination", "build_access"]
var state := {}
var world: Node

func _init(owner_world: Node, pawn: Node3D) -> void:
	world = owner_world
	state = {"hero": pawn, "worker": world.Worker.new(world), "order": "idle", "order_target": pawn.position,
		"hero_route_revision": -1, "selected_id": -1, "build_mode": "", "build_rotation": 0.0,
		"destination": world.ring(.42,Color("86c5ee")), "build_access": world.BuildAccess.new(world)}
	state.destination.hide()

func run(action: Callable) -> Variant:
	var local := {}
	for field in FIELDS:
		local[field] = world.get(field)
		world.set(field,state[field])
	var pointer: Control = world.pointer_feedback
	world.pointer_feedback = null
	world.coop.acting_slot = 2
	var result: Variant = action.call()
	for field in FIELDS:
		state[field] = world.get(field)
		world.set(field,local[field])
	world.pointer_feedback = pointer
	world.coop.acting_slot = 1
	return result

func tick(dt: float) -> void:
	run(func():
		world.hero.advance(dt)
		world.hero.position.y = world.board.layout.height_at(world.hero.position.x,world.hero.position.z)
		if world.hero.health <= 0: return
		world.update_order(dt)
		world.worker.update(dt)
		world.outfitting.tick_actor(dt))
