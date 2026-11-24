class_name ZinoHud
extends CanvasLayer
## In-game racing HUD: speedometer (speed, gear, RPM), lap counter, race position, timers, minimap,
## countdown, messages, big text, progress bars, custom labels, results screen and pause menu.
## Layout comes from scene settings `hud` (edited in the UI Studio): {element: {visible, anchor, offset, scale}}.

signal menu_action(action: String)   # resume, restart, quit

const ELEMENTS := ["speedometer", "laps", "position", "timer", "minimap", "message", "labels"]
const DEFAULT_LAYOUT := {
	"speedometer": {"visible": true, "anchor": "bottom_right", "offset": [-40, -40], "scale": 1.0},
	"laps": {"visible": true, "anchor": "top_left", "offset": [40, 40], "scale": 1.0},
	"position": {"visible": true, "anchor": "top_left", "offset": [40, 110], "scale": 1.0},
	"timer": {"visible": true, "anchor": "top_right", "offset": [-40, 40], "scale": 1.0},
	"minimap": {"visible": true, "anchor": "bottom_left", "offset": [40, -40], "scale": 1.0},
	"message": {"visible": true, "anchor": "top_center", "offset": [0, 120], "scale": 1.0},
	"labels": {"visible": true, "anchor": "top_center", "offset": [0, 40], "scale": 1.0},
}

var context
var layout := DEFAULT_LAYOUT.duplicate(true)
var root: Control
var _panels := {}
var _speed: Label
var _gear: Label
var _rpm: ProgressBar
var _laps: Label
var _pos: Label
var _timer: Label
var _best: Label
var _message: Label
var _message_until := 0.0
var _big: Label
var _big_until := 0.0
var _countdown: Label
var _labels: Array[Label] = []
var _progress_box: VBoxContainer
var _progress := {}
var _results: PanelContainer
var _menu: PanelContainer
var _minimap: Control
var _clock := 0.0

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _game_theme()
	add_child(root)
	_build()
	apply_layout(layout)

func _glass() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.08, 0.1, 0.62)
	s.set_corner_radius_all(16)
	s.content_margin_left = 18; s.content_margin_right = 18; s.content_margin_top = 10; s.content_margin_bottom = 10
	s.border_color = Color(1, 1, 1, 0.12)
	s.set_border_width_all(1)
	return s

func _game_theme() -> Theme:
	var t := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["SF Pro Display", "Segoe UI Variable Display", "Segoe UI", "Helvetica Neue", "Arial"])
	f.font_weight = 600
	t.default_font = f
	t.default_font_size = 20
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_stylebox("panel", "PanelContainer", _glass())
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("0a84ff")
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.15)
	bg.set_corner_radius_all(4)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_color("font_color", "ProgressBar", Color.WHITE)
	var btn := _glass()
	btn.bg_color = Color(1, 1, 1, 0.12)
	t.set_stylebox("normal", "Button", btn)
	var btn_h := btn.duplicate() as StyleBoxFlat
	btn_h.bg_color = Color("0a84ff")
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_h)
	t.set_stylebox("focus", "Button", btn_h)
	return t

func _panel(name: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	_panels[name] = p
	return p

func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build() -> void:
	var sp := _panel("speedometer")
	var sv := VBoxContainer.new()
	sp.add_child(sv)
	var sh := HBoxContainer.new()
	_speed = _label("0", 56)
	sh.add_child(_speed)
	var unit := VBoxContainer.new()
	unit.add_child(_label("km/h", 16, Color(1, 1, 1, 0.7)))
	_gear = _label("N", 30, Color("ffd60a"))
	unit.add_child(_gear)
	sh.add_child(unit)
	sv.add_child(sh)
	_rpm = ProgressBar.new()
	_rpm.custom_minimum_size = Vector2(220, 8)
	_rpm.show_percentage = false
	sv.add_child(_rpm)

	var lp := _panel("laps")
	_laps = _label("Lap 1/3", 28)
	lp.add_child(_laps)
	var pp := _panel("position")
	_pos = _label("P1/1", 36)
	pp.add_child(_pos)
	var tp := _panel("timer")
	var tv := VBoxContainer.new()
	_timer = _label("0:00.000", 28)
	_best = _label("Best --:--.---", 16, Color(1, 1, 1, 0.7))
	tv.add_child(_timer)
	tv.add_child(_best)
	tp.add_child(tv)

	var mm := _panel("minimap")
	_minimap = Control.new()
	_minimap.custom_minimum_size = Vector2(200, 200)
	_minimap.draw.connect(_draw_minimap)
	mm.add_child(_minimap)

	var msg := _panel("message")
	_message = _label("", 26)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_child(_message)
	msg.visible = false

	var lb := _panel("labels")
	var lv := VBoxContainer.new()
	lb.add_child(lv)
	for i in 4:
		var l := _label("", 20)
		l.visible = false
		_labels.append(l)
		lv.add_child(l)
	_progress_box = VBoxContainer.new()
	lv.add_child(_progress_box)
	lb.visible = false

	_big = _label("", 84)
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_big.grow_vertical = Control.GROW_DIRECTION_BOTH
	_big.visible = false
	root.add_child(_big)
	_countdown = _label("", 150, Color("ffd60a"))
	_countdown.set_anchors_preset(Control.PRESET_CENTER)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown.visible = false
	root.add_child(_countdown)

	_results = PanelContainer.new()
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_results.grow_vertical = Control.GROW_DIRECTION_BOTH
	_results.visible = false
	root.add_child(_results)
	_menu = PanelContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.visible = false
	root.add_child(_menu)

## Applies a layout dictionary (from the UI Studio). Unknown elements are ignored.
func apply_layout(l: Dictionary) -> void:
	for k in DEFAULT_LAYOUT:
		var e: Dictionary = DEFAULT_LAYOUT[k].duplicate()
		if l.has(k) and l[k] is Dictionary:
			e.merge(l[k], true)
		layout[k] = e
		var p: Control = _panels.get(k)
		if p == null:
			continue
		if k != "message" and k != "labels":
			p.visible = e.visible
		p.scale = Vector2.ONE * float(e.get("scale", 1.0))
		_place(p, str(e.anchor), ZinoFormat.v3([e.offset[0], e.offset[1], 0]))

func _place(p: Control, anchor: String, off: Vector3) -> void:
	var presets := {"top_left": Control.PRESET_TOP_LEFT, "top_right": Control.PRESET_TOP_RIGHT, "bottom_left": Control.PRESET_BOTTOM_LEFT,
		"bottom_right": Control.PRESET_BOTTOM_RIGHT, "top_center": Control.PRESET_CENTER_TOP, "bottom_center": Control.PRESET_CENTER_BOTTOM, "center": Control.PRESET_CENTER}
	p.set_anchors_and_offsets_preset(presets.get(anchor, Control.PRESET_TOP_LEFT), Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN if anchor.ends_with("right") else (Control.GROW_DIRECTION_BOTH if anchor.ends_with("center") else Control.GROW_DIRECTION_END)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN if anchor.begins_with("bottom") else Control.GROW_DIRECTION_END
	p.position += Vector2(off.x, off.y)

func set_element_visible(element: String, v: bool) -> void:
	var targets: Array = ELEMENTS if element == "all" else [element]
	for e in targets:
		if layout.has(e):
			layout[e]["visible"] = v
		if _panels.has(e) and e != "message" and e != "labels":
			_panels[e].visible = v

func show_message(text: String, seconds: float) -> void:
	_message.text = text
	_panels["message"].visible = true
	_message_until = _clock + seconds

func hide_message() -> void:
	_panels["message"].visible = false

func show_big(text: String, seconds: float) -> void:
	_big.text = text
	_big.visible = true
	_big_until = _clock + seconds

func show_countdown(text: String) -> void:
	_countdown.text = text
	_countdown.visible = text != ""

func set_label(slot: int, text: String) -> void:
	var i := clampi(slot - 1, 0, _labels.size() - 1)
	_labels[i].text = text
	_labels[i].visible = text != ""
	_panels["labels"].visible = true

func set_progress(name: String, value: float) -> void:
	if not _progress.has(name):
		var h := HBoxContainer.new()
		h.add_child(_label(name, 16))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(180, 10)
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		h.add_child(bar)
		_progress_box.add_child(h)
		_progress[name] = bar
	_progress[name].value = clampf(value, 0.0, 1.0)
	_panels["labels"].visible = true

func show_results(rows: Array) -> void:
	for c in _results.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(_label("Results", 40))
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 24)
		var pos_l := _label("%d" % int(r.position), 26, Color("ffd60a"))
		pos_l.custom_minimum_size.x = 40
		h.add_child(pos_l)
		var name_l := _label(str(r.name), 24)
		name_l.custom_minimum_size.x = 220
		h.add_child(name_l)
		h.add_child(_label(ZinoBlockRuntime.format_lap_time(r.time) if r.finished else ("OUT" if r.get("eliminated", false) else "DNF"), 24))
		h.add_child(_label("best " + ZinoBlockRuntime.format_lap_time(r.best_lap), 18, Color(1, 1, 1, 0.7)))
		v.add_child(h)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.add_child(_menu_button("Watch Replay", "replay"))
	hb.add_child(_menu_button("Restart", "restart"))
	v.add_child(hb)
	_results.add_child(v)
	_results.visible = true

func show_menu(kind: String) -> void:
	if kind == "results":
		_results.visible = true
		return
	for c in _menu.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(_label("Paused" if kind == "pause" else "Zino Racing", 40))
	if kind == "pause":
		v.add_child(_menu_button("Resume", "resume"))
	v.add_child(_menu_button("Restart Race", "restart"))
	v.add_child(_menu_button("Quit", "quit"))
	_menu.add_child(v)
	_menu.visible = true
	root.mouse_filter = Control.MOUSE_FILTER_STOP

func hide_menus() -> void:
	_menu.visible = false
	_results.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

func is_menu_open() -> bool:
	return _menu.visible

func _menu_button(text: String, action: String) -> Button:
	var b := Button.new()
	b.text = "   " + text + "   "
	b.custom_minimum_size = Vector2(260, 52)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.pressed.connect(func(): menu_action.emit(action))
	return b

func _process(delta: float) -> void:
	_clock += delta
	if _panels["message"].visible and _message_until > 0.0 and _clock > _message_until:
		_panels["message"].visible = false
	if _big.visible and _clock > _big_until:
		_big.visible = false
	if context == null:
		return
	var car: ZinoVehicle = context.vehicle("player")
	if car:
		_speed.text = "%d" % int(car.speed_kmh)
		_gear.text = "R" if car.gear == -1 else ("N" if car.gear == 0 else str(car.gear))
		_rpm.max_value = float(car.spec.get("maxRpm", 7200))
		_rpm.value = car.rpm
	var race = context.race
	if race:
		var r = race.racer_for(car) if car else null
		if r:
			_laps.text = "Lap %d/%d" % [mini(r.lap, race.laps), race.laps] if race.mode == "circuit" else "Sprint"
			_pos.text = "P%d/%d" % [r.position, race.racers.size()]
			_timer.text = ZinoBlockRuntime.format_lap_time(r.lap_time()) if race.state == "racing" and not r.finished else ZinoBlockRuntime.format_lap_time(r.total_time)
			var sec := ""
			for i in r.sectors.size():
				var prev: float = r.sectors[i - 1] if i > 0 else 0.0
				sec += "  S%d %.2f" % [i + 1, r.sectors[i] - prev]
			_best.text = "Best " + ZinoBlockRuntime.format_lap_time(r.best_lap) + sec
	if _panels["minimap"].visible:
		_minimap.queue_redraw()

func _draw_minimap() -> void:
	if context == null:
		return
	var pts: PackedVector3Array = context.track_points()
	var size := _minimap.size
	_minimap.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.0))
	if pts.size() < 2:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var span := maxf(hi.x - lo.x, hi.y - lo.y)
	if span <= 0.0:
		return
	var sc := (minf(size.x, size.y) - 16.0) / span
	var to_map := func(p: Vector3) -> Vector2: return Vector2(8, 8) + (Vector2(p.x, p.z) - lo) * sc
	var line := PackedVector2Array()
	for p in pts:
		line.append(to_map.call(p))
	if context.track_closed():
		line.append(line[0])
	_minimap.draw_polyline(line, Color(1, 1, 1, 0.75), 4.0, true)
	for v in context.all_vehicles():
		var col := Color("0a84ff") if v == context.vehicle("player") else Color("ff453a")
		_minimap.draw_circle(to_map.call(v.global_position), 5.0, col)
