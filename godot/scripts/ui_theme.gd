extends RefCounted
## Shared forest-green surfaces for standard controls, menus and embedded dialogs.
static func surface(fill: String, border: String = "526357", padding: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(6)
	style.set_content_margin_all(padding)
	style.shadow_color = Color(0, 0, 0, 0.34)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	return style

static func make(font: Font) -> Theme:
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	for type in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "PopupMenu", "TabBar", "Window"]:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_selected_color", "title_color"]:
			theme.set_color(state, type, Color("eef0d9"))
		theme.set_color("font_disabled_color", type, Color("73857a"))
	for type in ["Button", "OptionButton", "LineEdit"]:
		for state in ["normal", "hover", "pressed", "disabled", "read_only"]:
			var fill := "294437" if state == "hover" else "10231b" if state == "pressed" else "1c3429" if state == "normal" else "101b16"
			var border := "d8b66d" if state == "hover" else "6c8168" if state == "normal" else "334b3d"
			theme.set_stylebox(state, type, surface(fill, border, 8))
		theme.set_stylebox("focus", type, surface("1c3429", "e2bd70", 8))
	for type in ["AcceptDialog", "PopupMenu", "PopupPanel", "PanelContainer", "TabContainer", "TooltipPanel"]:
		theme.set_stylebox("panel", type, surface("101f19", "526b58"))
	theme.set_stylebox("hover", "PopupMenu", surface("294437", "d8b66d", 6))
	theme.set_constant("v_separation", "PopupMenu", 12)
	var border := surface("101f19", "526b58")
	border.expand_margin_top = 32
	theme.set_stylebox("embedded_border", "Window", border)
	theme.set_stylebox("embedded_unfocused_border", "Window", border)
	theme.set_color("title_color", "Window", Color("e2bd70"))
	for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
		for type in ["TabBar", "TabContainer"]:
			theme.set_stylebox(state,type,surface("294437" if state == "tab_selected" else "10231b", "526b58"))
	return theme
