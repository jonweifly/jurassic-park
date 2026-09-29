extends SceneTree
## Geometry/feedback contracts only. Construction and combat remain owned by Session.
const Detail = preload("res://scripts/camp_detail.gd")
const Tower = preload("res://scripts/tower_visuals.gd")
var checks := 0
var failures := 0

class VisionStub extends RefCounted:
	func shade(_node: Node) -> void: pass

class SessionStub extends RefCounted:
	var electricity := 10
	func supply() -> int: return electricity
	func demand() -> int: return 3

class PreferencesStub extends RefCounted:
	var values := {"quality": 1}

class WorldStub extends Node:
	var vision := VisionStub.new()
	var session := SessionStub.new()
	var preferences := PreferencesStub.new()
	var paused := false
	var miners: Array[Node3D] = []
	func survivors() -> Array[Node3D]: return miners

class SceneryStub extends RefCounted:
	var world: Node
	var clock := 0.0

class MinerStub extends Node3D:
	var work_state := "mine"
	var work_timeout := .15

func _initialize() -> void: call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var world := WorldStub.new()
	root.add_child(world)
	var scenery := SceneryStub.new()
	scenery.world = world
	for kind in ["tent", "fire", "fossil", "tower", "lab", "laboratory"]:
		var building := Node3D.new()
		world.add_child(building)
		Detail.prepare(scenery, building, kind)
		var detail: Node3D = building.get_node("CampDetail")
		var count := detail.get_child_count()
		Detail.prepare(scenery, building, kind)
		expect(building.get_child_count() == 1 and detail.get_child_count() == count, "Preparation is idempotent: " + kind)
		var structure: MeshInstance3D = detail.get_node("Structure")
		expect(structure.mesh.get_surface_count() == 1, "Static building accents share one draw surface: " + kind)
		var aabb := structure.mesh.get_aabb()
		expect(aabb.position.x >= -1.0 and aabb.end.x <= 1.0 and aabb.position.z >= -1.0 and aabb.end.z <= 1.0, "Detail fits the existing construction footprint: " + kind)
		var b := {"kind": kind, "hp": Detail.Catalog.BUILDINGS[kind].hp, "remaining": 5.0}
		Detail.update(scenery, building, b)
		expect(not detail.visible, "Unfinished buildings do not show complete mechanisms: " + kind)
		b.remaining = 0
		Detail.update(scenery, building, b)
		expect(detail.visible and detail.get_child_count() == count, "Updates reuse existing detail nodes: " + kind)
		if kind in ["tent", "tower", "lab", "laboratory"]:
			b.hp = 5
			Detail.update(scenery, building, b)
			expect(detail.get_node("DamageSmoke").emitting and detail.get_meta("lamp_state") == 2, "Critical damage is visible: " + kind)
			world.paused = true
			Detail.update(scenery, building, b)
			expect(not detail.get_node("DamageSmoke").emitting, "Paused game stops new damage smoke: " + kind)
			world.paused = false
			b.hp = Detail.Catalog.BUILDINGS[kind].hp
			world.session.electricity = 0
			Detail.update(scenery, building, b)
			expect(detail.get_meta("lamp_state") == (1 if kind == "tent" else 0), "Lamp distinguishes shelter from powered machinery: " + kind)
			world.session.electricity = 10
		if kind == "tower":
			b.refit = "heavy"
			Detail.update(scenery, building, b)
			expect(not structure.visible, "Specialist tower does not inherit conflicting base supports")
		if kind == "fossil":
			var miner := MinerStub.new()
			world.add_child(miner)
			world.miners.append(miner)
			var old_height: float = detail.get_node("Bucket").position.y
			scenery.clock += .1
			Detail.update(scenery, building, b)
			expect(not is_equal_approx(old_height, detail.get_node("Bucket").position.y), "Mining animates the excavation winch and basket")
			miner.work_timeout = 0
			var phase: float = detail.get_meta("winch_phase")
			scenery.clock += .1
			Detail.update(scenery, building, b)
			expect(is_equal_approx(phase, detail.get_meta("winch_phase")), "Idle excavation does not keep winding")
			world.miners.clear()
			miner.free()
		if kind == "lab":
			var fan: Node3D = detail.get_node("Ventilator")
			scenery.clock += .1
			Detail.update(scenery, building, b)
			expect(not is_zero_approx(fan.rotation.y), "Powered laboratory ventilates")
			world.session.electricity = 0
			var yaw := fan.rotation.y
			scenery.clock += .1
			Detail.update(scenery, building, b)
			expect(is_equal_approx(yaw, fan.rotation.y), "Unpowered laboratory fan stops")
			world.session.electricity = 10
		building.free()
	var tower := Node3D.new()
	var model: Node3D = load("res://assets/models/tower.glb").instantiate()
	model.name = "Model"
	tower.add_child(model)
	world.add_child(tower)
	var gun: Node3D = tower.get_node("Model/Gun")
	var weapon: Node3D = gun.get_child(0)
	var transform := weapon.global_transform
	Tower.ensure_recoil(tower)
	expect(weapon.global_transform.is_equal_approx(transform), "Installing basic tower recoil preserves the mesh transform")
	Tower.ensure_recoil(tower)
	expect(gun.get_child_count() == 1 and gun.has_node("Recoil/Muzzle"), "Basic tower gets one reusable articulated recoil root")
	Tower.fire(tower, scenery.clock)
	Tower.update(scenery, tower, {"kind": "tower", "remaining": 0.0})
	expect(gun.get_node("Recoil").position.z < 0 and gun.get_node("Recoil").rotation.x > 0, "Basic tower firing has recoil and lift")
	scenery.clock += .3
	Tower.update(scenery, tower, {"kind": "tower", "remaining": 0.0})
	expect(gun.get_node("Recoil").position.is_zero_approx() and gun.get_node("Recoil").rotation.is_zero_approx(), "Weapon fully settles after the shot")
	world.free()
	print("CAMP DETAIL: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
