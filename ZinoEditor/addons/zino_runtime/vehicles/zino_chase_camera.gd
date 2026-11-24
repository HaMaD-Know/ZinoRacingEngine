@tool
class_name ZinoChaseCamera
extends Camera3D
## Third-person chase camera with smoothing, look-ahead and speed-dependent field of view.
## Modes cycle with the "zino_camera_next" action: chase, close chase, hood, cinematic orbit.

const MODES := ["chase", "closeChase", "hood", "bumper", "cockpit", "orbit"]

var target: Node3D
@export var target_path: NodePath
@export var cam_data: Dictionary = {}
var follow_distance := 6.5
var follow_height := 2.1
var look_ahead := 4.0
var smoothing := 7.0
var base_fov := 65.0
var mode_index := 0
var _orbit_angle := 0.0

func setup(target_node: Node3D, data: Dictionary) -> void:
	target = target_node
	cam_data = data
	# Store a relative path so a scene saved from the Godot editor keeps the link.
	target_path = get_path_to(target_node)
	follow_distance = float(data.get("followDistance", 6.5))
	follow_height = float(data.get("followHeight", 2.1))
	look_ahead = float(data.get("lookAhead", 4.0))
	smoothing = float(data.get("smoothing", 7.0))
	base_fov = float(data.get("fov", 65.0))
	mode_index = maxi(0, MODES.find(str(data.get("startMode", "chase"))))
	fov = base_fov
	if target:
		global_transform = _desired_transform()

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	ZinoInput.ensure_actions()
	if target == null and not target_path.is_empty():
		var t := get_node_or_null(target_path) as Node3D
		if t:
			setup(t, cam_data)

func _unhandled_input(event: InputEvent) -> void:
	if current and event.is_action_pressed(ZinoInput.CAMERA):
		mode_index = (mode_index + 1) % MODES.size()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or target == null or not is_instance_valid(target):
		return
	var desired := _desired_transform()
	var mode: String = MODES[mode_index]
	if mode in ["hood", "bumper", "cockpit"]:
		global_transform = desired
	else:
		var w := 1.0 - exp(-smoothing * delta)
		global_position = global_position.lerp(desired.origin, w)
		var look_target := _look_target()
		if global_position.distance_to(look_target) > 0.01:
			look_at(look_target, Vector3.UP)
	var speed := 0.0
	if target is ZinoVehicle:
		speed = (target as ZinoVehicle).speed_kmh
	fov = lerpf(fov, base_fov + clampf(speed / 250.0, 0.0, 1.0) * 14.0, 1.0 - exp(-3.0 * delta))
	if mode == "orbit":
		_orbit_angle += delta * 0.35

func _desired_transform() -> Transform3D:
	var t := target.global_transform
	var fwd := -t.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var mode: String = MODES[mode_index]
	match mode:
		"closeChase":
			return Transform3D(Basis(), t.origin - fwd * follow_distance * 0.65 + Vector3.UP * follow_height * 0.75)
		"hood":
			return t * Transform3D(Basis(), Vector3(0, 0.75, -0.6))
		"bumper":
			return t * Transform3D(Basis(), Vector3(0, 0.05, -2.3))
		"cockpit":
			return t * Transform3D(Basis(), Vector3(-0.35, 0.62, 0.1))
		"orbit":
			var dir := fwd.rotated(Vector3.UP, _orbit_angle)
			return Transform3D(Basis(), t.origin - dir * follow_distance * 1.6 + Vector3.UP * follow_height * 1.4)
		_:
			return Transform3D(Basis(), t.origin - fwd * follow_distance + Vector3.UP * follow_height)

func _look_target() -> Vector3:
	var t := target.global_transform
	var fwd := -t.basis.z
	return t.origin + fwd * look_ahead + Vector3.UP * 0.8
