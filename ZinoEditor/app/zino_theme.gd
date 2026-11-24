class_name ZinoTheme
extends RefCounted
## The Zino Editor theme, in the style of macOS: system font, system-blue accent, rounded
## controls, soft sidebars and segmented tabs, with Light and Dark appearances.
## Colours are static vars so `apply_appearance` can switch them before the UI is (re)built.

static var dark := true
static var BG := Color("1e1e1e")
static var BG_2 := Color("252527")       # sidebars / bars
static var PANEL := Color("2b2b2d")      # content panels
static var PANEL_2 := Color("3a3a3c")    # controls
static var BORDER := Color("3d3d40")
static var TEXT := Color("f5f5f7")
static var TEXT_DIM := Color("98989d")
static var ACCENT := Color("0a84ff")     # systemBlue
static var ACCENT_2 := Color("5e5ce6")   # systemIndigo
static var OK := Color("30d158")
static var WARN := Color("ff9f0a")
static var ERROR := Color("ff453a")
static var INFO := Color("64d2ff")
static var SELECTION := Color("0a84ff")

## appearance: "dark", "light" or "system".
static func apply_appearance(appearance: String) -> void:
	dark = DisplayServer.is_dark_mode() if appearance == "system" else appearance != "light"
	if dark:
		BG = Color("1e1e1e"); BG_2 = Color("252527"); PANEL = Color("2b2b2d"); PANEL_2 = Color("3a3a3c")
		BORDER = Color("3d3d40"); TEXT = Color("f5f5f7"); TEXT_DIM = Color("98989d")
		ACCENT = Color("0a84ff"); ACCENT_2 = Color("5e5ce6"); OK = Color("30d158"); WARN = Color("ff9f0a")
		ERROR = Color("ff453a"); INFO = Color("64d2ff"); SELECTION = Color("0a84ff")
	else:
		BG = Color("f5f5f7"); BG_2 = Color("e8e8ed"); PANEL = Color("ffffff"); PANEL_2 = Color("ffffff")
		BORDER = Color("d1d1d6"); TEXT = Color("1d1d1f"); TEXT_DIM = Color("6e6e73")
		ACCENT = Color("007aff"); ACCENT_2 = Color("5856d6"); OK = Color("248a3d"); WARN = Color("c93400")
		ERROR = Color("d70015"); INFO = Color("0071a4"); SELECTION = Color("007aff")

## A system colour adapted to the current appearance (blue, green, orange, red, yellow, purple, teal, gray).
static func tint(name: String) -> Color:
	var d := {"blue": "0a84ff", "green": "30d158", "orange": "ff9f0a", "red": "ff453a", "yellow": "ffd60a", "purple": "bf5af2", "teal": "64d2ff", "pink": "ff375f", "gray": "98989d"}
	var l := {"blue": "007aff", "green": "248a3d", "orange": "c93400", "red": "d70015", "yellow": "a05a00", "purple": "8944ab", "teal": "0071a4", "pink": "d30f45", "gray": "6e6e73"}
	return Color((d if dark else l).get(name, "98989d"))

static func box(color: Color, radius: int = 6, border: Color = Color.TRANSPARENT, border_w: int = 0, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.55
	s.content_margin_bottom = pad * 0.55
	s.anti_aliasing = true
	s.corner_detail = 10
	return s

static func _shadowed(s: StyleBoxFlat, size: int = 6) -> StyleBoxFlat:
	s.shadow_color = Color(0, 0, 0, 0.35 if dark else 0.12)
	s.shadow_size = size
	s.shadow_offset = Vector2(0, 2)
	return s

static func font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["SF Pro Text", "SF Pro Display", "Segoe UI Variable Text", "Segoe UI Variable", "Segoe UI", "Helvetica Neue", "Arial"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_LCD if dark else TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 13
	var control_bg := PANEL_2 if dark else Color.WHITE
	var hover_bg := control_bg.lightened(0.06) if dark else Color("f2f2f7")
	for c in ["Label", "Button", "CheckBox", "CheckButton", "OptionButton", "MenuButton", "LinkButton", "ItemList", "Tree", "TabBar", "PopupMenu", "MenuBar", "LineEdit", "TextEdit", "RichTextLabel", "SpinBox", "GraphNode", "GraphEdit"]:
		t.set_color("font_color", c, TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "Panel", box(PANEL, 0, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 0, Color.TRANSPARENT, 0, 0))

	# Push buttons: subtle filled controls with a hairline border, blue when pressed / toggled.
	t.set_stylebox("normal", "Button", box(control_bg, 6, BORDER, 1, 10))
	t.set_stylebox("hover", "Button", box(hover_bg, 6, BORDER, 1, 10))
	t.set_stylebox("pressed", "Button", box(ACCENT, 6, ACCENT, 1, 10))
	t.set_stylebox("hover_pressed", "Button", box(ACCENT.lightened(0.08), 6, ACCENT, 1, 10))
	t.set_stylebox("disabled", "Button", box(control_bg.darkened(0.04) if dark else Color("f5f5f7"), 6, BORDER, 1, 10))
	t.set_stylebox("focus", "Button", box(Color.TRANSPARENT, 7, Color(ACCENT, 0.55), 2, 10))
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.6))
	t.set_color("font_focus_color", "Button", TEXT)

	for c in ["OptionButton", "MenuButton"]:
		t.set_stylebox("normal", c, box(control_bg, 6, BORDER, 1, 10))
		t.set_stylebox("hover", c, box(hover_bg, 6, BORDER, 1, 10))
		t.set_stylebox("pressed", c, box(hover_bg, 6, ACCENT, 1, 10))
		t.set_stylebox("focus", c, box(Color.TRANSPARENT, 7, Color(ACCENT, 0.55), 2, 10))
		t.set_stylebox("disabled", c, box(control_bg, 6, BORDER, 1, 10))
		t.set_color("font_pressed_color", c, TEXT)
		t.set_color("font_hover_color", c, TEXT)

	# Checkboxes keep their glyph; tint the text.
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", TEXT)
	for st in ["normal", "pressed", "hover", "hover_pressed", "focus"]:
		t.set_stylebox(st, "CheckBox", box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 4))

	# Text fields
	var field_bg := Color("1c1c1e") if dark else Color.WHITE
	t.set_stylebox("normal", "LineEdit", box(field_bg, 6, BORDER, 1, 8))
	t.set_stylebox("focus", "LineEdit", box(field_bg, 6, Color(ACCENT, 0.8), 2, 8))
	t.set_stylebox("read_only", "LineEdit", box(BG_2, 6, BORDER, 1, 8))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.8))
	t.set_stylebox("normal", "TextEdit", box(field_bg, 6, BORDER, 1, 8))
	t.set_stylebox("focus", "TextEdit", box(field_bg, 6, Color(ACCENT, 0.8), 2, 8))

	# Source lists (sidebars): rounded highlight rows.
	t.set_stylebox("panel", "Tree", box(BG_2, 8, Color.TRANSPARENT, 0, 6))
	t.set_stylebox("focus", "Tree", box(Color.TRANSPARENT, 8))
	t.set_stylebox("selected", "Tree", box(Color(ACCENT, 0.85), 5, Color.TRANSPARENT, 0, 2))
	t.set_stylebox("selected_focus", "Tree", box(ACCENT, 5, Color.TRANSPARENT, 0, 2))
	t.set_stylebox("hovered", "Tree", box(Color(TEXT, 0.06), 5, Color.TRANSPARENT, 0, 2))
	t.set_stylebox("hovered_dimmed", "Tree", box(Color(TEXT, 0.04), 5, Color.TRANSPARENT, 0, 2))
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_color("font_hovered_color", "Tree", TEXT)
	t.set_color("guide_color", "Tree", Color.TRANSPARENT)
	t.set_color("relationship_line_color", "Tree", Color(TEXT_DIM, 0.25))
	t.set_constant("draw_relationship_lines", "Tree", 0)
	t.set_constant("v_separation", "Tree", 6)
	t.set_constant("item_margin", "Tree", 14)
	t.set_stylebox("panel", "ItemList", box(BG_2, 8, Color.TRANSPARENT, 0, 6))
	t.set_stylebox("selected", "ItemList", box(Color(ACCENT, 0.85), 5))
	t.set_stylebox("selected_focus", "ItemList", box(ACCENT, 5))
	t.set_stylebox("hovered", "ItemList", box(Color(TEXT, 0.06), 5))
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("font_hovered_color", "ItemList", TEXT)
	t.set_constant("v_separation", "ItemList", 6)

	# Tabs as a segmented control.
	t.set_stylebox("panel", "TabContainer", box(PANEL, 0, Color.TRANSPARENT, 0, 6))
	t.set_stylebox("tabbar_background", "TabContainer", box(BG_2, 0, Color.TRANSPARENT, 0, 4))
	var seg_sel := box(Color("636366") if dark else Color.WHITE, 6, Color.TRANSPARENT, 0, 12)
	t.set_stylebox("tab_selected", "TabContainer", _shadowed(seg_sel, 2))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 12))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(TEXT, 0.07), 6, Color.TRANSPARENT, 0, 12))
	t.set_stylebox("tab_focus", "TabContainer", box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 12))
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_constant("side_margin", "TabContainer", 6)

	# Menus: translucent rounded popovers with blue highlight.
	var menu_bg := Color("2c2c2e", 0.97) if dark else Color("fbfbfd", 0.98)
	t.set_stylebox("panel", "PopupMenu", _shadowed(box(menu_bg, 10, BORDER, 1, 6), 14))
	t.set_stylebox("hover", "PopupMenu", box(ACCENT, 5, Color.TRANSPARENT, 0, 6))
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", Color(TEXT_DIM, 0.6))
	t.set_color("font_accelerator_color", "PopupMenu", TEXT_DIM)
	t.set_color("font_separator_color", "PopupMenu", TEXT_DIM)
	t.set_constant("v_separation", "PopupMenu", 7)
	t.set_stylebox("separator", "PopupMenu", _line(BORDER))
	t.set_stylebox("normal", "MenuBar", box(Color.TRANSPARENT, 5, Color.TRANSPARENT, 0, 8))
	t.set_stylebox("hover", "MenuBar", box(Color(TEXT, 0.08), 5, Color.TRANSPARENT, 0, 8))
	t.set_stylebox("pressed", "MenuBar", box(Color(TEXT, 0.14), 5, Color.TRANSPARENT, 0, 8))
	t.set_color("font_pressed_color", "MenuBar", TEXT)
	t.set_color("font_hover_color", "MenuBar", TEXT)
	t.set_stylebox("panel", "PopupPanel", _shadowed(box(menu_bg, 10, BORDER, 1, 8), 14))
	t.set_stylebox("panel", "AcceptDialog", box(PANEL, 12, BORDER, 1, 18))
	t.set_stylebox("embedded_border", "Window", _shadowed(box(PANEL, 12, BORDER, 1, 0), 24))
	t.set_stylebox("embedded_unfocused_border", "Window", _shadowed(box(PANEL, 12, BORDER, 1, 0), 18))
	t.set_color("title_color", "Window", TEXT)
	t.set_constant("title_height", "Window", 32)

	# Scrollbars: thin overlay style.
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, box(Color.TRANSPARENT, 4, Color.TRANSPARENT, 0, 1))
		t.set_stylebox("grabber", sb, box(Color(TEXT_DIM, 0.45), 4, Color.TRANSPARENT, 0, 3))
		t.set_stylebox("grabber_highlight", sb, box(Color(TEXT_DIM, 0.7), 4, Color.TRANSPARENT, 0, 3))
		t.set_stylebox("grabber_pressed", sb, box(Color(TEXT_DIM, 0.85), 4, Color.TRANSPARENT, 0, 3))
	t.set_stylebox("separator", "HSeparator", _line(BORDER))
	t.set_stylebox("separator", "VSeparator", _line(BORDER))
	t.set_stylebox("panel", "TooltipPanel", _shadowed(box(menu_bg, 6, BORDER, 1, 8), 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_constant("separation", "HSplitContainer", 1)
	t.set_constant("separation", "VSplitContainer", 1)
	t.set_stylebox("split_bar_background", "HSplitContainer", box(BORDER, 0, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("split_bar_background", "VSplitContainer", box(BORDER, 0, Color.TRANSPARENT, 0, 0))

	# GraphEdit (Block Studio)
	t.set_stylebox("panel", "GraphEdit", box(Color("1a1a1c") if dark else Color("f2f2f7"), 0))
	t.set_color("grid_major", "GraphEdit", Color(TEXT, 0.07))
	t.set_color("grid_minor", "GraphEdit", Color(TEXT, 0.03))
	t.set_color("selection_fill", "GraphEdit", Color(ACCENT, 0.12))
	t.set_color("selection_stroke", "GraphEdit", Color(ACCENT, 0.8))
	t.set_stylebox("panel", "GraphNode", _shadowed(box(PANEL_2 if dark else Color.WHITE, 10, BORDER, 1, 10), 6))
	t.set_stylebox("panel_selected", "GraphNode", _shadowed(box(PANEL_2 if dark else Color.WHITE, 10, ACCENT, 2, 10), 8))
	t.set_stylebox("titlebar", "GraphNode", box(Color.TRANSPARENT, 10, Color.TRANSPARENT, 0, 10))
	t.set_stylebox("titlebar_selected", "GraphNode", box(Color.TRANSPARENT, 10, Color.TRANSPARENT, 0, 10))
	t.set_color("resizer_color", "GraphNode", TEXT_DIM)
	return t

static func _line(color: Color) -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = color
	l.thickness = 1
	return l
