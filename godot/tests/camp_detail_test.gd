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
	for kind in ["tent", "fire", "fossil", "tower", "generator", "shelter", "gate", "lab", "laboratory"]:
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
		var joinery: MeshInstance3D = detail.get_node("Joinery")
		expect(joinery.mesh.get_surface_count() == 1 and joinery.mesh.surface_get_array_index_len(0) < 9000, "Close details have one surface and a bounded triangle budget: " + kind)
		var near_aabb := joinery.mesh.get_aabb()
		expect(near_aabb.position.x >= -1.0 and near_aabb.end.x <= 1.0 and near_aabb.position.z >= -1.0 and near_aabb.end.z <= 1.0, "Joinery stays inside the existing footprint: " + kind)
		expect(joinery.visibility_range_end == 38.0 and detail.find_children("*", "CollisionObject3D", true, false).is_empty(), "Close details cull with distance and never block units: " + kind)
		var b := {"kind": kind, "hp": Detail.Catalog.BUILDINGS[kind].hp, "remaining": 5.0}
		Detail.update(scenery, building, b)
		expect(not detail.visible, "Unfinished buildings do not show complete mechanisms: " + kind)
		b.remaining = 0
		Detail.update(scenery, building, b)
		expect(detail.visible and detail.get_child_count() == count, "Updates reuse existing detail nodes: " + kind)
		world.preferences.values.quality = 0
		Detail.update(scenery, building, b)
		expect(not joinery.visible and structure.visible, "Low quality retains silhouette and hides close detail: " + kind)
		world.preferences.values.quality = 2
		Detail.update(scenery, building, b)
		expect(joinery.visible, "High quality restores close detail without rebuilding: " + kind)
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
			var lamp_light: OmniLight3D = detail.get_node("LampLight")
			expect(lamp_light.visible == (kind == "tent") and (kind == "tent" or is_zero_approx(lamp_light.light_energy)), "Unpowered machinery never leaves an invisible lamp illuminating the ground: " + kind)
			world.session.electricity = 10
		if kind == "tower":
			b.refit = "heavy"
			Detail.update(scenery, building, b)
			expect(not structure.visible, "Specialist tower does not inherit conflicting base supports")
			expect(not joinery.visible, "Specialist tower does not inherit conflicting ladders")
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
		if kind == "generator":
			var wheel: Node3D = detail.get_node("Flywheel")
			var wheel_rotation := wheel.rotation.x
			scenery.clock += .1
			Detail.update(scenery, building, b)
			expect(not is_equal_approx(wheel_rotation, wheel.rotation.x), "Healthy generator flywheel turns")
			world.session.electricity = 0
			wheel_rotation = wheel.rotation.x
			scenery.clock += .1
			Detail.update(scenery, building, b)
			expect(not is_equal_approx(wheel_rotation, wheel.rotation.x), "Generator keeps running when camp demand exceeds supply")
			b.hp = 0
			var stopped_rotation := wheel.rotation.x
			scenery.clock += .1
			Detail.update(scenery, building, b)
			expect(is_equal_approx(stopped_rotation, wheel.rotation.x), "Destroyed generator flywheel stops")
			world.session.electricity = 10
		if kind in ["shelter", "gate"]:
			expect(detail.has_node("PowerBeacon") and detail.find_children("PowerBeacon*", "MeshInstance3D", true, false).size() == 2, "Powered barrier has two readable beacons: " + kind)
			Detail.update(scenery, building, b)
			expect(detail.get_node("PowerBeacon").visible, "Powered barrier beacon is visible: " + kind)
			world.session.electricity = 0
			Detail.update(scenery, building, b)
			expect(not detail.get_node("PowerBeacon").visible, "Unpowered barrier beacon is dark: " + kind)
			world.session.electricity = 10
			if kind == "gate":
				var passage_clear := true
				for mesh_node in [structure, joinery]:
					for vertex in mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
						if absf(vertex.x) < .5: passage_clear = false
				expect(passage_clear, "Fixed gate accents stay on the posts and leave the center passage clear")
				b.open = true
				Detail.update(scenery, building, b)
				expect(not detail.get_node("PowerBeacon").visible, "Open gate stops its power beacon: " + kind)
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
