class_name ZinoUI
extends RefCounted
## Small helpers for building the editor UI in code.

static func label(text: String, size: int = 14, color: Color = ZinoTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func dim(text: String, size: int = 13) -> Label:
	return label(text, size, ZinoTheme.TEXT_DIM)

static func heading(text: String, size: int = 20) -> Label:
	return label(text, size, ZinoTheme.TEXT)

static func button(text: String, on_pressed: Callable, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b

static func accent_button(text: String, on_pressed: Callable) -> Button:
	var b := button(text, on_pressed)
	b.add_theme_stylebox_override("normal", ZinoTheme.box(ZinoTheme.ACCENT, 6, ZinoTheme.ACCENT, 1, 14))
	b.add_theme_stylebox_override("hover", ZinoTheme.box(ZinoTheme.ACCENT.lightened(0.08), 6, ZinoTheme.ACCENT, 1, 14))
	b.add_theme_stylebox_override("pressed", ZinoTheme.box(ZinoTheme.ACCENT.darkened(0.12), 6, ZinoTheme.ACCENT, 1, 14))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_color", Color.WHITE)
	return b

static func toggle(text: String, pressed: bool, on_toggled: Callable, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = pressed
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(on_toggled)
	return b

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func margin(child: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	m.add_child(child)
	return m

static func card(color: Color = ZinoTheme.PANEL, radius: int = 10, pad: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ZinoTheme.box(color, radius, ZinoTheme.BORDER, 1, pad))
	return p

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

static func spin(min_v: float, max_v: float, step: float, value: float, on_changed: Callable, suffix: String = "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.allow_greater = true
	s.allow_lesser = true
	s.value = value
	s.suffix = suffix
	s.select_all_on_focus = true
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.x = 60
	s.value_changed.connect(on_changed)
	return s

static func option(items: Array, selected_value, on_selected: Callable) -> OptionButton:
	## items: Array of [value, label]. on_selected receives the value.
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for i in items.size():
		o.add_item(str(items[i][1]), i)
		o.set_item_metadata(i, items[i][0])
		if items[i][0] == selected_value:
			o.select(i)
	o.item_selected.connect(func(idx): on_selected.call(o.get_item_metadata(idx)))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return o

static func check(text: String, pressed: bool, on_toggled: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(on_toggled)
	return c

static func color_button(color: Color, on_changed: Callable) -> ColorPickerButton:
	var c := ColorPickerButton.new()
	c.color = color
	c.edit_alpha = false
	c.custom_minimum_size = Vector2(60, 26)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.popup_closed.connect(func(): on_changed.call(c.color))
	return c

## A labelled row: [label | control].
static func row(text: String, control: Control, label_width: int = 110) -> HBoxContainer:
	var h := hbox(6)
	var l := dim(text, 13)
	l.custom_minimum_size.x = label_width
	l.clip_text = true
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h

## Three spin boxes for a Vector3; on_changed receives the new Vector3.
static func vec3_row(text: String, value: Vector3, step: float, on_changed: Callable) -> HBoxContainer:
	var h := hbox(4)
	var l := dim(text, 13)
	l.custom_minimum_size.x = 70
	h.add_child(l)
	var boxes: Array[SpinBox] = []
	var axis_colors := [Color(0.95, 0.35, 0.35), Color(0.45, 0.9, 0.35), Color(0.35, 0.6, 1.0)]
	for i in 3:
		var s := SpinBox.new()
		s.step = step
		s.allow_greater = true
		s.allow_lesser = true
		s.min_value = -1e6
		s.max_value = 1e6
		s.value = value[i]
		s.select_all_on_focus = true
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.custom_minimum_size.x = 50
		s.get_line_edit().add_theme_color_override("font_color", axis_colors[i].lightened(0.35))
		boxes.append(s)
		h.add_child(s)
	for s in boxes:
		s.value_changed.connect(func(_v): on_changed.call(Vector3(boxes[0].value, boxes[1].value, boxes[2].value)))
	return h

static func section(title: String) -> VBoxContainer:
	var v := vbox(6)
	var h := hbox(6)
	h.add_child(label(title, 13, ZinoTheme.TEXT_DIM))
	v.add_child(h)
	return v

static func pill(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ZinoTheme.box(Color(color, 0.16), 10, Color(color, 0.45), 1, 8))
	var l := label(text, 12, color)
	p.add_child(l)
	return p
