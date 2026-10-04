extends SceneTree
const Save = preload("res://scripts/save_store.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	expect(FileAccess.file_exists("res://data/maps/organic_island_v3.json"), "Only playable island data is exported")
	expect(not FileAccess.file_exists("res://data/terrain.json"), "Old map terrain data is removed")
	expect(ResourceLoader.exists("res://scenes/original_island.tscn"), "Original island scene is exported")
	expect(not ResourceLoader.exists("res://scenes/reference_island.tscn"), "Old map scene is removed")
	Save.directory = "user://export_smoke_%d" % Time.get_ticks_usec()
	var world: Node = load("res://scenes/main.tscn").instantiate()
	world.persistence_enabled = false
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.start_session(1500.0, "standard")
	world.session.wood = 43
	var error: String = Save.write(world)
	expect(error.is_empty(), "Exported game can write a save: " + error)
	var saved: Dictionary = Save.latest()
	expect(saved.has("data") and saved.data.session.wood == 43, "Exported game can read its save")
	var folder := DirAccess.open(Save.directory)
	if folder:
		for file in folder.get_files(): folder.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.directory))
	print("EXPORT SMOKE: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
