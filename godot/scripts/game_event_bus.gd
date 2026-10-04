extends RefCounted
class_name GameEventBus
## Small synchronous event bus for gameplay-to-presentation boundaries.
## Payloads are dictionaries so events remain data-only and save/network friendly.

var _listeners: Dictionary = {}

func subscribe(event_name: String, callback: Callable) -> void:
	if not callback.is_valid(): return
	var listeners: Array = _listeners.get(event_name, [])
	listeners.append(callback)
	_listeners[event_name] = listeners

func unsubscribe(event_name: String, callback: Callable) -> void:
	if not _listeners.has(event_name): return
	var listeners: Array = _listeners[event_name]
	listeners = listeners.filter(func(item): return item != callback)
	if listeners.is_empty():
		_listeners.erase(event_name)
	else:
		_listeners[event_name] = listeners

func emit(event_name: String, payload: Dictionary = {}) -> void:
	for callback in _listeners.get(event_name, []).duplicate():
		if callback is Callable and callback.is_valid(): callback.call(payload)

func clear() -> void:
	_listeners.clear()
