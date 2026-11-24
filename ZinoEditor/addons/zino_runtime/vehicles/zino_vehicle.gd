@tool
class_name ZinoVehicle
extends VehicleBody3D
## Zino universal vehicle: Godot's VehicleBody3D (raycast suspension on the physics engine's rigid body)
## plus Zino extensions — engine RPM model, automatic/manual gearbox, speed-sensitive steering,
## handbrake, downforce and aerodynamic drag. All physics profiles configure this one class.

signal gear_changed(gear: int)
signal collided(impact_speed: float, other: Node)

## Godot's VehicleBody3D drives along the body's local +Z axis for positive engine force,
## while Zino (and Godot) treat -Z as "forward" for models and cameras. We therefore push
## with a negative engine force for forward motion. Verified by tests/test_vehicle.gd.
const ENGINE_FORWARD_SIGN := -1.0

@export var spec: Dictionary = {}
@export var input_enabled := false
var throttle := 0.0
var brake_input := 0.0
var steer_input := 0.0
var handbrake_input := false

var gear := 1          # -1 reverse, 0 neutral, 1..n forward
var rpm := 900.0
var speed_kmh := 0.0
var forward_speed := 0.0   # m/s along the vehicle's -Z
var spawn_transform := Transform3D.IDENTITY

## Script / AI control: values set here replace player input for that channel.
var override := {}                 # keys: throttle, brake, steer, handbrake
var power_multiplier := 1.0
var top_speed_override := 0.0
var nitro_time_left := 0.0
var nitro_strength := 1.0
var display_name := ""
var _last_velocity := Vector3.ZERO

var _wheels: Array[VehicleWheel3D] = []
var _steer := 0.0
var _shift_cooldown := 0.0

func configure(vehicle_spec: Dictionary) -> void:
	spec = vehicle_spec
	mass = float(spec.get("massKg", 1350.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = ZinoFormat.v3(spec.get("centerOfMass"), Vector3(0, -0.3, 0))
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	for w in _wheels:
		w.queue_free()
	_wheels.clear()
	var radius := float(spec.get("wheelRadius", 0.34))
	var width := float(spec.get("wheelWidth", 0.26))
	for wspec in spec.get("wheels", []):
		var w := VehicleWheel3D.new()
		w.name = "Wheel_" + str(wspec.get("name", _wheels.size()))
		w.position = ZinoFormat.v3(wspec.get("position"))
		w.wheel_radius = radius
		w.wheel_rest_length = float(spec.get("suspensionRestLength", 0.18))
		w.suspension_travel = float(spec.get("suspensionTravel", 0.25))
		w.suspension_stiffness = float(spec.get("suspensionStiffness", 45.0))
		w.suspension_max_force = mass * 9.81 * 2.0
		w.damping_compression = float(spec.get("dampingCompression", 3.4)) * 0.1
		w.damping_relaxation = float(spec.get("dampingRelaxation", 4.2)) * 0.1
		w.wheel_roll_influence = float(spec.get("rollInfluence", 0.08))
		var rear: bool = wspec.get("handbrake", false)
		w.wheel_friction_slip = float(spec.get("rearFrictionSlip" if rear else "tireFrictionSlip", 3.2))
		w.use_as_traction = wspec.get("drive", false)
		w.use_as_steering = wspec.get("steer", false)
		w.set_meta("zino_handbrake", rear)
		w.add_child(_build_wheel_visual(radius, width, w.position.x < 0))
		add_child(w)
		_wheels.append(w)

func wheel_count() -> int:
	return _wheels.size()

func wheels() -> Array[VehicleWheel3D]:
	return _wheels

func grounded_wheels() -> int:
	var n := 0
	for w in _wheels:
		if w.is_in_contact():
			n += 1
	return n

func reset_to_spawn() -> void:
	global_transform = spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gear = 1
	_steer = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	ZinoInput.ensure_actions()
	spawn_transform = global_transform
	body_entered.connect(_on_body_entered)
	# Loaded from a saved .tscn: wheels already exist as children, collect them.
	if _wheels.is_empty():
		for c in get_children():
			if c is VehicleWheel3D:
				_wheels.append(c)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or spec.is_empty() or freeze:
		return
	if input_enabled:
		_read_input()
	if override.has("throttle"): throttle = override.throttle
	if override.has("brake"): brake_input = override.brake
	if override.has("steer"): steer_input = override.steer
	if override.has("handbrake"): handbrake_input = override.handbrake
	nitro_time_left = maxf(0.0, nitro_time_left - delta)
	_last_velocity = linear_velocity
	var fwd := -global_transform.basis.z
	forward_speed = linear_velocity.dot(fwd)
	speed_kmh = linear_velocity.length() * 3.6
	_update_steering(delta)
	_update_drivetrain(delta)
	_apply_aero()

func _read_input() -> void:
	throttle = Input.get_action_strength(ZinoInput.ACCELERATE)
	brake_input = Input.get_action_strength(ZinoInput.BRAKE)
	steer_input = Input.get_action_strength(ZinoInput.STEER_RIGHT) - Input.get_action_strength(ZinoInput.STEER_LEFT)
	handbrake_input = Input.is_action_pressed(ZinoInput.HANDBRAKE)
	if Input.is_action_just_pressed(ZinoInput.RESET):
		reset_to_spawn()
	if not spec.get("automatic", true):
		var ratios: Array = spec.get("gearRatios", [1.0])
		if Input.is_action_just_pressed(ZinoInput.SHIFT_UP) and gear < ratios.size():
			gear = maxi(1, gear + 1)
			gear_changed.emit(gear)
		elif Input.is_action_just_pressed(ZinoInput.SHIFT_DOWN):
			gear = maxi(-1, gear - 1) if gear != 1 else -1
			gear_changed.emit(gear)

func _update_steering(delta: float) -> void:
	var top := maxf(10.0, float(spec.get("topSpeedKmh", 230.0)))
	var factor := lerpf(1.0, float(spec.get("highSpeedSteerFactor", 0.4)), clampf(speed_kmh / top, 0.0, 1.0))
	var target := -steer_input * deg_to_rad(float(spec.get("maxSteerAngle", 32.0))) * factor
	_steer = move_toward(_steer, target, float(spec.get("steerSpeed", 3.5)) * delta)
	steering = _steer

func _update_drivetrain(delta: float) -> void:
	var ratios: Array = spec.get("gearRatios", [3.3, 2.2, 1.6, 1.25, 1.0, 0.82])
	var final_drive := float(spec.get("finalDrive", 3.7))
	var idle := float(spec.get("idleRpm", 900.0))
	var max_rpm := float(spec.get("maxRpm", 7200.0))
	var radius := float(spec.get("wheelRadius", 0.34))
	var top_ms := (top_speed_override if top_speed_override > 0.0 else float(spec.get("topSpeedKmh", 230.0))) / 3.6
	if nitro_time_left > 0.0:
		top_ms *= 1.0 + (nitro_strength - 1.0) * 0.5
	_shift_cooldown = maxf(0.0, _shift_cooldown - delta)

	# Direction logic: braking while (nearly) stopped engages reverse; throttle selects forward.
	var want_forward := throttle > 0.05
	var want_back := brake_input > 0.05
	if spec.get("automatic", true):
		if gear == -1 and want_forward and forward_speed > -1.0:
			gear = 1
			gear_changed.emit(gear)
		elif gear >= 1 and want_back and forward_speed < 0.8 and throttle < 0.05:
			gear = -1
			gear_changed.emit(gear)

	var ratio: float = float(spec.get("reverseRatio", 3.2)) if gear == -1 else float(ratios[clampi(gear - 1, 0, ratios.size() - 1)])
	var neutral := gear == 0
	var wheel_rpm := absf(forward_speed) / (TAU * radius) * 60.0
	rpm = clampf(wheel_rpm * ratio * final_drive, idle, max_rpm * 1.05)

	if spec.get("automatic", true) and gear >= 1 and _shift_cooldown <= 0.0:
		if rpm > max_rpm * 0.9 and gear < ratios.size():
			gear += 1
			_shift_cooldown = 0.45
			gear_changed.emit(gear)
		elif rpm < max_rpm * 0.42 and gear > 1:
			gear -= 1
			_shift_cooldown = 0.45
			gear_changed.emit(gear)

	# Torque multiplication relative to first gear, with a soft rev limiter and top-speed cap.
	var first: float = float(ratios[0])
	var gear_mult := clampf(ratio / first, 0.25, 1.4)
	var limiter := 1.0 - smoothstep(max_rpm * 0.97, max_rpm * 1.03, rpm)
	var cap := 1.0 - smoothstep(top_ms * 0.95, top_ms, absf(forward_speed))
	var force := float(spec.get("maxEngineForce", 6500.0)) * gear_mult * limiter * cap * power_multiplier
	if nitro_time_left > 0.0:
		force *= nitro_strength
	var drive := 0.0
	var braking := 0.0
	if gear == -1:
		drive = -force * 0.6 * brake_input
		braking = float(spec.get("maxBrakeForce", 90.0)) * throttle
	else:
		drive = force * throttle
		braking = float(spec.get("maxBrakeForce", 90.0)) * brake_input
	if neutral:
		drive = 0.0
	engine_force = drive * ENGINE_FORWARD_SIGN
	var hb := float(spec.get("handbrakeForce", 140.0)) if handbrake_input else 0.0
	for w in _wheels:
		w.brake = braking + (hb if w.get_meta("zino_handbrake", false) else 0.0)
	# Gentle engine braking when coasting.
	if throttle < 0.05 and brake_input < 0.05 and not handbrake_input:
		for w in _wheels:
			w.brake = maxf(w.brake, 1.5)

## Sets the gear directly (used by scripts and manual gearboxes). 0 = neutral, -1 = reverse.
func set_gear(g: int) -> void:
	var ratios: Array = spec.get("gearRatios", [1.0])
	gear = clampi(g, -1, ratios.size())
	gear_changed.emit(gear)

func nitro(seconds: float, strength: float) -> void:
	nitro_time_left = maxf(nitro_time_left, seconds)
	nitro_strength = maxf(1.0, strength)

func _on_body_entered(other: Node) -> void:
	var impact := (_last_velocity - linear_velocity).length()
	if impact > 1.5:
		collided.emit(impact * 3.6, other)

func _apply_aero() -> void:
	var v := linear_velocity
	var speed := v.length()
	if speed < 0.5:
		return
	var down := float(spec.get("downforce", 2.5))
	if grounded_wheels() > 0:
		apply_central_force(-global_transform.basis.y * down * speed * speed)
	var drag := float(spec.get("dragCoefficient", 0.32))
	apply_central_force(-v.normalized() * drag * 1.2 * 2.2 * 0.5 * speed * speed)

func _build_wheel_visual(radius: float, width: float, left_side: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var tire := MeshInstance3D.new()
	tire.name = "Tire"
	var tm := CylinderMesh.new()
	tm.top_radius = radius
	tm.bottom_radius = radius
	tm.height = width
	tm.radial_segments = 32
	tm.rings = 1
	tire.mesh = tm
	tire.rotation_degrees = Vector3(0, 0, 90)
	tire.material_override = ZinoMaterials.get_material({"preset": "rubber"})
	root.add_child(tire)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var rm := CylinderMesh.new()
	rm.top_radius = radius * 0.62
	rm.bottom_radius = radius * 0.62
	rm.height = width * 1.02
	rm.radial_segments = 24
	rim.mesh = rm
	rim.rotation_degrees = Vector3(0, 0, 90)
	rim.material_override = ZinoMaterials.get_material({"preset": "metal", "color": [0.78, 0.79, 0.8, 1.0], "metallic": 1.0, "roughness": 0.18})
	root.add_child(rim)
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var hm := CylinderMesh.new()
	hm.top_radius = radius * 0.16
	hm.bottom_radius = radius * 0.16
	hm.height = width * 1.08
	hub.mesh = hm
	hub.rotation_degrees = Vector3(0, 0, 90)
	hub.material_override = ZinoMaterials.get_material({"preset": "metal", "color": [0.2, 0.2, 0.22, 1.0], "metallic": 1.0, "roughness": 0.35})
	root.add_child(hub)
	return root
