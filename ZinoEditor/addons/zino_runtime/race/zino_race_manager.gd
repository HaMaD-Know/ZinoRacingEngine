class_name ZinoRaceManager
extends Node
## Universal race manager: countdown, checkpoint order, laps, lap/sector timing, live positions,
## finish detection, results and restart. Race rules (modes):
##   circuit     — laps over a closed track
##   sprint      — point to point, finish at the last checkpoint
##   timeTrial   — solo laps against the clock; the race ends after `laps` laps, best lap kept
##   elimination — circuit where the last car is eliminated every time the leader completes a lap

signal countdown_started(seconds: float)
signal countdown_tick(value: int)
signal race_started()
signal checkpoint_passed(racer: Racer, index: int)
signal lap_completed(racer: Racer, lap: int, lap_time: float)
signal racer_finished(racer: Racer, position: int, total_time: float)
signal race_finished()
signal racer_eliminated(racer: Racer)

class Racer:
	var vehicle: ZinoVehicle
	var name := ""
	var is_player := false
	var lap := 1
	var next_checkpoint := 1
	var checkpoints_passed := 0          # total, for ordering
	var lap_start := 0.0
	var last_lap := 0.0
	var best_lap := 0.0
	var sectors: Array = []               # sector times of the current lap
	var last_checkpoint := 0
	var finished := false
	var eliminated := false
	var total_time := 0.0
	var last_sectors: Array = []           # sector times of the previous lap
	var position := 1
	var clock := 0.0                      # race clock, set by the manager each frame
	func lap_time() -> float:
		return clock - lap_start

var laps := 3
var countdown := 3.0
var mode := "circuit"
var state := "idle"                      # idle, countdown, racing, finished
var racers: Array = []
var checkpoints := {}                    # index -> Area3D
var max_index := 0
var race_time := 0.0
var finish_order: Array = []
var _countdown_left := 0.0
var _last_tick := -1

## Collects checkpoint areas and racers from a built scene.
func setup(builder: ZinoSceneBuilder, vehicles: Array, race_settings: Dictionary) -> void:
	laps = maxi(1, int(race_settings.get("laps", 3)))
	countdown = maxf(0.0, float(race_settings.get("countdown", 3.0)))
	checkpoints.clear()
	var closed := false
	for e in builder.scene.get("entities", []):
		if e.get("type") in [ZinoEntities.TYPE_CHECKPOINT, ZinoEntities.TYPE_START_FINISH]:
			var area := builder.node_for(e["id"]) as Area3D
			if area:
				var idx := int(e.get("trigger", {}).get("index", 0))
				checkpoints[idx] = area
				area.monitoring = true
				if not area.body_entered.is_connected(_on_area_entered):
					area.body_entered.connect(_on_area_entered.bind(idx))
		elif e.get("type") == ZinoEntities.TYPE_ROAD and e.get("road", {}).get("closed", false):
			closed = true
	max_index = 0
	for k in checkpoints:
		max_index = maxi(max_index, k)
	var m := str(race_settings.get("mode", "auto"))
	mode = m if m in ["circuit", "sprint", "timeTrial", "elimination"] else ("circuit" if closed else "sprint")
	if mode in ["circuit", "timeTrial", "elimination"] and not closed and not checkpoints.has(0):
		mode = "sprint"
	racers.clear()
	for v in vehicles:
		var r := Racer.new()
		r.vehicle = v
		r.name = v.display_name if v.display_name != "" else str(v.name)
		r.is_player = v.input_enabled
		racers.append(r)

func has_track() -> bool:
	return not checkpoints.is_empty()

func racer_for(v) -> Racer:
	for r in racers:
		if r.vehicle == v:
			return r
	return null

func player() -> Racer:
	for r in racers:
		if r.is_player:
			return r
	return racers[0] if not racers.is_empty() else null

## Starts the countdown (or the race directly when countdown is 0).
func start() -> void:
	race_time = 0.0
	finish_order.clear()
	for r in racers:
		r.lap = 1
		r.next_checkpoint = 1 if max_index >= 1 else 0
		r.checkpoints_passed = 0
		r.last_lap = 0.0
		r.best_lap = 0.0
		r.sectors = []
		r.finished = false
		r.eliminated = false
		r.last_sectors = []
		r.total_time = 0.0
		r.last_checkpoint = 0
		r.lap_start = 0.0
		r.vehicle.override = {"throttle": 0.0, "brake": 1.0}
	state = "countdown"
	_countdown_left = countdown
	_last_tick = -1
	countdown_started.emit(countdown)
	if countdown <= 0.0:
		_go()

func stop() -> void:
	state = "idle"
	for r in racers:
		r.vehicle.override = {}

func restart() -> void:
	for r in racers:
		r.vehicle.reset_to_spawn()
	start()

## Ends the race for one racer immediately (e.g. from a block).
func finish_racer(r: Racer) -> void:
	if r == null or r.finished:
		return
	r.finished = true
	r.total_time = race_time
	finish_order.append(r)
	r.vehicle.override = {"throttle": 0.0, "brake": 0.4}
	racer_finished.emit(r, finish_order.size(), r.total_time)
	if racers.all(func(x): return x.finished) or (r.is_player and _player_only()):
		_end()

func _player_only() -> bool:
	return racers.size() == 1

func _go() -> void:
	state = "racing"
	race_time = 0.0
	for r in racers:
		r.vehicle.override = {}
		r.lap_start = 0.0
	race_started.emit()

func _end() -> void:
	if state == "finished":
		return
	state = "finished"
	# Unfinished racers are classified by progress.
	_update_positions()
	race_finished.emit()

func _physics_process(delta: float) -> void:
	match state:
		"countdown":
			_countdown_left -= delta
			var tick := int(ceil(_countdown_left))
			if tick != _last_tick and tick > 0:
				_last_tick = tick
				countdown_tick.emit(tick)
			if _countdown_left <= 0.0:
				countdown_tick.emit(0)
				_go()
		"racing", "finished":
			if state == "racing":
				race_time += delta
			for r in racers:
				r.clock = race_time
			_update_positions()

func _on_area_entered(body: Node, index: int) -> void:
	if state != "racing":
		return
	var r := racer_for(body)
	if r == null or r.finished:
		return
	if index != r.next_checkpoint:
		return   # wrong order or a repeated crossing
	r.last_checkpoint = index
	r.checkpoints_passed += 1
	r.sectors.append(r.lap_time())
	checkpoint_passed.emit(r, index)
	if mode == "sprint":
		if index >= max_index:
			r.last_lap = r.lap_time()
			r.best_lap = r.last_lap
			finish_racer(r)
		else:
			r.next_checkpoint = _next_index(index)
		return
	if index == 0:
		# Crossed start/finish after all checkpoints: lap complete.
		var t := r.lap_time()
		r.last_lap = t
		r.best_lap = t if r.best_lap <= 0.0 else minf(r.best_lap, t)
		lap_completed.emit(r, r.lap, t)
		r.lap_start = race_time
		r.last_sectors = r.sectors
		r.sectors = []
		if mode == "elimination" and r.position == 1:
			_eliminate_last()
		if r.lap >= laps:
			finish_racer(r)
			return
		r.lap += 1
	r.next_checkpoint = _next_index(index)

func _eliminate_last() -> void:
	var alive: Array = racers.filter(func(x): return not x.finished)
	if alive.size() <= 1:
		return
	alive.sort_custom(func(a, b): return _progress(a) > _progress(b))
	var last: Racer = alive.back()
	last.eliminated = true
	last.finished = true
	last.total_time = race_time
	last.vehicle.override = {"throttle": 0.0, "brake": 0.5}
	racer_eliminated.emit(last)
	var still: Array = racers.filter(func(x): return not x.finished)
	if still.size() == 1:
		finish_racer(still[0])

func _next_index(index: int) -> int:
	var keys := checkpoints.keys()
	keys.sort()
	for k in keys:
		if k > index:
			return k
	return 0 if mode == "circuit" and checkpoints.has(0) else keys[0]

func _progress(r: Racer) -> float:
	var target = checkpoints.get(r.next_checkpoint)
	if not is_instance_valid(r.vehicle) or target == null or not is_instance_valid(target):
		return r.checkpoints_passed * 100000.0
	var dist: float = r.vehicle.global_position.distance_to((target as Area3D).global_position)
	return r.checkpoints_passed * 100000.0 - dist

func _update_positions() -> void:
	var ordered: Array = finish_order.filter(func(r): return not r.eliminated)
	var rest: Array = racers.filter(func(r): return not r.finished)
	rest.sort_custom(func(a, b): return _progress(a) > _progress(b))
	ordered.append_array(rest)
	# Eliminated racers are classified behind everyone still racing, latest elimination first.
	var out: Array = racers.filter(func(r): return r.eliminated)
	out.sort_custom(func(a, b): return a.total_time > b.total_time)
	ordered.append_array(out)
	for i in ordered.size():
		ordered[i].position = i + 1

func results() -> Array:
	_update_positions()
	var rows: Array = []
	for r in racers:
		rows.append({"name": r.name, "position": r.position, "time": r.total_time if r.finished else race_time, "best_lap": r.best_lap,
			"finished": r.finished and not r.eliminated, "eliminated": r.eliminated, "player": r.is_player, "sectors": r.last_sectors})
	rows.sort_custom(func(a, b): return a.position < b.position)
	return rows
