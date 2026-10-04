extends RefCounted
## Local presentation/input preferences; separate from single-run saves and simulation.
const DEFAULTS = {"quality": 2, "fullscreen": true, "vsync": true, "fps": 0, "pan_speed": 1.0, "rotation_speed": 1.0, "zoom_speed": 1.0, "invert_y": false, "route_dots": false, "perspective": true, "impact_motion": true}
const ACTIONS = {
	"pan_up": ["镜头向前", KEY_W], "pan_down": ["镜头向后", KEY_S], "pan_left": ["镜头向左", KEY_A], "pan_right": ["镜头向右", KEY_D],
	"rotate_left": ["镜头左转", KEY_Q], "rotate_right": ["镜头右转", KEY_E], "center": ["回到并跟随角色", KEY_SPACE], "follow": ["切换跟随", KEY_F], "reset_camera": ["重置镜头", KEY_HOME],
	"upgrade": ["升级实验室", KEY_R], "tech": ["科技面板", KEY_T], "heal": ["返回帐篷治疗", KEY_H], "kit": ["使用急救包", KEY_J], "stop": ["停止命令", KEY_X], "journal": ["装备与探索", KEY_L],
	"save": ["手动存档", KEY_F5], "load": ["选择存档", KEY_F9], "guide": ["生存手册", KEY_F1], "settings": ["设置", KEY_F10],
	"build_0": ["建造帐篷", KEY_1], "build_1": ["建造营火", KEY_2], "build_2": ["建造发电站", KEY_3], "build_3": ["建造电栅栏", KEY_4],
	"build_4": ["建造弓箭塔", KEY_5], "build_5": ["建造基础建筑", KEY_6], "build_6": ["建造化石挖掘场", KEY_7], "build_7": ["建造电门", KEY_8],
}
static var file_path := "user://preferences.cfg"
var values: Dictionary = DEFAULTS.duplicate()
var bindings: Dictionary = default_bindings()
var diagnostic := ""

static func default_bindings() -> Dictionary:
	var keys := {}
	for action in ACTIONS: keys[action] = int(ACTIONS[action][1])
	return keys

static func valid_key(code: int) -> bool:
	return (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9) or (code >= KEY_F1 and code <= KEY_F12) or code in [KEY_SPACE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN, KEY_INSERT, KEY_DELETE, KEY_BACKSPACE, KEY_TAB]

static func clean_values(raw: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	for key in DEFAULTS:
		if not raw.has(key): continue
		var value: Variant = raw[key]
		match key:
			"quality":
				if value is int and value in [0, 1, 2]: result[key] = value
			"fps":
				if value is int and value in [0, 30, 60, 120]: result[key] = value
			"pan_speed", "rotation_speed", "zoom_speed":
				if (value is float or value is int) and is_finite(float(value)): result[key] = clampf(float(value), 0.5, 2.0)
			_:
				if value is bool: result[key] = value
	return result

static func valid_bindings(raw: Dictionary) -> bool:
	if raw.size() != ACTIONS.size(): return false
	var used := {}
	for action in ACTIONS:
		if not raw.get(action) is int or not valid_key(raw[action]) or used.has(raw[action]): return false
		used[raw[action]] = true
	return true

func load_file() -> void:
	values = DEFAULTS.duplicate()
	bindings = default_bindings()
	diagnostic = ""
	var file := ConfigFile.new()
	var error := file.load(file_path)
	if error == ERR_FILE_NOT_FOUND: return
	if error != OK:
		diagnostic = "设置文件无法读取，已使用默认设置。"
		return
	var raw: Variant = file.get_value("preferences", "values", {})
	if raw is Dictionary: values = clean_values(raw)
	var keys: Variant = file.get_value("preferences", "bindings", {})
	if keys is Dictionary and valid_bindings(keys): bindings = keys.duplicate()
	else: diagnostic = "键位配置无效，已恢复默认键位。"

func save_file() -> String:
	var file := ConfigFile.new()
	file.set_value("preferences", "values", values)
	file.set_value("preferences", "bindings", bindings)
	if file.save(file_path + ".tmp") != OK: return "无法保存设置，请检查磁盘权限。"
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(file_path + ".tmp"), ProjectSettings.globalize_path(file_path)) != OK: return "无法替换设置文件，原设置仍保留。"
	return ""

func key_name(action: String) -> String:
	var code: int = bindings[action]
	return "空格" if code == KEY_SPACE else OS.get_keycode_string(code)

func matches(event: InputEvent, action: String) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	return code == bindings[action]

func held(action: String) -> bool:
	return Input.is_physical_key_pressed(bindings[action])

func apply(world: Node, display: bool = true) -> void:
	# Only cosmetic nodes and rendering switches: no collision, vision or gameplay changes.
	world.sun.shadow_enabled = values.quality > 0
	RenderingServer.directional_shadow_atlas_set_size(4096 if values.quality == 2 else 2048, true)
	world.get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][values.quality]
	var cover := world.get_node_or_null("Island/GroundCover")
	if cover: cover.visible = values.quality > 0
	# Settings apply while paused too; do not wait for the next simulation tick.
	for b in world.session.buildings:
		if not world.visuals.has(b.id): continue
		var dressing: Node = world.visuals[b.id].get_node_or_null("CampDressing")
		if dressing: dressing.visible = b.remaining <= 0 and values.quality > 0 and (b.kind != "tower" or b.get("refit", "").is_empty())
		preload("res://scripts/camp_detail.gd").update(world.scenery, world.visuals[b.id], b)
	if display and DisplayServer.get_name() != "headless":
		Engine.max_fps = values.fps
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode: DisplayServer.window_set_mode(mode)
