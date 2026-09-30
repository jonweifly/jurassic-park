extends RefCounted
## Shared forest-green surfaces for standard controls, menus and embedded dialogs.
static func surface(fill: String, border: String = "526357", padding: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(padding)
	return style

static func make(font: Font) -> Theme:
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	for type in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "PopupMenu", "TabBar", "Window"]:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_selected_color", "title_color"]:
			theme.set_color(state, type, Color("e7e4cc"))
		theme.set_color("font_disabled_color", type, Color("819489"))
	for type in ["Button", "OptionButton", "LineEdit"]:
		for state in ["normal", "hover", "pressed", "disabled", "read_only"]:
			theme.set_stylebox(state, type, surface("354d3e" if state == "hover" else "172b24" if state == "pressed" else "23392f", "b5a477" if state == "hover" else "475e4e", 8))
		theme.set_stylebox("focus", type, surface("23392f", "d8c38d", 8))
	for type in ["AcceptDialog", "PopupMenu", "PopupPanel", "PanelContainer", "TabContainer", "TooltipPanel"]:
		theme.set_stylebox("panel", type, surface("14291f"))
	theme.set_stylebox("hover", "PopupMenu", surface("354d3e", "b5a477", 6))
	theme.set_constant("v_separation", "PopupMenu", 12)
	var border := surface("14291f")
	border.expand_margin_top = 32
	theme.set_stylebox("embedded_border", "Window", border)
	theme.set_stylebox("embedded_unfocused_border", "Window", border)
	theme.set_color("title_color", "Window", Color("d8c38d"))
	for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
		for type in ["TabBar", "TabContainer"]:
			theme.set_stylebox(state,type,surface("354d3e" if state == "tab_selected" else "172b24"))
	return theme
