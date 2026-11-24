@tool
class_name ZinoEntities
extends RefCounted
## Factory for every entity type the editor can create, plus vehicle specs and physics profiles.
## Every physics profile is a set of defaults for the same vehicle model, never a separate physics system.

const TYPE_EMPTY := "empty"
const TYPE_PRIMITIVE := "primitive"
const TYPE_LIGHT := "light"
const TYPE_CAMERA := "camera"
const TYPE_VEHICLE := "vehicle"
const TYPE_ROAD := "road"
const TYPE_CHECKPOINT := "checkpoint"
const TYPE_START_FINISH := "startFinish"
const TYPE_SPAWN := "spawnPoint"
const TYPE_BARRIER := "barrier"
const TYPE_TERRAIN := "terrain"
const TYPE_VEGETATION := "vegetation"
const TYPE_WATER := "water"
const TYPE_BUILDING := "building"
const TYPE_MODEL := "model"

const PRIMITIVES := ["cube", "sphere", "cylinder", "capsule", "plane"]
const LIGHT_KINDS := ["directional", "point", "spot"]
const MATERIAL_PRESETS := ["default", "asphalt", "concrete", "grass", "dirt", "gravel", "carPaint", "metal", "rubber", "glass"]
const PROFILES := ["arcade", "simulation", "drift", "drag", "kart", "circuit", "openWorld"]
const DRIVES := ["rwd", "fwd", "awd"]

## Menu key -> label, used by the editor's Scene/Racing menus.
const CREATABLE := {
	"empty": "Empty",
	"cube": "Cube", "sphere": "Sphere", "cylinder": "Cylinder", "capsule": "Capsule", "plane": "Plane",
	"directionalLight": "Directional Light", "pointLight": "Point Light", "spotLight": "Spot Light",
	"camera": "Camera",
	"vehicle": "Vehicle", "road": "Road (Circuit)", "checkpoint": "Checkpoint",
	"startFinish": "Start / Finish Line", "spawnPoint": "Grid Spawn Point",
	"terrain": "Terrain", "vegetation": "Vegetation", "water": "Water", "building": "Building",
}

static func base(type: String, entity_name: String) -> Dictionary:
	return {
		"id": ZinoFormat.new_id(),
		"name": entity_name,
		"type": type,
		"parentId": null,
		"active": true,
		"transform": ZinoFormat.transform_dict(Vector3.ZERO, Vector3.ZERO, Vector3.ONE),
	}

static func set_pos(e: Dictionary, p: Vector3) -> Dictionary:
	e["transform"]["position"] = ZinoFormat.arr3(p)
	return e

static func set_rot(e: Dictionary, r: Vector3) -> Dictionary:
	e["transform"]["rotation"] = ZinoFormat.arr3(r)
	return e

static func set_scale(e: Dictionary, s: Vector3) -> Dictionary:
	e["transform"]["scale"] = ZinoFormat.arr3(s)
	return e

static func material(preset: String = "default", color: Color = Color(0.8, 0.8, 0.8), metallic: float = 0.0, roughness: float = 0.6) -> Dictionary:
	return {"preset": preset, "color": ZinoFormat.arr_col(color), "metallic": metallic, "roughness": roughness}

static func empty(entity_name: String = "Empty") -> Dictionary:
	return base(TYPE_EMPTY, entity_name)

static func primitive(shape: String, entity_name: String = "", color: Color = Color(0.8, 0.8, 0.8), preset: String = "default") -> Dictionary:
	assert(shape in PRIMITIVES, "unknown primitive " + shape)
	var e := base(TYPE_PRIMITIVE, entity_name if entity_name != "" else shape.capitalize())
	e["mesh"] = {"primitive": shape, "material": material(preset, color), "castShadows": true, "collider": true}
	if shape != "plane":
		set_pos(e, Vector3(0, 0.5, 0))
	return e

static func light(kind: String, entity_name: String = "") -> Dictionary:
	assert(kind in LIGHT_KINDS, "unknown light " + kind)
	var e := base(TYPE_LIGHT, entity_name)
	var l := {"kind": kind, "color": ZinoFormat.arr_col(Color.WHITE), "intensity": 1.0, "range": 10.0, "spotAngle": 45.0, "shadows": true}
	match kind:
		"directional":
			e["name"] = entity_name if entity_name != "" else "Sun"
			l["intensity"] = 1.3
			l["color"] = ZinoFormat.arr_col(Color(1.0, 0.95, 0.86))
			set_pos(e, Vector3(0, 30, 0))
			set_rot(e, Vector3(-42, -35, 0))
		"spot":
			e["name"] = entity_name if entity_name != "" else "Spot Light"
			l["intensity"] = 6.0
			l["range"] = 25.0
			set_pos(e, Vector3(0, 6, 0))
			set_rot(e, Vector3(-90, 0, 0))
		_:
			e["name"] = entity_name if entity_name != "" else "Point Light"
			l["intensity"] = 4.0
			l["range"] = 15.0
			set_pos(e, Vector3(0, 4, 0))
	e["light"] = l
	return e

static func camera(entity_name: String = "Camera", mode: String = "fixed", target_id = null) -> Dictionary:
	var e := base(TYPE_CAMERA, entity_name)
	e["camera"] = {
		"fov": 65.0, "near": 0.1, "far": 4000.0, "orthographic": false, "orthoSize": 20.0,
		"mode": mode, "targetId": target_id,
		"followDistance": 6.5, "followHeight": 2.1, "lookAhead": 4.0, "smoothing": 7.0,
	}
	set_pos(e, Vector3(0, 3, 8))
	set_rot(e, Vector3(-12, 0, 0))
	return e

# --- Vehicles ---------------------------------------------------------------------

static func default_vehicle_spec(profile: String = "arcade") -> Dictionary:
	var s := {
		"profile": profile,
		"massKg": 1350.0,
		"bodySize": [1.85, 0.62, 4.3],
		"bodyColor": ZinoFormat.arr_col(Color(0.72, 0.04, 0.03)),
		"centerOfMass": [0.0, -0.3, 0.0],
		"wheelRadius": 0.34,
		"wheelWidth": 0.26,
		"wheels": [],
		"suspensionRestLength": 0.18,
		"suspensionTravel": 0.25,
		"suspensionStiffness": 45.0,
		"dampingCompression": 3.4,
		"dampingRelaxation": 4.2,
		"rollInfluence": 0.7,           # Godot: 1.0 resists body roll fully, 0.0 rolls over easily
		"maxSteerAngle": 32.0,
		"highSpeedSteerFactor": 0.35,
		"steerSpeed": 3.5,
		"drive": "rwd",
		"maxEngineForce": 6500.0,
		"idleRpm": 900.0,
		"maxRpm": 7200.0,
		"gearRatios": [3.3, 2.2, 1.6, 1.25, 1.0, 0.82],
		"reverseRatio": 3.2,
		"finalDrive": 3.7,
		"automatic": true,
		"topSpeedKmh": 230.0,
		"maxBrakeForce": 40.0,
		"handbrakeForce": 70.0,
		"tireFrictionSlip": 10.5,
		"rearFrictionSlip": 10.5,
		"downforce": 2.5,
		"dragCoefficient": 0.32,
	}
	apply_profile(s, profile)
	var kart := profile == "kart"
	layout_four_wheels(s, 1.05 if kart else 2.6, 1.0 if kart else 1.6)
	return s

## Lays out FL/FR/RL/RR wheels. Vehicle forward is -Z (Godot convention); front wheels have negative z.
static func layout_four_wheels(s: Dictionary, wheelbase: float, track: float) -> void:
	var body := ZinoFormat.v3(s["bodySize"])
	var y := -body.y * 0.5
	var zf := -wheelbase * 0.5
	var zr := wheelbase * 0.5
	var x := track * 0.5
	var front_drive: bool = s["drive"] != "rwd"
	var rear_drive: bool = s["drive"] != "fwd"
	s["wheels"] = [
		{"name": "FL", "position": [-x, y, zf], "steer": true, "drive": front_drive, "handbrake": false},
		{"name": "FR", "position": [x, y, zf], "steer": true, "drive": front_drive, "handbrake": false},
		{"name": "RL", "position": [-x, y, zr], "steer": false, "drive": rear_drive, "handbrake": true},
		{"name": "RR", "position": [x, y, zr], "steer": false, "drive": rear_drive, "handbrake": true},
	]

static func apply_profile(s: Dictionary, profile: String) -> void:
	s["profile"] = profile
	match profile:
		"simulation":
			s["tireFrictionSlip"] = 8.0; s["rearFrictionSlip"] = 8.0; s["downforce"] = 1.2; s["rollInfluence"] = 0.45; s["highSpeedSteerFactor"] = 0.5
		"drift":
			s["tireFrictionSlip"] = 7.0; s["rearFrictionSlip"] = 2.4; s["drive"] = "rwd"; s["maxSteerAngle"] = 45.0
			s["maxEngineForce"] = 7800.0; s["highSpeedSteerFactor"] = 0.65
		"drag":
			s["maxEngineForce"] = 14000.0; s["topSpeedKmh"] = 330.0; s["maxSteerAngle"] = 16.0
			s["tireFrictionSlip"] = 14.0; s["rearFrictionSlip"] = 14.0; s["drive"] = "rwd"
		"kart":
			s["massKg"] = 170.0; s["bodySize"] = [1.2, 0.3, 1.8]; s["wheelRadius"] = 0.14; s["wheelWidth"] = 0.18
			s["suspensionRestLength"] = 0.06; s["suspensionTravel"] = 0.06; s["suspensionStiffness"] = 80.0
			s["maxEngineForce"] = 900.0; s["topSpeedKmh"] = 110.0; s["gearRatios"] = [1.0]; s["finalDrive"] = 1.0
			s["maxBrakeForce"] = 6.0; s["handbrakeForce"] = 9.0; s["centerOfMass"] = [0.0, -0.1, 0.0]
			s["rollInfluence"] = 0.9
		"circuit":
			s["tireFrictionSlip"] = 12.0; s["rearFrictionSlip"] = 12.0; s["downforce"] = 4.0
		"openWorld":
			s["suspensionTravel"] = 0.35; s["suspensionStiffness"] = 38.0
		_:
			s["tireFrictionSlip"] = 11.0; s["rearFrictionSlip"] = 10.5; s["downforce"] = 3.0; s["highSpeedSteerFactor"] = 0.4

static func vehicle(entity_name: String = "Player Car", profile: String = "arcade") -> Dictionary:
	var e := base(TYPE_VEHICLE, entity_name)
	var spec := default_vehicle_spec(profile)
	e["vehicle"] = {"spec": spec, "playerControlled": true}
	var body := ZinoFormat.v3(spec["bodySize"])
	# Wheel centres sit at -body.y/2; put the tyres on y = 0 with the suspension at rest.
	var ride := float(spec["wheelRadius"]) + float(spec["suspensionRestLength"]) + body.y * 0.5
	set_pos(e, Vector3(0, ride, 0))
	return e

# --- Track ------------------------------------------------------------------------

static func road(points: Array, entity_name: String = "Road", width: float = 12.0, closed: bool = true) -> Dictionary:
	var e := base(TYPE_ROAD, entity_name)
	var pts: Array = []
	for p in points:
		pts.append(ZinoFormat.arr3(ZinoFormat.v3(p)))
	e["road"] = {
		"points": pts, "width": width, "closed": closed, "banking": 0.0, "thickness": 0.3,
		"samplesPerSegment": 14, "surface": "asphalt", "edgeLines": true, "shoulderWidth": 1.2,
	}
	return e

const CIRCUIT_HALF_X := 70.0
const CIRCUIT_HALF_Z := 35.0
const CIRCUIT_CORNER_RADIUS := 22.0

## Rounded-rectangle circuit, 140 m x 70 m. The main straight is z = +35, driven towards -X.
## Each straight has a midpoint so the Catmull-Rom centreline stays straight between corners.
static func circuit_points() -> Array:
	var hx := CIRCUIT_HALF_X
	var hz := CIRCUIT_HALF_Z
	var r := CIRCUIT_CORNER_RADIUS
	var pts: Array = [Vector3(0, 0, hz)]
	# [corner centre x, corner centre z, start angle in degrees], visited in driving order.
	var corners := [[-hx + r, hz - r, 90.0], [-hx + r, -hz + r, 180.0], [hx - r, -hz + r, 270.0], [hx - r, hz - r, 0.0]]
	var mids := [Vector3(-hx, 0, 0), Vector3(0, 0, -hz), Vector3(hx, 0, 0), null]
	for i in corners.size():
		var c: Array = corners[i]
		for step in 3:
			var a := deg_to_rad(c[2] + step * 45.0)
			pts.append(Vector3(c[0] + r * cos(a), 0, c[1] + r * sin(a)))
		if mids[i] != null:
			pts.append(mids[i])
	return pts

static func circuit_road(entity_name: String = "Circuit Road") -> Dictionary:
	return road(circuit_points(), entity_name, 12.0, true)

static func trigger(type: String, entity_name: String, index: int) -> Dictionary:
	var e := base(type, entity_name)
	e["trigger"] = {"size": [14.0, 4.0, 1.0], "index": index}
	set_pos(e, Vector3(0, 2, 0))
	return e

static func checkpoint(index: int, entity_name: String = "") -> Dictionary:
	return trigger(TYPE_CHECKPOINT, entity_name if entity_name != "" else "Checkpoint %d" % index, index)

static func start_finish(entity_name: String = "Start / Finish") -> Dictionary:
	return trigger(TYPE_START_FINISH, entity_name, 0)

static func spawn_point(grid_index: int = 0) -> Dictionary:
	var e := base(TYPE_SPAWN, "Grid Slot %d" % (grid_index + 1))
	e["spawn"] = {"gridIndex": grid_index}
	return e

static func terrain() -> Dictionary:
	var e := base(TYPE_TERRAIN, "Terrain")
	e["terrain"] = ZinoWorld.default_terrain()
	return e

static func vegetation() -> Dictionary:
	var e := base(TYPE_VEGETATION, "Vegetation")
	e["vegetation"] = ZinoWorld.default_vegetation()
	return e

static func water(size: Vector3 = Vector3(300, 0, 300)) -> Dictionary:
	var e := base(TYPE_WATER, "Lake")
	e["water"] = {"size": ZinoFormat.arr3(size)}
	return e

static func model(path: String, entity_name: String = "") -> Dictionary:
	var e := base(TYPE_MODEL, entity_name if entity_name != "" else path.get_file().get_basename().capitalize())
	e["model"] = {"path": path, "collision": "box"}
	return e

static func building(seed: int = 1, floors: int = 6) -> Dictionary:
	var e := base(TYPE_BUILDING, "Building")
	e["building"] = {"seed": seed, "floors": floors, "width": 18.0, "depth": 14.0}
	return e

## Creates an entity from a menu key (see CREATABLE).
static func create(kind: String) -> Dictionary:
	match kind:
		"empty": return empty()
		"cube", "sphere", "cylinder", "capsule", "plane": return primitive(kind)
		"directionalLight": return light("directional")
		"pointLight": return light("point")
		"spotLight": return light("spot")
		"camera": return camera()
		"vehicle": return vehicle()
		"road": return circuit_road()
		"checkpoint": return checkpoint(1)
		"startFinish": return start_finish()
		"spawnPoint": return spawn_point(0)
		"terrain": return terrain()
		"vegetation": return vegetation()
		"water": return water()
		"building": return building()
	push_error("Unknown entity kind: " + kind)
	return {}
