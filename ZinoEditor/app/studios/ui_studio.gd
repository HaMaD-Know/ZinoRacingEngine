class_name ZinoUIStudio
extends HSplitContainer
## UI Studio: lay out the in-game HUD by dragging elements on a live 1920×1080 preview, or edit
## anchors, offsets, scale and visibility numerically. Mobile touch controls are designed on the
## same canvas (Touch tab, Phase 10). Saved in scene settings (hud / touch).

var session: ZinoEditorSession
var mode := "hud"                        # hud or touch
var _vp: SubViewport
var _preview: TextureRect
var _hud: ZinoHud
var _touch: ZinoTouchControls
var _props: VBoxContainer
var _selected := ""
var _drag_from := Vector2.INF
var _drag_offset := Vector2.ZERO
var _layout: Dictionary = {}

func setup(s: ZinoEditorSession) -> void:
	session = s
	var left := ZinoUI.vbox(8)
	left.custom_minimum_size.x = 300
	var seg := ZinoUI.hbox(0)
	var hb := ZinoUI.toggle("HUD", true, func(_on): set_mode("hud"))
	var tb := ZinoUI.toggle("Touch Controls", false, func(_on): set_mode("touch"))
	seg.add_child(hb)
	seg.add_child(tb)
	set_meta("seg", [hb, tb])
	left.add_child(seg)
	_props = ZinoUI.vbox(6)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(_props)
	_props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(sc)
	add_child(left)
	var right := ZinoUI.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(ZinoUI.dim("Live preview at 1920×1080. Drag elements to move them; changes are undoable.", 12))
	_vp = SubViewport.new()
	_vp.size = Vector2i(1920, 1080)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var bg := ColorRect.new()
	bg.color = Color(0.28, 0.33, 0.38)
	bg.size = Vector2(1920, 1080)
	_vp.add_child(bg)
	var road := ColorRect.new()
	road.color = Color(0.16, 0.16, 0.18)
	road.position = Vector2(560, 500)
	road.size = Vector2(800, 580)
	_vp.add_child(road)
	_preview = TextureRect.new()
	_preview.texture = _vp.get_texture()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.gui_input.connect(_preview_input)
	right.add_child(_preview)
	add_child(right)
	session.scene_changed.connect(func(c):
		if c.get("settingsChanged", false) or c.get("reloaded", false):
			_reload.call_deferred())
	visibility_changed.connect(func(): if visible: _reload())
	_reload()

func set_mode(m: String) -> void:
	mode = m
	var seg: Array = get_meta("seg")
	seg[0].set_pressed_no_signal(m == "hud")
	seg[1].set_pressed_no_signal(m == "touch")
	_selected = ""
	_reload()

func _reload() -> void:
	if _hud:
		_hud.free()
		_hud = null
	if _touch:
		_touch.free()
		_touch = null
	var st: Dictionary = session.scene().settings
	if mode == "hud":
		_layout = ZinoHud.DEFAULT_LAYOUT.duplicate(true)
		for k in st.get("hud", {}):
			if _layout.has(k):
				_layout[k].merge(st.hud[k], true)
		_hud = ZinoHud.new()
		_vp.add_child(_hud)
		_hud.apply_layout(_layout)
		_hud.show_message("Lap 2  1:23.456", 0.0)
		_hud.set_label(1, "Custom label")
		_hud.set_progress("Boost", 0.6)
	else:
		_layout = ZinoTouchControls.default_layout()
		for k in st.get("touch", {}).get("controls", {}):
			if _layout.has(k):
				_layout[k].merge(st.touch.controls[k], true)
		_touch = ZinoTouchControls.new()
		_touch.always_visible = true
		_vp.add_child(_touch)
		_touch.apply_layout(_layout)
	_rebuild_props()

func _panel_rect(key: String) -> Rect2:
	if mode == "hud":
		var p: Control = _hud._panels.get(key)
		return p.get_global_rect() if p else Rect2()
	return _touch.control_rect(key)

func _to_vp(pos: Vector2) -> Vector2:
	# The preview keeps aspect and is centred.
	var s := minf(_preview.size.x / 1920.0, _preview.size.y / 1080.0)
	var off := (_preview.size - Vector2(1920, 1080) * s) * 0.5
	return (pos - off) / s

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var p := _to_vp(event.position)
			_selected = ""
			for k in _layout:
				if _panel_rect(k).has_point(p):
					_selected = k
			if _selected != "":
				_drag_from = p
				_drag_offset = Vector2(_layout[_selected].offset[0], _layout[_selected].offset[1])
			_rebuild_props()
		elif _drag_from != Vector2.INF:
			_drag_from = Vector2.INF
			_commit()
	elif event is InputEventMouseMotion and _drag_from != Vector2.INF and _selected != "":
		var d := _to_vp(event.position) - _drag_from
		_layout[_selected].offset = [snappedf(_drag_offset.x + d.x, 2.0), snappedf(_drag_offset.y + d.y, 2.0)]
		_apply_preview()

func _apply_preview() -> void:
	if mode == "hud":
		_hud.apply_layout(_layout)
	else:
		_touch.apply_layout(_layout)

## Writes the layout to the scene settings (one undoable command).
func _commit() -> void:
	var st: Dictionary = session.scene().settings.duplicate(true)
	if mode == "hud":
		st["hud"] = _layout.duplicate(true)
	else:
		var t: Dictionary = st.get("touch", {})
		t["controls"] = _layout.duplicate(true)
		st["touch"] = t
	session.execute(ZinoSceneEdits.settings(session.scene(), st, "HUD Layout" if mode == "hud" else "Touch Layout"))

func _rebuild_props() -> void:
	for c in _props.get_children():
		c.queue_free()
	_props.add_child(ZinoUI.heading("HUD Elements" if mode == "hud" else "Touch Controls", 17))
	if mode == "touch":
		_touch_settings()
	for k in _layout:
		var key: String = k
		var e: Dictionary = _layout[key]
		var sec := ZinoUI.section(key.capitalize() + ("  ◀" if key == _selected else ""))
		sec.add_child(ZinoUI.row("Visible", ZinoUI.check("Show", e.get("visible", true), func(v): _set_field(key, "visible", v)), 80))
		var anchors := ["top_left", "top_center", "top_right", "center", "bottom_left", "bottom_center", "bottom_right"]
		sec.add_child(ZinoUI.row("Anchor", ZinoUI.option(anchors.map(func(a): return [a, a.replace("_", " ").capitalize()]), e.get("anchor", "top_left"), func(v): _set_field(key, "anchor", v)), 80))
		var oh := ZinoUI.hbox(4)
		oh.add_child(ZinoUI.spin(-1920, 1920, 1, float(e.offset[0]), func(v): _set_field(key, "offset", [v, _layout[key].offset[1]])))
		oh.add_child(ZinoUI.spin(-1080, 1080, 1, float(e.offset[1]), func(v): _set_field(key, "offset", [_layout[key].offset[0], v])))
		sec.add_child(ZinoUI.row("Offset", oh, 80))
		sec.add_child(ZinoUI.row("Scale", ZinoUI.spin(0.3, 4, 0.05, float(e.get("scale", 1.0)), func(v): _set_field(key, "scale", v)), 80))
		if mode == "touch":
			sec.add_child(ZinoUI.row("Opacity", ZinoUI.spin(0.05, 1, 0.05, float(e.get("opacity", 0.6)), func(v): _set_field(key, "opacity", v)), 80))
		_props.add_child(sec)
	_props.add_child(ZinoUI.button("Reset to defaults", func():
		_layout = ZinoHud.DEFAULT_LAYOUT.duplicate(true) if mode == "hud" else ZinoTouchControls.default_layout()
		_commit()))

func _set_field(key: String, field: String, value) -> void:
	_layout[key][field] = value
	_apply_preview()
	_commit()

func _touch_settings() -> void:
	var t: Dictionary = session.scene().settings.get("touch", {})
	var set_t := func(field: String, value):
		var st: Dictionary = session.scene().settings.duplicate(true)
		var tt: Dictionary = st.get("touch", {})
		tt[field] = value
		st["touch"] = tt
		session.execute(ZinoSceneEdits.settings(session.scene(), st, "Touch Settings"))
	var sec := ZinoUI.section("Behaviour")
	sec.add_child(ZinoUI.row("Steering", ZinoUI.option([["arrows", "Arrow buttons"], ["wheel", "Steering wheel"], ["tilt", "Tilt (gyroscope)"]], t.get("steering", "arrows"), func(v): set_t.call("steering", v)), 80))
	sec.add_child(ZinoUI.row("Sensitivity", ZinoUI.spin(0.2, 3, 0.05, float(t.get("sensitivity", 1.0)), func(v): set_t.call("sensitivity", v)), 80))
	sec.add_child(ZinoUI.row("Gearbox", ZinoUI.option([[true, "Automatic"], [false, "Manual (shift buttons)"]], t.get("automatic", true), func(v): set_t.call("automatic", v)), 80))
	sec.add_child(ZinoUI.row("Auto throttle", ZinoUI.check("Accelerate automatically", t.get("autoAccelerate", false), func(v): set_t.call("autoAccelerate", v)), 80))
	_props.add_child(sec)
