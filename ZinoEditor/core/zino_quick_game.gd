class_name ZinoQuickGame
extends RefCounted
## "Make a Game" — turns a handful of simple choices into a complete, playable racing game project:
## game type, car, colour, track, world (time + weather), laps, opponents and difficulty.

const GAME_TYPES := [
	{"id": "circuit", "name": "Circuit Race", "desc": "Race opponents around a track for a few laps.", "icon": "🏁", "template": "circuit", "mode": "circuit"},
	{"id": "timeTrial", "name": "Time Trial", "desc": "Just you against the clock. Beat your best lap.", "icon": "⏱", "template": "circuit", "mode": "timeTrial"},
	{"id": "elimination", "name": "Elimination", "desc": "Last car is knocked out every lap.", "icon": "💥", "template": "circuit", "mode": "elimination"},
	{"id": "drift", "name": "Drift", "desc": "Slide sideways around a wide track.", "icon": "💨", "template": "drift", "mode": "circuit"},
	{"id": "kart", "name": "Kart Cup", "desc": "Small, fast karts on a twisty track.", "icon": "🏎", "template": "kart", "mode": "circuit"},
	{"id": "drag", "name": "Drag Race", "desc": "Straight line, full throttle, 402 metres.", "icon": "🚀", "template": "drag", "mode": "sprint"},
	{"id": "openWorld", "name": "Open World", "desc": "Drive freely on highways with traffic.", "icon": "🌄", "template": "openWorld", "mode": "auto"},
]

const CARS := [
	{"id": "sport", "name": "Sports Car", "desc": "Quick and easy to drive.", "profile": "arcade"},
	{"id": "racer", "name": "Race Car", "desc": "Lots of grip and downforce.", "profile": "circuit"},
	{"id": "drifter", "name": "Drift Car", "desc": "Loose rear end, made to slide.", "profile": "drift"},
	{"id": "realistic", "name": "Realistic", "desc": "Simulation handling, less forgiving.", "profile": "simulation"},
	{"id": "kart", "name": "Go-Kart", "desc": "Tiny, light and nimble.", "profile": "kart"},
	{"id": "dragster", "name": "Dragster", "desc": "Huge power for straight lines.", "profile": "drag"},
]

const COLORS := ["#d01010", "#0a84ff", "#30d158", "#ffd60a", "#ff9f0a", "#bf5af2", "#f5f5f7", "#1c1c1e"]

const TRACKS := [
	{"id": "classic", "name": "Classic Circuit", "desc": "A clean rounded-rectangle track.", "gen": {}},
	{"id": "oval", "name": "Speedway Oval", "desc": "Fast, wide and simple.", "gen": {"seed": 4, "corners": 6, "irregularity": 0.05, "radius": 120.0, "banking": 6.0}},
	{"id": "technical", "name": "Technical", "desc": "Lots of corners to master.", "gen": {"seed": 21, "corners": 16, "irregularity": 0.5, "radius": 95.0, "banking": 3.0}},
	{"id": "hills", "name": "Hill Circuit", "desc": "Ups, downs and banked turns.", "gen": {"seed": 33, "corners": 12, "irregularity": 0.35, "radius": 110.0, "elevation": 18.0, "banking": 6.0}},
	{"id": "random", "name": "Surprise Me", "desc": "A brand-new random track.", "gen": {"random": true}},
]

const WORLDS := [
	{"id": "day", "name": "Sunny Day", "hours": 13.0, "weather": "clear"},
	{"id": "sunset", "name": "Sunset", "hours": 19.3, "weather": "clear"},
	{"id": "night", "name": "Night", "hours": 23.0, "weather": "clear"},
	{"id": "rain", "name": "Rain", "hours": 14.0, "weather": "rain"},
	{"id": "storm", "name": "Storm", "hours": 16.5, "weather": "storm"},
	{"id": "fog", "name": "Foggy Morning", "hours": 8.0, "weather": "fog"},
]

const DIFFICULTY := {"easy": 0.45, "normal": 0.7, "hard": 0.86, "pro": 1.0}

static func find(list: Array, id: String) -> Dictionary:
	for x in list:
		if x.id == id:
			return x
	return list[0]

static func default_choices() -> Dictionary:
	return {"gameType": "circuit", "car": "sport", "color": "#d01010", "track": "classic", "world": "day",
		"laps": 3, "opponents": 3, "difficulty": "normal", "name": "", "location": ""}

## Tracks make sense only for circuit-style games.
static func uses_track(game_type: String) -> bool:
	return not game_type in ["drag", "openWorld"]

## Creates the project. Returns {ok, path, error}.
static func create(choices: Dictionary) -> Dictionary:
	var c := default_choices()
	c.merge(choices, true)
	var gt := find(GAME_TYPES, c.gameType)
	var o := ZinoProjectService.default_options()
	o.name = str(c.name).strip_edges() if str(c.name).strip_edges() != "" else "My " + str(gt.name).replace(" ", "")
	o.location = c.location
	o.template = gt.template
	o.vehicleProfile = find(CARS, c.car).profile
	var r := ZinoProjectService.create_project(o)
	if not r.ok:
		return r
	var path: String = r.path
	var scene_path := path.path_join("Scenes/Main.zscene")
	var scene: Dictionary = ZinoFormat.load_scene_file(scene_path).scene
	apply(scene, c)
	var err := ZinoFormat.save_scene_file(scene_path, scene)
	if err != OK:
		return {"ok": false, "path": path, "error": "Could not save the game scene (%d)" % err}
	var mr := ZinoFormat.read_json_file(ZinoProjectService.manifest_path(path))
	if mr.ok:
		var m: Dictionary = mr.data
		m["coach"] = {"enabled": true, "done": []}
		m["quickGame"] = c.duplicate()
		ZinoProjectService.save_manifest(path, m)
	return {"ok": true, "path": path, "error": ""}

## Applies the choices to a scene document (used by create and by tests).
static func apply(scene: Dictionary, c: Dictionary) -> void:
	var gt := find(GAME_TYPES, c.get("gameType", "circuit"))
	var car_def := find(CARS, c.get("car", "sport"))
	var st: Dictionary = scene.settings
	var w := find(WORLDS, c.get("world", "day"))
	st["timeOfDay"] = w.hours
	st["weather"] = w.weather
	var race: Dictionary = st.get("race", {})
	if gt.id != "openWorld":
		race["enabled"] = true
		race["mode"] = gt.mode
		race["laps"] = 1 if gt.id == "drag" else clampi(int(c.get("laps", 3)), 1, 50)
		race["aiOpponents"] = 0 if gt.id == "timeTrial" else clampi(int(c.get("opponents", 3)), 0, 11)
		race["aiDifficulty"] = DIFFICULTY.get(c.get("difficulty", "normal"), 0.7)
		race["countdown"] = 3.0
	st["race"] = race
	if uses_track(gt.id):
		var t := find(TRACKS, c.get("track", "classic"))
		if not t.gen.is_empty():
			_replace_track(scene, t.gen, gt.id)
	# The player's car.
	for e in scene.entities:
		if e.type == ZinoEntities.TYPE_VEHICLE:
			var spec := ZinoEntities.default_vehicle_spec(car_def.profile)
			spec["bodyColor"] = ZinoFormat.arr_col(Color.html(str(c.get("color", "#d01010"))))
			e.vehicle.spec = spec
			e.name = "Player Car"
			break

static func _replace_track(scene: Dictionary, gen: Dictionary, game_type: String) -> void:
	var params := {"width": 16.0 if game_type == "drift" else (9.0 if game_type == "kart" else 12.0), "elevation": 0.0, "banking": 0.0}
	params.merge(gen, true)
	if params.get("random", false):
		params["seed"] = randi_range(1, 99999)
		params["corners"] = randi_range(8, 16)
		params["irregularity"] = randf_range(0.2, 0.5)
	scene.entities = scene.entities.filter(func(e): return not e.type in [ZinoEntities.TYPE_ROAD, ZinoEntities.TYPE_CHECKPOINT, ZinoEntities.TYPE_START_FINISH, ZinoEntities.TYPE_SPAWN, ZinoEntities.TYPE_BARRIER])
	var road: Dictionary = ZinoTrackTools.generate_circuit(params)[0]
	road.name = "Track"
	scene.entities.append(road)
	scene.entities.append_array(ZinoTrackTools.checkpoints(road.road, Transform3D.IDENTITY, 4))
	var grid := ZinoTrackTools.grid(road.road, Transform3D.IDENTITY, 6)
	scene.entities.append_array(grid)
	scene.entities.append(ZinoTrackTools.barrier(road.id, "both", "guardrail"))
	for e in scene.entities:
		if e.type == ZinoEntities.TYPE_VEHICLE:
			var s: Dictionary = e.vehicle.spec
			var ride: float = float(s.wheelRadius) + float(s.suspensionRestLength) + ZinoFormat.v3(s.bodySize).y * 0.5
			e.transform.position = ZinoFormat.arr3(ZinoFormat.v3(grid[0].transform.position) + Vector3.UP * (ride + 0.1))
			e.transform.rotation = grid[0].transform.rotation
		elif e.type == ZinoEntities.TYPE_CAMERA:
			e.transform.position = ZinoFormat.arr3(ZinoFormat.v3(grid[0].transform.position) + Vector3(0, 4, 0))
