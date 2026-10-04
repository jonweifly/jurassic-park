extends RefCounted
## Copy presentation settings after the application name changes; old-map saves remain separate.
const LEGACY_NAME := "侏罗纪公园 · 生存营地"

static func copy_legacy_data() -> void:
	var target := ProjectSettings.globalize_path("user://").trim_suffix("/")
	var source := target.get_base_dir().path_join(LEGACY_NAME)
	if not DirAccess.dir_exists_absolute(source): return
	for name in ["preferences.cfg", "audio.cfg"]:
		copy_missing(source.path_join(name), target.path_join(name))

static func copy_missing(source: String, target: String) -> void:
	if not FileAccess.file_exists(source) or FileAccess.file_exists(target): return
	if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK: return
	DirAccess.copy_absolute(source, target)
