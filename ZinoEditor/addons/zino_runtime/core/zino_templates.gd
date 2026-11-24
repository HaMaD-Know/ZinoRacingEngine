@tool
class_name ZinoTemplates
extends RefCounted
## Project templates (the eight racing game types) and the starting scene each one creates.

const ROAD_SURFACE_Y := 0.05

## id -> {name, description, gameType, profile, scene}
const PROJECTS := {
	"openWorld": {"name": "Open World Racing", "description": "Large ground, highway and side road, open-world handling.", "gameType": "openWorld", "profile": "openWorld", "scene": "openWorld"},
	"circuit": {"name": "Circuit Racing", "description": "Closed circuit with start/finish, checkpoints and grid.", "gameType": "circuit", "profile": "circuit", "scene": "circuit"},
	"arcade": {"name": "Arcade Racing", "description": "Forgiving, high-grip handling on a closed circuit.", "gameType": "arcade", "profile": "arcade", "scene": "circuit"},
	"simulation": {"name": "Simulation Racing", "description": "Detailed tuning parameters and lower assist grip.", "gameType": "simulation", "profile": "simulation", "scene": "circuit"},
	"drift": {"name": "Drifting", "description": "Wide circuit, rear-wheel drive, low rear grip for sliding.", "gameType": "drift", "profile": "drift", "scene": "circuit"},
	"drag": {"name": "Drag Racing", "description": "Quarter-mile strip with start and finish lines.", "gameType": "drag", "profile": "drag", "scene": "drag"},
	"kart": {"name": "Kart Racing", "description": "Light kart on a narrower circuit.", "gameType": "kart", "profile": "kart", "scene": "circuit"},
	"empty": {"name": "Empty Racing Project", "description": "Ground, sun and camera. Build everything yourself.", "gameType": "custom", "profile": "arcade", "scene": "empty"},
}

const ORDER := ["openWorld", "circuit", "arcade", "simulation", "drift", "drag", "kart", "empty"]

static func scene_for_template(template_id: String, scene_name: String = "Main") -> Dictionary:
	var t: Dictionary = PROJECTS.get(template_id, PROJECTS["circuit"])
	match t["scene"]:
		"openWorld": return open_world(scene_name)
		"drag": return drag_strip(scene_name)
		"empty": return empty(scene_name)
		_: return racing_test_scene(t["profile"], scene_name)

## Phase 1 racing test scene: ground, closed circuit, one drivable four-wheel vehicle,
## chase camera, sun, start/finish line, three checkpoints, one grid slot.
static func racing_test_scene(profile: String = "arcade", scene_name: String = "Main") -> Dictionary:
	var scene := _ground_and_sun(scene_name)
	var hz := ZinoEntities.CIRCUIT_HALF_Z
	var hx := ZinoEntities.CIRCUIT_HALF_X

	var road := ZinoEntities.circuit_road("Circuit Road")
	if profile == "kart":
		road["road"]["width"] = 9.0
	elif profile == "drift":
		road["road"]["width"] = 16.0
	var width: float = road["road"]["width"]
	scene["entities"].append(road)

	var start := ZinoEntities.start_finish()
	ZinoEntities.set_pos(start, Vector3(0, 2, hz))
	ZinoEntities.set_rot(start, Vector3(0, 90, 0))
	start["trigger"]["size"] = [width + 2.0, 4.0, 1.0]
	scene["entities"].append(start)

	var cps := [[Vector3(-hx, 2, 0), 0.0], [Vector3(0, 2, -hz), 90.0], [Vector3(hx, 2, 0), 0.0]]
	for i in cps.size():
		var cp := ZinoEntities.checkpoint(i + 1)
		ZinoEntities.set_pos(cp, cps[i][0])
		ZinoEntities.set_rot(cp, Vector3(0, cps[i][1], 0))
		cp["trigger"]["size"] = [width + 2.0, 4.0, 1.0]
		scene["entities"].append(cp)

	# Car faces -X (yaw +90 turns Godot's -Z forward to -X), parked just behind the line.
	var car := ZinoEntities.vehicle("Player Car", profile)
	var y: float = ZinoFormat.v3(car["transform"]["position"]).y + ROAD_SURFACE_Y
	ZinoEntities.set_pos(car, Vector3(10, y, hz))
	ZinoEntities.set_rot(car, Vector3(0, 90, 0))
	scene["entities"].append(car)

	var spawn := ZinoEntities.spawn_point(0)
	ZinoEntities.set_pos(spawn, Vector3(10, ROAD_SURFACE_Y, hz))
	ZinoEntities.set_rot(spawn, Vector3(0, 90, 0))
	scene["entities"].append(spawn)

	var cam := ZinoEntities.camera("Chase Camera", "chase", car["id"])
	ZinoEntities.set_pos(cam, Vector3(17, 3, hz))
	ZinoEntities.set_rot(cam, Vector3(-12, 90, 0))
	scene["entities"].append(cam)
	if profile == "kart":
		scene["settings"]["race"]["aiOpponents"] = 5
	elif profile == "drift":
		scene["settings"]["race"]["aiOpponents"] = 1
	return scene

static func drag_strip(scene_name: String = "Main") -> Dictionary:
	var scene := _ground_and_sun(scene_name)
	scene["entities"].append(ZinoEntities.road([Vector3(0, 0, 30), Vector3(0, 0, -200), Vector3(0, 0, -440)], "Drag Strip", 14.0, false))
	var start := ZinoEntities.start_finish("Start Line")
	start["trigger"]["size"] = [16.0, 4.0, 1.0]
	scene["entities"].append(start)
	var finish := ZinoEntities.checkpoint(1, "Finish Line (402 m)")
	ZinoEntities.set_pos(finish, Vector3(0, 2, -402.3))
	finish["trigger"]["size"] = [16.0, 4.0, 1.0]
	scene["entities"].append(finish)
	var car := ZinoEntities.vehicle("Player Car", "drag")
	var y: float = ZinoFormat.v3(car["transform"]["position"]).y + ROAD_SURFACE_Y
	ZinoEntities.set_pos(car, Vector3(-3, y, 4))
	scene["entities"].append(car)
	var cam := ZinoEntities.camera("Chase Camera", "chase", car["id"])
	ZinoEntities.set_pos(cam, Vector3(-3, 3, 11))
	scene["entities"].append(cam)
	scene["settings"]["race"].merge({"aiOpponents": 1, "laps": 1, "mode": "sprint"}, true)
	return scene

static func open_world(scene_name: String = "Main") -> Dictionary:
	var scene := ZinoFormat.new_scene(scene_name)
	scene["entities"].append(ZinoEntities.light("directional", "Sun"))
	var terrain := ZinoEntities.terrain()
	scene["entities"].append(terrain)
	scene["entities"].append(ZinoEntities.road([Vector3(-500, 2, 0), Vector3(-200, 4, 10), Vector3(0, 2, 0), Vector3(250, 6, -20), Vector3(500, 3, 0)], "East-West Highway", 14.0, false))
	scene["entities"].append(ZinoEntities.road([Vector3(0, 2, 500), Vector3(10, 3, 250), Vector3(0, 2, 30), Vector3(60, 5, -160), Vector3(40, 4, -500)], "North Road", 10.0, false))
	var veg := ZinoEntities.vegetation()
	scene["entities"].append(veg)
	var lake := ZinoEntities.water(Vector3(160, 0, 120))
	ZinoEntities.set_pos(lake, Vector3(-180, 0.3, -160))
	scene["entities"].append(lake)
	for i in 6:
		var b := ZinoEntities.building(i + 1, 4 + i * 3)
		ZinoEntities.set_pos(b, Vector3(60 + (i % 3) * 30, 2.0, 40 + floor(i / 3.0) * 30))
		scene["entities"].append(b)
	scene["settings"]["traffic"] = {"count": 6, "speedKmh": 55.0}
	var car := ZinoEntities.vehicle("Player Car", "openWorld")
	# The highway is ~2.3 m up at x = -30; drop the car just above it.
	var y: float = ZinoFormat.v3(car["transform"]["position"]).y + ROAD_SURFACE_Y + 2.6
	ZinoEntities.set_pos(car, Vector3(-30, y, 3.5))
	ZinoEntities.set_rot(car, Vector3(0, -90, 0))
	scene["entities"].append(car)
	var cam := ZinoEntities.camera("Chase Camera", "chase", car["id"])
	ZinoEntities.set_pos(cam, Vector3(-37, 5.5, 3.5))
	ZinoEntities.set_rot(cam, Vector3(-12, -90, 0))
	scene["entities"].append(cam)
	scene["settings"]["race"]["enabled"] = false
	return scene

static func empty(scene_name: String = "Main") -> Dictionary:
	var scene := _ground_and_sun(scene_name)
	scene["entities"].append(ZinoEntities.camera("Main Camera"))
	scene["settings"]["race"]["enabled"] = false
	return scene

static func _ground_and_sun(scene_name: String, ground_size: float = 500.0) -> Dictionary:
	var scene := ZinoFormat.new_scene(scene_name)
	var ground := ZinoEntities.primitive("plane", "Ground", Color(0.22, 0.38, 0.16), "grass")
	ZinoEntities.set_scale(ground, Vector3(ground_size, 1, ground_size))
	scene["entities"].append(ground)
	scene["entities"].append(ZinoEntities.light("directional", "Sun"))
	return scene
