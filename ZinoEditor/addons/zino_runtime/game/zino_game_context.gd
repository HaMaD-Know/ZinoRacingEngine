class_name ZinoGameContext
extends Node
## A running Zino game session: race manager, AI opponents, HUD, audio, environment, camera and the
## block runtime. Used by the editor playtest and by exported games (zino_game.gd), so both behave
## identically. Implements every game-facing block for ZinoBlockRuntime.

signal quit_requested()

var builder: ZinoSceneBuilder
var scene: Dictionary
var project_root := "res://"
var save_key := "game"
var race: ZinoRaceManager
var hud: ZinoHud
var audio: ZinoAudio
var environment: ZinoEnvironment
var blocks: ZinoBlockRuntime
var ai_drivers: Array = []
var ai_vehicles: Array = []
var replay: ZinoReplay
var traffic: Array = []
var speed_fx: ZinoSpeedFx
var score := 0.0
var last_impact := 0.0
var _track := PackedVector3Array()
var _track_closed := false
var _camera_shake := 0.0
var _camera_shake_strength := 0.0
var _paused := false
var _save := {}

## settings: scene settings; programs: compiled block IR list; options: {ai_count?, start_race?}
func start(scene_builder: ZinoSceneBuilder, root_project: String, programs: Array, options: Dictionary = {}) -> void:
	builder = scene_builder
	scene = builder.scene
	project_root = root_project
	save_key = str(options.get("save_key", "game")).validate_filename()
	_load_save()
	var settings: Dictionary = scene.get("settings", {})
	var race_settings: Dictionary = settings.get("race", {})
	_collect_track()

	audio = ZinoAudio.new()
	audio.project_root = project_root
	audio.settings.merge(settings.get("audio", {}), true)
	add_child(audio)
	var aset: Dictionary = settings.get("audio", {})
	if str(aset.get("music", "")) != "":
		var merr := audio.play_music(str(aset.music), aset.get("musicLoop", true))
		if merr != "":
			push_warning("Zino music: " + merr)
	environment = ZinoEnvironment.new()
	add_child(environment)
	environment.camera_provider = func(): return get_viewport().get_camera_3d() if is_inside_tree() else null
	environment.setup(builder.environment_node(), _find_sun(), settings)

	var player := builder.player_vehicle()
	if player:
		player.display_name = "You"
	var ai_count := int(options.get("ai_count", race_settings.get("aiOpponents", 0))) if race_settings.get("enabled", true) else 0
	if str(race_settings.get("mode", "")) == "timeTrial":
		ai_count = 0
	if player and _track.size() > 1 and ai_count > 0:
		_spawn_ai(player, ai_count, race_settings)
	_spawn_traffic(settings.get("traffic", {}))
	for v in all_vehicles():
		audio.attach_vehicle(v)
		v.collided.connect(func(impact, _o): _on_collision(v, impact))

	if settings.get("postFx", {}).get("speedBlur", true):
		speed_fx = ZinoSpeedFx.new()
		speed_fx.context = self
		add_child(speed_fx)
	hud = ZinoHud.new()
	hud.context = self
	add_child(hud)
	hud.apply_layout(settings.get("hud", {}))
	hud.menu_action.connect(_on_menu_action)
	var touch := ZinoTouchControls.new()
	touch.settings = settings.get("touch", {})
	touch.always_visible = bool(options.get("show_touch", false))
	add_child(touch)
	touch.apply_layout(settings.get("touch", {}).get("controls", {}))
	var player_car := builder.player_vehicle()
	if player_car and settings.get("touch", {}).has("automatic") and ZinoTouchControls.should_show():
		player_car.spec["automatic"] = bool(settings.touch.automatic)

	race = ZinoRaceManager.new()
	add_child(race)
	race.setup(builder, all_vehicles(), race_settings)
	race.countdown_tick.connect(_on_countdown_tick)
	race.countdown_started.connect(func(_s): _fire("ev_countdown"))
	race.race_started.connect(func():
		_fire("ev_race_start")
		_set_ai_active(true))
	race.lap_completed.connect(func(r, lap, t):
		if r.is_player:
			hud.show_message("Lap %d  %s" % [lap, ZinoBlockRuntime.format_lap_time(t)], 2.5)
			_fire("ev_lap"))
	race.checkpoint_passed.connect(func(r, _i):
		if r.is_player:
			_fire("ev_checkpoint"))
	race.racer_finished.connect(func(r, pos, _t):
		if r.is_player:
			_fire("ev_race_finish")
			hud.show_big("P%d" % pos, 3.0))
	race.race_finished.connect(func():
		replay.stop_recording()
		hud.show_results(race.results()))
	race.racer_eliminated.connect(func(r): hud.show_message("%s eliminated" % r.name, 2.5))
	replay = ZinoReplay.new()
	add_child(replay)
	replay.track = _track
	race.race_started.connect(func(): replay.start_recording(all_vehicles()))
	replay.finished.connect(func(): hud.show_results(race.results()))
	for idx in race.checkpoints:
		var area: Area3D = race.checkpoints[idx]
		var area_name := str(area.name)
		area.body_entered.connect(func(b):
			if b == builder.player_vehicle():
				_fire("ev_area", {"area": area_name}))

	blocks = ZinoBlockRuntime.new()
	blocks.context = self
	add_child(blocks)
	blocks.load_programs(programs)
	blocks.log_message.connect(func(level, text): print("[Zino Blocks] %s: %s" % [level, text]))
	_fire("ev_game_start")
	_fire("ev_player_join")
	var auto_start: bool = race_settings.get("enabled", true) and race_settings.get("autoStart", true) and race.has_track()
	if bool(options.get("start_race", auto_start)):
		race.start()
	else:
		_set_ai_active(true)

func _on_countdown_tick(n: int) -> void:
	hud.show_countdown("GO!" if n == 0 else str(n))
	if n == 0:
		get_tree().create_timer(0.8).timeout.connect(func(): hud.show_countdown(""))

func _fire(event: String, filter: Dictionary = {}) -> void:
	if blocks:
		blocks.fire(event, filter)

func _find_sun() -> DirectionalLight3D:
	for e in scene.get("entities", []):
		if e.get("type") == ZinoEntities.TYPE_LIGHT and e.get("light", {}).get("kind") == "directional":
			return builder.node_for(e["id"]) as DirectionalLight3D
	return null

func _collect_track() -> void:
	for e in scene.get("entities", []):
		if e.get("type") == ZinoEntities.TYPE_ROAD:
			var node := builder.node_for(e["id"])
			var xf := node.global_transform if node else Transform3D.IDENTITY
			_track = ZinoTrackTools.racing_line(e["road"], xf) if e["road"].get("racingLine", true) else ZinoTrackTools.world_centerline(e["road"], xf)
			_track_closed = e["road"].get("closed", false)
			if _track_closed:
				return   # prefer a closed circuit for the racing line

func track_points() -> PackedVector3Array:
	return _track

func track_closed() -> bool:
	return _track_closed

func all_vehicles() -> Array:
	var out: Array = []
	for id in builder.nodes:
		var n := builder.node_for(id)
		if n is ZinoVehicle:
			out.append(n)
	out.append_array(ai_vehicles.filter(func(v): return is_instance_valid(v)))
	return out

func vehicle(name_or_player) -> ZinoVehicle:
	var key := str(name_or_player)
	if key == "" or key == "player":
		return builder.player_vehicle()
	for v in all_vehicles():
		if v.display_name == key or str(v.name) == key:
			return v
	return null

# --- AI opponents ---------------------------------------------------------------------------

func _spawn_ai(player: ZinoVehicle, count: int, race_settings: Dictionary) -> void:
	var base := player.global_transform
	var fwd := -base.basis.z
	var right := base.basis.x
	var colors := [Color("0a84ff"), Color("30d158"), Color("ffd60a"), Color("bf5af2"), Color("f5f5f7"), Color("ff9f0a"), Color("64d2ff")]
	# Grid slots from the scene, ordered by grid index.
	var slot_entities: Array = scene.get("entities", []).filter(func(e): return e.get("type") == ZinoEntities.TYPE_SPAWN)
	slot_entities.sort_custom(func(a, b): return int(a.get("spawn", {}).get("gridIndex", 0)) < int(b.get("spawn", {}).get("gridIndex", 0)))
	var slots: Array = slot_entities.map(func(e): return builder.node_for(e.id)).filter(func(n): return n != null)
	for i in mini(count, 11):
		var spec: Dictionary = player.spec.duplicate(true)
		spec["bodyColor"] = ZinoFormat.arr_col(colors[i % colors.size()])
		var v := ZinoVehicle.new()
		v.name = "AI_%d" % (i + 1)
		v.display_name = "AI %d" % (i + 1)
		v.collision_layer = ZinoSceneBuilder.GAMEPLAY_LAYER
		v.collision_mask = ZinoSceneBuilder.GAMEPLAY_LAYER
		builder._build_car_body(v, spec)
		v.configure(spec)
		v.input_enabled = false
		var row := i + 1
		var t := base
		if row < slots.size():
			# Use the track's starting grid (slot 0 is the player's).
			var slot: Node3D = slots[row]
			t = Transform3D(slot.global_transform.basis.orthonormalized(), slot.global_position + Vector3.UP * (base.origin.y - slots[0].global_position.y))
		else:
			var side := -1.0 if row % 2 == 1 else 1.0
			t.origin = base.origin - fwd * (7.0 * ceil(row / 2.0) + 2.0 * (row % 2)) + right * side * 3.2 * float(row % 2)
		v.transform = t
		builder.root.add_child(v)
		v.spawn_transform = v.global_transform
		ai_vehicles.append(v)
		var d := ZinoAIDriver.new()
		d.difficulty = clampf(float(race_settings.get("aiDifficulty", 0.7)), 0.0, 1.0)
		d.behavior = str(race_settings.get("aiBehavior", "balanced"))
		d.active = false
		add_child(d)
		d.setup(v, _track, _track_closed)
		ai_drivers.append(d)
	for d in ai_drivers:
		d.others = all_vehicles()

## Traffic cars cruise the road network in the right-hand lane at a set speed.
func _spawn_traffic(cfg: Dictionary) -> void:
	var count := int(cfg.get("count", 0))
	if count <= 0:
		return
	var roads: Array = scene.get("entities", []).filter(func(e): return e.get("type") == ZinoEntities.TYPE_ROAD)
	if roads.is_empty():
		return
	var colors := [Color("f5f5f7"), Color("1c1c1e"), Color("8e8e93"), Color("0a84ff"), Color("ff9f0a"), Color("30d158")]
	for i in mini(count, 24):
		var r: Dictionary = roads[i % roads.size()]
		var line := ZinoTrackTools.world_centerline(r.road, builder.node_for(r.id).global_transform)
		if line.size() < 4:
			continue
		var spec := ZinoEntities.default_vehicle_spec("openWorld")
		spec["bodyColor"] = ZinoFormat.arr_col(colors[i % colors.size()])
		spec["topSpeedKmh"] = 120.0
		var v := ZinoVehicle.new()
		v.name = "Traffic_%d" % (i + 1)
		v.display_name = "Traffic %d" % (i + 1)
		v.collision_layer = ZinoSceneBuilder.GAMEPLAY_LAYER
		v.collision_mask = ZinoSceneBuilder.GAMEPLAY_LAYER
		builder._build_car_body(v, spec)
		v.configure(spec)
		var k := int(line.size() * (0.15 + 0.7 * fmod(i * 0.37, 1.0)))
		var dir := (line[mini(k + 1, line.size() - 1)] - line[k]).normalized()
		var lane := float(r.road.get("width", 12.0)) * 0.25
		var pos := line[k] + dir.cross(Vector3.UP).normalized() * lane + Vector3.UP * 1.2
		v.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
		builder.root.add_child(v)
		v.spawn_transform = v.global_transform
		var d := ZinoAIDriver.new()
		d.speed_limit_kmh = float(cfg.get("speedKmh", 55.0))
		d.lane_offset = lane
		d.behavior = "cautious"
		add_child(d)
		d.setup(v, line, r.road.get("closed", false))
		traffic.append(v)

func _set_ai_active(on: bool) -> void:
	for d in ai_drivers:
		d.active = on

# --- Events from the world ---------------------------------------------------------------------

func _on_collision(v: ZinoVehicle, impact: float) -> void:
	if v == builder.player_vehicle():
		last_impact = impact
		_fire("ev_collision")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := OS.get_keycode_string((event as InputEventKey).keycode).to_lower()
		_fire("ev_key", {"key": key})
	for action in ZinoBlockLibrary.ACTIONS.split("|"):
		if InputMap.has_action(action) and event.is_action_pressed(action):
			_fire("ev_action", {"action": action})
			if action == ZinoInput.PAUSE:
				toggle_pause()
			if action == ZinoInput.NITRO:
				var p := builder.player_vehicle()
				if p:
					p.nitro(1.5, 1.5)

func toggle_pause() -> void:
	_paused = not _paused
	if _paused:
		hud.show_menu("pause")
	else:
		hud.hide_menus()
	PhysicsServer3D.set_active(not _paused)
	builder.root.process_mode = Node.PROCESS_MODE_DISABLED if _paused else Node.PROCESS_MODE_INHERIT

func _on_menu_action(action: String) -> void:
	match action:
		"resume":
			if _paused:
				toggle_pause()
		"restart":
			if _paused:
				toggle_pause()
			hud.hide_menus()
			replay.stop()
			for v in all_vehicles():
				v.freeze = false
			race.restart()
		"replay":
			hud.hide_menus()
			hud.show_big("REPLAY", 2.0)
			replay.play(builder.root)
		"quit":
			quit_requested.emit()

func _process(delta: float) -> void:
	if _camera_shake > 0.0:
		_camera_shake = maxf(0.0, _camera_shake - delta)
		var cam := get_viewport().get_camera_3d()
		if cam:
			var k := _camera_shake_strength if _camera_shake > 0.0 else 0.0
			cam.h_offset = randf_range(-1, 1) * k
			cam.v_offset = randf_range(-1, 1) * k

func stop() -> void:
	PhysicsServer3D.set_active(true)
	ZinoMaterials.set_wetness(0.0)
	if audio:
		audio.stop_all()

# --- Data (save game) ------------------------------------------------------------------------

func _save_path() -> String:
	return "user://zino_saves/%s.json" % save_key

func _load_save() -> void:
	var r := ZinoFormat.read_json_file(_save_path())
	_save = r.data if r.ok and r.data is Dictionary else {}

func data_save(key: String, value) -> void:
	_save[key] = ZinoFormat.arr3(value) if value is Vector3 else value
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://zino_saves"))
	ZinoFormat.write_text_atomic(ProjectSettings.globalize_path(_save_path()), ZinoFormat.to_json(_save), false)

func data_load(key: String, fallback):
	return _save.get(key, fallback)

func data_has(key: String) -> bool:
	return _save.has(key)

# --- Blocks ---------------------------------------------------------------------------------------

func _err(msg: String) -> Dictionary:
	return {"__error": msg}

func _veh(a: Dictionary):
	var v := vehicle(a.get("vehicle", "player"))
	return v if v else _err("vehicle '%s' not found" % str(a.get("vehicle")))

## Value blocks that read game state.
func value_block(block: String, a: Dictionary, _rt):
	var r = null
	var racer = null
	if block.begins_with("race_") and a.has("vehicle"):
		var v = _veh(a)
		if v is Dictionary:
			return v
		racer = race.racer_for(v) if race else null
		if racer == null:
			return _err("'%s' is not part of the race" % str(a.vehicle))
	match block:
		"race_running": return race != null and race.state == "racing"
		"race_lap": return float(racer.lap)
		"race_total_laps": return float(race.laps)
		"race_position": return float(racer.position)
		"race_lap_time": return racer.lap_time()
		"race_last_lap": return racer.last_lap
		"race_best_lap": return racer.best_lap
		"race_time": return race.race_time
		"race_checkpoint": return float(racer.last_checkpoint)
		"race_racers": return float(race.racers.size())
		"race_score": return score
		"ai_count": return float(ai_vehicles.size())
		"ai_player_position":
			var p := builder.player_vehicle()
			return p.global_position if p else Vector3.ZERO
		"phy_gravity": return float(PhysicsServer3D.area_get_param(get_viewport().find_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY))
		"env_time_value": return environment.hours
		"in_key": return Input.is_physical_key_pressed(OS.find_keycode_from_string(str(a.key)))
		"in_action": return InputMap.has_action(str(a.action)) and Input.is_action_pressed(str(a.action))
		"in_throttle": return Input.get_action_strength(ZinoInput.ACCELERATE)
		"in_steer": return Input.get_action_strength(ZinoInput.STEER_RIGHT) - Input.get_action_strength(ZinoInput.STEER_LEFT)
	var v = _veh(a)
	if v is Dictionary:
		return v
	match block:
		"veh_speed": r = v.speed_kmh
		"veh_rpm": r = v.rpm
		"veh_gear": r = float(v.gear)
		"veh_position": r = v.global_position
		"veh_rotation": r = v.global_rotation_degrees
		"veh_grounded": r = v.grounded_wheels() > 0
		"phy_velocity": r = v.linear_velocity
		"phy_wheel_contact":
			var i := int(a.wheel) - 1
			var ws: Array = v.wheels()
			if i < 0 or i >= ws.size():
				return _err("wheel %d does not exist" % (i + 1))
			r = ws[i].is_in_contact()
		_:
			return _err("unknown value block " + block)
	return r

## Statement blocks that change the game.
func stmt_block(block: String, a: Dictionary, _rt):
	if block.begins_with("race_") and race == null:
		return _err("no race in this scene")
	match block:
		"race_start": race.start(); return null
		"race_stop": race.stop(); return null
		"race_restart": race.restart(); return null
		"race_set_laps": race.laps = maxi(1, int(a.laps)); return null
		"race_set_countdown": race.countdown = maxf(0.0, float(a.seconds)); return null
		"race_add_score": score += float(a.points); return null
		"race_finish":
			var v = _veh(a)
			if v is Dictionary: return v
			race.finish_racer(race.racer_for(v))
			return null
		"ai_start": _set_ai_active(true); return null
		"ai_stop": _set_ai_active(false); return null
		"ai_difficulty":
			for d in ai_drivers: d.difficulty = clampf(float(a.level) / 100.0, 0.0, 1.0)
			return null
		"ai_behavior":
			for d in ai_drivers: d.behavior = str(a.style)
			return null
		"ai_follow_line":
			for d in ai_drivers: d.follow_line = bool(a.on)
			return null
		"ai_target":
			var v = _veh(a)
			if v is Dictionary: return v
			for d in ai_drivers:
				if d.vehicle == v:
					d.target_override = a.position
					d.active = true
					return null
			return _err("'%s' is not an AI vehicle" % str(a.vehicle))
		"cam_mode":
			var cam := get_viewport().get_camera_3d()
			if cam is ZinoChaseCamera:
				cam.mode_index = maxi(0, ZinoChaseCamera.MODES.find(str(a.mode)))
			return null
		"cam_fov":
			var cam := get_viewport().get_camera_3d()
			if cam is ZinoChaseCamera:
				cam.base_fov = float(a.fov)
			elif cam:
				cam.fov = float(a.fov)
			return null
		"cam_shake":
			_camera_shake = float(a.seconds)
			_camera_shake_strength = float(a.strength)
			return null
		"cam_target":
			var v = _veh(a)
			if v is Dictionary: return v
			var cam := get_viewport().get_camera_3d()
			if cam is ZinoChaseCamera:
				cam.setup(v, cam.cam_data)
			return null
		"env_time": environment.set_time(float(a.hours)); return null
		"env_weather": environment.set_weather(str(a.weather)); return null
		"env_fog": environment.set_fog(float(a.density)); return null
		"env_exposure":
			builder.environment_node().environment.tonemap_exposure = float(a.value)
			return null
		"env_preset":
			match str(a.preset):
				"sunset": environment.set_time(19.2); environment.set_weather("clear")
				"overcast": environment.set_time(13.0); environment.set_weather("cloudy")
				"night": environment.set_time(23.0)
				_: environment.set_time(13.0); environment.set_weather("clear")
			return null
		"env_sun":
			var sun := _find_sun()
			if sun:
				sun.light_energy = float(a.intensity)
				environment._base_sun_energy = float(a.intensity)
			return null
		"aud_play":
			var e := audio.play_sound(str(a.sound))
			return _err(e) if e != "" else null
		"aud_stop": audio.stop_all(); return null
		"aud_volume": audio.set_volume(str(a.bus), float(a.percent)); return null
		"aud_music":
			var e := audio.play_music(str(a.sound), bool(a.loop))
			return _err(e) if e != "" else null
		"aud_stop_music": audio.stop_music(); return null
		"aud_engine": audio.engine_enabled = bool(a.on); return null
		"aud_tires": audio.tires_enabled = bool(a.on); return null
		"ui_message": hud.show_message(ZinoBlockRuntime._to_text(a.text), float(a.seconds)); return null
		"ui_hide_message": hud.hide_message(); return null
		"ui_big": hud.show_big(ZinoBlockRuntime._to_text(a.text), float(a.seconds)); return null
		"ui_hud": hud.set_element_visible(str(a.element), bool(a.visible)); return null
		"ui_progress": hud.set_progress(str(a.label), float(a.value)); return null
		"ui_label": hud.set_label(int(a.slot), ZinoBlockRuntime._to_text(a.text)); return null
		"ui_results": hud.show_results(race.results() if race else []); return null
		"ui_menu":
			if str(a.menu) == "results":
				hud.show_results(race.results() if race else [])
			else:
				hud.show_menu(str(a.menu))
			return null
		"ui_hide_menu": hud.hide_menus(); return null
		"phy_set_gravity":
			PhysicsServer3D.area_set_param(get_viewport().find_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, float(a.g))
			return null
	var v = _veh(a)
	if v is Dictionary:
		return v
	match block:
		"veh_set_power": v.power_multiplier = maxf(0.0, float(a.percent) / 100.0)
		"veh_set_top_speed": v.top_speed_override = maxf(1.0, float(a.kmh))
		"veh_accelerate": v.override["throttle"] = clampf(float(a.amount), 0.0, 1.0)
		"veh_brake": v.override["brake"] = clampf(float(a.amount), 0.0, 1.0)
		"veh_steer": v.override["steer"] = clampf(float(a.amount), -1.0, 1.0)
		"veh_handbrake": v.override["handbrake"] = bool(a.on)
		"veh_release": v.override = {}
		"veh_set_gear": v.set_gear(int(a.gear))
		"veh_auto": v.spec["automatic"] = bool(a.on)
		"veh_control": v.input_enabled = bool(a.on)
		"veh_reset": v.reset_to_spawn()
		"veh_teleport":
			v.global_position = a.position
			v.linear_velocity = Vector3.ZERO
			v.angular_velocity = Vector3.ZERO
		"veh_paint":
			var col := Color.html(str(a.color)) if Color.html_is_valid(str(a.color)) else Color.RED
			var body: Node = v.get_node_or_null("Body")
			if body:
				var mat := ZinoMaterials.get_material({"preset": "carPaint", "color": ZinoFormat.arr_col(col)})
				for n in ["Chassis", "Roof"]:
					var mi := body.get_node_or_null(n) as MeshInstance3D
					if mi:
						mi.material_override = mat
		"veh_profile":
			var spec := ZinoEntities.default_vehicle_spec(str(a.profile))
			spec["bodyColor"] = v.spec.get("bodyColor")
			spec["wheels"] = v.spec.get("wheels")
			v.configure(spec)
		"veh_nitro": v.nitro(float(a.seconds), float(a.strength))
		"phy_force": v.apply_central_force(a.force)
		"phy_impulse": v.apply_central_impulse(a.impulse)
		"phy_suspension":
			v.spec["suspensionStiffness"] = float(a.stiffness)
			for w in v.wheels(): w.suspension_stiffness = float(a.stiffness)
		"phy_friction":
			v.spec["tireFrictionSlip"] = float(a.front)
			v.spec["rearFrictionSlip"] = float(a.rear)
			for w in v.wheels(): w.wheel_friction_slip = float(a.rear) if w.get_meta("zino_handbrake", false) else float(a.front)
		"phy_mass":
			v.mass = maxf(1.0, float(a.kg))
		"phy_downforce": v.spec["downforce"] = float(a.amount)
		_:
			return _err("unknown block " + block)
	return null
