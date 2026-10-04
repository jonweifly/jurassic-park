extends SceneTree
const EventBus = preload("res://scripts/game_event_bus.gd")
var checks := 0
var failures := 0
var received: Array = []

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func receive(payload: Dictionary) -> void:
	received.append(payload)

func _initialize() -> void:
	var bus = EventBus.new()
	var callback := Callable(self, "receive")
	bus.subscribe("building_created", callback)
	bus.emit("building_created", {"id": 7, "kind": "tent"})
	expect(received.size() == 1 and received[0].id == 7, "Event payload reaches subscribers")
	bus.unsubscribe("building_created", callback)
	bus.emit("building_created", {"id": 8})
	expect(received.size() == 1, "Unsubscribed callbacks do not receive events")
	bus.clear()
	print("EVENT BUS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
