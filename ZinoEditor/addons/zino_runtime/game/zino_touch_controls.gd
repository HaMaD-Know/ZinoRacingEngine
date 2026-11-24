class_name ZinoTouchControls
extends CanvasLayer
## On-screen touch controls for phones and tablets. Every control drives the same input actions as
## the keyboard/gamepad, so vehicles and blocks behave identically. Steering: arrow buttons, a
## draggable steering wheel or tilt (accelerometer). Layout comes from the UI Studio (scene settings
## touch.controls); positions are anchored so they adapt to any aspect ratio.

const CONTROLS := {
	"steer_left": {"label": "◀", "action": ZinoInput.STEER_LEFT, "anchor": "bottom_left", "offset": [60, -60], "size": 150},
	"steer_right": {"label": "▶", "action": ZinoInput.STEER_RIGHT, "anchor": "bottom_left", "offset": [240, -60], "size": 150},
	"wheel": {"label": "⟳", "action": "", "anchor": "bottom_left", "offset": [60, -60], "size": 300},
	"accelerate": {"label": "GO", "action": ZinoInput.ACCELERATE, "anchor": "bottom_right", "offset": [-60, -60], "size": 170},
	"brake": {"label": "BRK", "action": ZinoInput.BRAKE, "anchor": "bottom_right", "offset": [-250, -60], "size": 140},
	"handbrake": {"label": "HB", "action": ZinoInput.HANDBRAKE, "anchor": "bottom_right", "offset": [-250, -220], "size": 110},
	"nitro": {"label": "N₂O", "action": ZinoInput.NITRO, "anchor": "bottom_right", "offset": [-60, -250], "size": 120},
	"shift_up": {"label": "+", "action": ZinoInput.SHIFT_UP, "anchor": "bottom_right", "offset": [-400, -200], "size": 90},
	"shift_down": {"label": "−", "action": ZinoInput.SHIFT_DOWN, "anchor": "bottom_right", "offset": [-400, -90], "size": 90},
	"camera": {"label": "CAM", "action": ZinoInput.CAMERA, "anchor": "top_right", "offset": [-60, 200], "size": 90},
	"pause": {"label": "❚❚", "action": ZinoInput.PAUSE, "anchor": "top_center", "offset": [0, 30], "size": 80},
}

var settings: Dictionary = {}
var always_visible := false             # editor preview
var layout := {}
var _root: Control
var _buttons := {}
var _touches := {}                      # finger index -> control key
var _wheel_angle := 0.0
var _wheel_finger := -1
var _wheel_start := 0.0

static func default_layout() -> Dictionary:
	var out := {}
	for k in CONTROLS:
		var c: Dictionary = CONTROLS[k]
		out[k] = {"visible": k != "wheel", "anchor": c.anchor, "offset": c.offset.duplicate(), "scale": 1.0, "opacity": 0.6}
	return out

static func should_show() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_ios") or OS.has_feature("web_android") or DisplayServer.is_touchscreen_available()

func _ready() -> void:
	layer = 11
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	ZinoInput.ensure_actions()
	if layout.is_empty():
		apply_layout(default_layout())
	visible = always_visible or should_show()

func apply_layout(l: Dictionary) -> void:
	layout = default_layout()
	for k in l:
		if layout.has(k) and l[k] is Dictionary:
			layout[k].merge(l[k], true)
	var steering := str(settings.get("steering", "arrows"))
	if not always_visible:
		layout.wheel.visible = steering == "wheel"
		if steering != "arrows":
			layout.steer_left.visible = false
			layout.steer_right.visible = false
		if settings.get("automatic", true):
			layout.shift_up.visible = false
			layout.shift_down.visible = false
	if _root == null:
		return
	for c in _root.get_children():
		c.free()
	_buttons.clear()
	for k in layout:
		var e: Dictionary = layout[k]
		if not e.get("visible", true):
			continue
		var size := float(CONTROLS[k].size) * float(e.get("scale", 1.0))
		var b := Panel.new()
		b.name = k
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.1, 0.1, 0.12, float(e.get("opacity", 0.6)))
		st.border_color = Color(1, 1, 1, 0.5 * float(e.get("opacity", 0.6)) + 0.2)
		st.set_border_width_all(3)
		st.set_corner_radius_all(int(size * 0.5))
		b.add_theme_stylebox_override("panel", st)
		b.size = Vector2(size, size)
		var lab := Label.new()
		lab.text = CONTROLS[k].label
		lab.add_theme_font_size_override("font_size", int(size * 0.3))
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(lab)
		_root.add_child(b)
		_place(b, str(e.anchor), Vector2(e.offset[0], e.offset[1]))
		_buttons[k] = b

func _place(c: Control, anchor: String, off: Vector2) -> void:
	var vp := Vector2(get_viewport().get_visible_rect().size) if get_viewport() else Vector2(1920, 1080)
	var base := Vector2.ZERO
	if anchor.ends_with("right"):
		base.x = vp.x - c.size.x
	elif anchor.ends_with("center") or anchor == "center":
		base.x = (vp.x - c.size.x) * 0.5
	if anchor.begins_with("bottom"):
		base.y = vp.y - c.size.y
	elif anchor == "center":
		base.y = (vp.y - c.size.y) * 0.5
	c.position = base + off

func control_rect(key: String) -> Rect2:
	var b: Control = _buttons.get(key)
	return b.get_global_rect() if b else Rect2()

func _input(event: InputEvent) -> void:
	if not visible or always_visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			for k in _buttons:
				if control_rect(k).has_point(event.position):
					_touches[event.index] = k
					_press(k, true, event.position)
					get_viewport().set_input_as_handled()
					return
		elif _touches.has(event.index):
			_press(_touches[event.index], false, event.position)
			_touches.erase(event.index)
	elif event is InputEventScreenDrag and _touches.get(event.index) == "wheel":
		var center := control_rect("wheel").get_center()
		var ang: float = (event.position - center).angle()
		_wheel_angle = clampf(wrapf(ang - _wheel_start, -PI, PI), -2.0, 2.0)
		_apply_steer(_wheel_angle / 2.0)

func _press(k: String, down: bool, pos: Vector2) -> void:
	if k == "wheel":
		if down:
			_wheel_start = (pos - control_rect("wheel").get_center()).angle()
		else:
			_wheel_angle = 0.0
			_apply_steer(0.0)
		return
	var action: String = CONTROLS[k].action
	if action == "":
		return
	if down:
		Input.action_press(action, 1.0)
	else:
		Input.action_release(action)
	var b: Control = _buttons.get(k)
	if b:
		b.modulate = Color(1.3, 1.3, 1.5) if down else Color.WHITE

func _apply_steer(v: float) -> void:
	v = clampf(v * float(settings.get("sensitivity", 1.0)), -1.0, 1.0)
	if v > 0.02:
		Input.action_press(ZinoInput.STEER_RIGHT, v)
		Input.action_release(ZinoInput.STEER_LEFT)
	elif v < -0.02:
		Input.action_press(ZinoInput.STEER_LEFT, -v)
		Input.action_release(ZinoInput.STEER_RIGHT)
	else:
		Input.action_release(ZinoInput.STEER_LEFT)
		Input.action_release(ZinoInput.STEER_RIGHT)

func _process(_delta: float) -> void:
	if not visible or always_visible:
		return
	if str(settings.get("steering", "arrows")) == "tilt":
		var acc := Input.get_accelerometer()
		if acc != Vector3.ZERO:
			_apply_steer(acc.x / 6.0)
	if settings.get("autoAccelerate", false) and not _touches.values().has("brake"):
		Input.action_press(ZinoInput.ACCELERATE, 1.0)
