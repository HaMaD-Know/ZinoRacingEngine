class_name ZinoAIDriver
extends Node
## Drives one ZinoVehicle along a racing line using the same controls a player has
## (throttle, brake, steering) — no teleporting. Plans corner speeds from path curvature,
## overtakes by shifting laterally, and recovers when stuck.

var vehicle: ZinoVehicle
var path := PackedVector3Array()      # racing line (world space)
var closed := true
var difficulty := 0.7                 # 0..1 → fraction of the theoretical corner speed
var behavior := "balanced"            # cautious, balanced, aggressive
var follow_line := true
var target_override = null            # Vector3: drive to a point instead of the line
var others: Array = []                # other vehicles (for overtaking)
var active := true
var lateral_offset := 0.0
var _index := 0
var _stuck_time := 0.0
var _reverse_time := 0.0
var _flip_time := 0.0
var _offtrack_time := 0.0
var respawns := 0
var speed_limit_kmh := 0.0           # traffic: cruise at this speed (0 = race flat out)
var lane_offset := 0.0               # traffic: drive in a lane, metres right of the line

func setup(v: ZinoVehicle, line: PackedVector3Array, is_closed: bool) -> void:
	vehicle = v
	path = line
	closed = is_closed
	_index = _nearest_index(v.global_position, 0, path.size())

func _physics_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or path.size() < 2:
		return
	if not active:
		vehicle.override = {"throttle": 0.0, "brake": 0.3, "steer": 0.0}
		return
	if vehicle.override.get("brake", 0.0) >= 1.0 and vehicle.override.get("throttle", 1.0) == 0.0 and vehicle.override.size() == 2:
		return   # held on the grid by the race manager during the countdown
	var pos := vehicle.global_position
	_index = _nearest_index(pos, _index - 5, 40)
	# Crash recovery: upside down for 1.5 s, or stranded far from the track for 3 s → back on the line.
	_flip_time = _flip_time + delta if vehicle.global_transform.basis.y.y < 0.35 else 0.0
	_offtrack_time = _offtrack_time + delta if pos.distance_to(path[_index]) > 25.0 else 0.0
	if _flip_time > 1.5 or _offtrack_time > 3.0:
		respawn_on_track()
		return
	var speed := absf(vehicle.forward_speed)
	var look := clampf(6.0 + speed * 0.55, 6.0, 40.0)
	var target: Vector3 = target_override if target_override is Vector3 else _point_ahead(look)
	if not (target_override is Vector3):
		target += _lateral(_index) * (lateral_offset + lane_offset)
	# Open roads: turn around at the end (traffic keeps circulating).
	if not closed and _index >= path.size() - 3 and pos.distance_to(path[path.size() - 1]) < 12.0:
		path.reverse()
		_index = _nearest_index(pos, 0, path.size())

	# Steering: signed angle between forward and the target direction (left = negative input).
	var fwd := -vehicle.global_transform.basis.z
	fwd.y = 0.0
	var to_t := target - pos
	to_t.y = 0.0
	var angle := fwd.signed_angle_to(to_t.normalized(), Vector3.UP)
	var steer := clampf(-angle / deg_to_rad(float(vehicle.spec.get("maxSteerAngle", 32.0))) * 1.3, -1.0, 1.0)

	# Speed planning: the tightest corner within braking distance sets the target speed.
	var grip: float = {"cautious": 0.75, "balanced": 0.9, "aggressive": 1.05}.get(behavior, 0.9) * lerpf(0.72, 1.0, clampf(difficulty, 0.0, 1.0))
	var max_speed := float(vehicle.spec.get("topSpeedKmh", 230.0)) / 3.6
	var target_speed := max_speed
	var brake_dist := speed * speed / (2.0 * 9.0) + 15.0
	var travelled := 0.0
	var i := _index
	var steps := 0
	while travelled < brake_dist and steps < 200:
		var a := path[_wrap(i)]
		var b := path[_wrap(i + 1)]
		var c := path[_wrap(i + 2)]
		var r := _radius(a, b, c)
		var v_corner := sqrt(maxf(1.0, r) * 9.81 * 1.1 * grip)
		# Allowed speed now so that we can still brake down to v_corner at that distance.
		var v_allowed := sqrt(v_corner * v_corner + 2.0 * 8.0 * travelled)
		target_speed = minf(target_speed, v_allowed)
		travelled += a.distance_to(b)
		i += 1
		steps += 1
		if not closed and _wrap(i) >= path.size() - 2:
			break
	if target_override is Vector3:
		target_speed = minf(target_speed, maxf(3.0, pos.distance_to(target) * 0.5))
	if speed_limit_kmh > 0.0:
		target_speed = minf(target_speed, speed_limit_kmh / 3.6)

	var throttle := 0.0
	var brake := 0.0
	var err := target_speed - speed
	if err > 0.0:
		throttle = clampf(err / 4.0, 0.15, 1.0)
	else:
		brake = clampf(-err / 6.0, 0.0, 1.0)
	_overtake(delta, pos, fwd)

	# Recovery: stuck against something for 2 s → reverse briefly, then carry on.
	if _reverse_time > 0.0:
		_reverse_time -= delta
		vehicle.override = {"throttle": 0.0, "brake": 1.0, "steer": -steer, "handbrake": false}
		return
	if throttle > 0.3 and speed < 1.0:
		_stuck_time += delta
		if _stuck_time > 2.0:
			_stuck_time = 0.0
			_reverse_time = 1.4
	else:
		_stuck_time = 0.0
	vehicle.override = {"throttle": throttle, "brake": brake, "steer": steer, "handbrake": false}

## Places the car back on the racing line at its current progress, facing forward, at rest.
func respawn_on_track() -> void:
	_flip_time = 0.0
	_offtrack_time = 0.0
	_stuck_time = 0.0
	_reverse_time = 0.0
	respawns += 1
	var p := path[_index]
	var ahead := path[_wrap(_index + 3)]
	var dir := (ahead - p)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var ride := float(vehicle.spec.get("wheelRadius", 0.34)) + float(vehicle.spec.get("suspensionRestLength", 0.18)) + ZinoFormat.v3(vehicle.spec.get("bodySize"), Vector3(1.8, 0.6, 4.3)).y * 0.5 + 0.3
	vehicle.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p + Vector3.UP * ride)
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO

func _overtake(delta: float, pos: Vector3, fwd: Vector3) -> void:
	var want := 0.0
	for o in others:
		if o == vehicle or not is_instance_valid(o):
			continue
		var rel: Vector3 = o.global_position - pos
		var ahead := rel.dot(fwd)
		if ahead > 0.0 and ahead < 14.0 and absf(rel.dot(fwd.cross(Vector3.UP))) < 3.0:
			want = 3.0 if rel.dot(fwd.cross(Vector3.UP)) < 0.0 else -3.0
			if behavior == "cautious":
				want *= 0.5
	lateral_offset = move_toward(lateral_offset, want, delta * 2.0)

func _point_ahead(distance: float) -> Vector3:
	var d := 0.0
	var i := _index
	for _n in 400:
		var a := path[_wrap(i)]
		var b := path[_wrap(i + 1)]
		var seg := a.distance_to(b)
		if d + seg >= distance:
			return a.lerp(b, (distance - d) / maxf(seg, 0.001))
		d += seg
		i += 1
		if not closed and _wrap(i) >= path.size() - 1:
			return path[path.size() - 1]
	return path[_wrap(i)]

func _lateral(i: int) -> Vector3:
	var t := (path[_wrap(i + 1)] - path[_wrap(i)])
	t.y = 0
	return t.normalized().cross(Vector3.UP)

func _nearest_index(p: Vector3, start: int, count: int) -> int:
	var best := _wrap(start)
	var best_d := INF
	for k in mini(count, path.size()):
		var idx := _wrap(start + k)
		var d := path[idx].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = idx
	return best

func _wrap(i: int) -> int:
	if closed:
		return posmod(i, path.size())
	return clampi(i, 0, path.size() - 1)

static func _radius(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var bc := Vector2(c.x - b.x, c.z - b.z)
	var ca := Vector2(a.x - c.x, a.z - c.z)
	var cross := absf(ab.x * bc.y - ab.y * bc.x)
	if cross < 0.0001:
		return 100000.0
	return ab.length() * bc.length() * ca.length() / (2.0 * cross)
