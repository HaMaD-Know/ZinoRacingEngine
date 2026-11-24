class_name ZinoReplay
extends Node
## Records every vehicle's transform during a race (30 Hz) and plays it back with a cinematic
## trackside camera that cuts between positions along the track, following the leader.

signal finished()

const RATE := 30.0
var recording := false
var playing := false
var vehicles: Array = []
var frames: Array = []                 # [{t, xf: [Transform3D per vehicle]}]
var track := PackedVector3Array()
var _t := 0.0
var _acc := 0.0
var _cam: Camera3D
var _prev_cam: Camera3D
var _cut_timer := 0.0

func start_recording(vs: Array) -> void:
	vehicles = vs
	frames.clear()
	_t = 0.0
	_acc = 0.0
	recording = true

func stop_recording() -> void:
	recording = false

func duration() -> float:
	return frames.back().t if not frames.is_empty() else 0.0

func _physics_process(delta: float) -> void:
	if recording:
		_t += delta
		_acc += delta
		if _acc >= 1.0 / RATE:
			_acc = 0.0
			var xf: Array = []
			for v in vehicles:
				xf.append(v.global_transform if is_instance_valid(v) else Transform3D.IDENTITY)
			frames.append({"t": _t, "xf": xf})

## Pose of vehicle i at replay time t (interpolated between recorded frames).
func pose_at(i: int, t: float) -> Transform3D:
	if frames.is_empty():
		return Transform3D.IDENTITY
	var lo := 0
	var hi := frames.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if frames[mid].t <= t:
			lo = mid
		else:
			hi = mid
	var a: Dictionary = frames[lo]
	var b: Dictionary = frames[hi]
	var k := 0.0 if b.t == a.t else clampf((t - a.t) / (b.t - a.t), 0.0, 1.0)
	return (a.xf[i] as Transform3D).interpolate_with(b.xf[i], k)

func play(camera_parent: Node) -> void:
	if frames.size() < 2:
		return
	stop_recording()
	playing = true
	_t = 0.0
	for v in vehicles:
		if is_instance_valid(v):
			v.freeze = true
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 50
	camera_parent.add_child(_cam)
	_cam.current = true
	_cut_timer = 0.0

func stop() -> void:
	if not playing:
		return
	playing = false
	if _cam:
		_cam.queue_free()
		_cam = null
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.current = true
	finished.emit()

func _process(delta: float) -> void:
	if not playing:
		return
	_t += delta
	if _t > duration():
		stop()
		return
	var lead := 0
	for i in vehicles.size():
		if is_instance_valid(vehicles[i]):
			vehicles[i].global_transform = pose_at(i, _t)
	# Trackside camera: cut every 4 s to the track point ahead of the leader, then pan to follow.
	var target := (vehicles[lead] as Node3D).global_position if is_instance_valid(vehicles[lead]) else Vector3.ZERO
	_cut_timer -= delta
	if _cut_timer <= 0.0 and track.size() > 2:
		_cut_timer = 4.0
		var best := 0
		var best_d := INF
		for k in track.size():
			var d := track[k].distance_squared_to(target)
			if d < best_d:
				best_d = d
				best = k
		var ahead := track[(best + 12) % track.size()]
		var side := (track[(best + 13) % track.size()] - ahead).normalized().cross(Vector3.UP)
		_cam.global_position = ahead + side * 14.0 + Vector3.UP * 4.0
	if _cam.global_position.distance_to(target) > 0.5:
		_cam.look_at(target + Vector3.UP * 0.8, Vector3.UP)
