@tool
class_name ZinoFormat
extends RefCounted
## Zino scene/project file format: constants, conversions, ids, validation and safe file IO.
##
## Zino scene space is Godot space: metres, right-handed, +Y up, -Z forward.
## Rotations are Euler angles in degrees, Godot order (YXZ).
## Entities are plain Dictionaries so they serialize to JSON losslessly and
## unknown keys written by newer Zino versions are preserved.

const SCENE_FORMAT := "zino-scene"
const SCENE_FORMAT_VERSION := 1
const PROJECT_FORMAT := "zino-project"
const PROJECT_FORMAT_VERSION := 1
const ENGINE_VERSION := "1.1.0"
const SCENE_EXTENSION := "zscene"
const MAX_ROAD_POINTS := 4096

const ID_ALPHABET := "abcdefghijklmnopqrstuvwxyz0123456789"

# --- Vector / colour conversion -------------------------------------------------

static func v3(value, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

static func arr3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.00001), snappedf(v.y, 0.00001), snappedf(v.z, 0.00001)]

static func col(value, fallback: Color = Color.WHITE) -> Color:
	if value is Color:
		return value
	if value is Array and value.size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() > 3 else 1.0)
	if value is String and value.begins_with("#"):
		return Color.html(value)
	return fallback

static func arr_col(c: Color) -> Array:
	return [snappedf(c.r, 0.0001), snappedf(c.g, 0.0001), snappedf(c.b, 0.0001), snappedf(c.a, 0.0001)]

static func is_finite_array(value, count: int = 3) -> bool:
	if not (value is Array) or value.size() != count:
		return false
	for x in value:
		if not (x is float or x is int):
			return false
		if is_nan(float(x)) or is_inf(float(x)):
			return false
	return true

# --- Transforms ------------------------------------------------------------------

static func transform_from_entity(entity: Dictionary) -> Transform3D:
	var t: Dictionary = entity.get("transform", {})
	var rot_deg := v3(t.get("rotation"), Vector3.ZERO)
	var rot := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	# Local scale (rotation * scale), matching Node3D.scale semantics.
	return Transform3D(rot * Basis.from_scale(v3(t.get("scale"), Vector3.ONE)), v3(t.get("position"), Vector3.ZERO))

static func transform_dict(position: Vector3, rotation_deg: Vector3, scale: Vector3) -> Dictionary:
	return {"position": arr3(position), "rotation": arr3(rotation_deg), "scale": arr3(scale)}

## Reads the entity transform as a Dictionary of Vector3 values (position, rotation in degrees, scale).
static func read_transform(entity: Dictionary) -> Dictionary:
	var t: Dictionary = entity.get("transform", {})
	return {
		"position": v3(t.get("position"), Vector3.ZERO),
		"rotation": v3(t.get("rotation"), Vector3.ZERO),
		"scale": v3(t.get("scale"), Vector3.ONE),
	}

static func node_transform_dict(node: Node3D) -> Dictionary:
	return transform_dict(node.position, node.rotation_degrees, node.scale)

# --- Ids -------------------------------------------------------------------------

static func new_id() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(10)
	var s := "e_"
	for b in bytes:
		s += ID_ALPHABET[b % ID_ALPHABET.length()]
	return s

static func is_valid_id(id) -> bool:
	if not (id is String) or id.is_empty() or id.length() > 64:
		return false
	for i in id.length():
		var c: int = id.unicode_at(i)
		var ok: bool = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or c == 45
		if not ok:
			return false
	return true

static func is_safe_name(name) -> bool:
	if not (name is String) or name.strip_edges().is_empty() or name.length() > 64:
		return false
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", ".."]:
		if name.contains(bad):
			return false
	return true

# --- Scene documents -------------------------------------------------------------

static func new_scene(scene_name: String = "Main") -> Dictionary:
	return {
		"format": SCENE_FORMAT,
		"formatVersion": SCENE_FORMAT_VERSION,
		"name": scene_name,
		"settings": default_scene_settings(),
		"entities": [],
	}

static func default_scene_settings() -> Dictionary:
	return {
		"environmentPreset": "day",
		"exposure": 1.0,
		"ambientIntensity": 1.0,
		"fogEnabled": true,
		"fogDensity": 0.0008,
		"fogColor": arr_col(Color(0.72, 0.78, 0.86)),
		"timeOfDay": 14.0,
		"weather": "clear",
		"postFx": {"dofEnabled": false, "dofDistance": 120.0, "dofAmount": 0.08, "glowIntensity": 0.35, "contrast": 1.04, "saturation": 1.06, "speedBlur": true},
		"race": {"enabled": true, "laps": 3, "countdown": 3.0, "aiOpponents": 3, "aiDifficulty": 0.7, "aiBehavior": "balanced", "autoStart": true, "mode": "auto"},
	}

## Validates a parsed scene. Returns a list of human-readable problems (empty = valid).
static func validate_scene(scene) -> PackedStringArray:
	var problems := PackedStringArray()
	if not (scene is Dictionary):
		problems.append("scene is not a JSON object")
		return problems
	if scene.get("format") != SCENE_FORMAT:
		problems.append("not a Zino scene (format '%s')" % str(scene.get("format")))
		return problems
	var version := int(scene.get("formatVersion", 0))
	if version > SCENE_FORMAT_VERSION:
		problems.append("scene format v%d is newer than this Zino supports (v%d)" % [version, SCENE_FORMAT_VERSION])
		return problems
	if not (scene.get("entities") is Array):
		problems.append("entities list is missing")
		return problems
	var ids := {}
	for e in scene["entities"]:
		if not (e is Dictionary):
			problems.append("an entity entry is not an object")
			continue
		problems.append_array(validate_entity(e))
		var id = e.get("id")
		if is_valid_id(id):
			if ids.has(id):
				problems.append("duplicate entity id '%s'" % id)
			ids[id] = e.get("parentId")
	for id in ids:
		var parent = ids[id]
		if parent != null and not ids.has(parent):
			problems.append("entity '%s' references missing parent '%s'" % [id, parent])
	# Parent cycles.
	for id in ids:
		var seen := {}
		var cur = id
		while cur != null and ids.has(cur):
			if seen.has(cur):
				problems.append("parent cycle involving '%s'" % id)
				break
			seen[cur] = true
			cur = ids[cur]
	return problems

static func validate_entity(e: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var id = e.get("id")
	if not is_valid_id(id):
		problems.append("entity '%s' has an invalid id" % str(e.get("name", "?")))
	if not (e.get("name") is String):
		problems.append("entity '%s' has no name" % str(id))
	if not (e.get("type") is String):
		problems.append("entity '%s' has no type" % str(id))
	var parent = e.get("parentId")
	if parent != null and not is_valid_id(parent):
		problems.append("entity '%s' has an invalid parentId" % str(id))
	var t = e.get("transform")
	if not (t is Dictionary):
		problems.append("entity '%s' has no transform" % str(id))
	else:
		for key in ["position", "rotation", "scale"]:
			if not is_finite_array(t.get(key), 3):
				problems.append("entity '%s' transform.%s must be 3 finite numbers" % [str(id), key])
	var road = e.get("road")
	if road is Dictionary:
		var pts = road.get("points", [])
		if not (pts is Array):
			problems.append("road '%s' points must be an array" % str(id))
		elif pts.size() > MAX_ROAD_POINTS:
			problems.append("road '%s' has too many points" % str(id))
		else:
			for p in pts:
				if not is_finite_array(p, 3):
					problems.append("road '%s' has an invalid point" % str(id))
					break
	return problems

static func find_entity(scene: Dictionary, id: String) -> Dictionary:
	for e in scene.get("entities", []):
		if e.get("id") == id:
			return e
	return {}

static func index_of(scene: Dictionary, id: String) -> int:
	var list: Array = scene.get("entities", [])
	for i in list.size():
		if list[i].get("id") == id:
			return i
	return -1

static func children_of(scene: Dictionary, parent_id) -> Array:
	var out: Array = []
	for e in scene.get("entities", []):
		if e.get("parentId") == parent_id:
			out.append(e)
	return out

## Entity plus all descendants, parents first.
static func with_descendants(scene: Dictionary, id: String) -> Array:
	var out: Array = []
	var root := find_entity(scene, id)
	if root.is_empty():
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var e: Dictionary = stack.pop_back()
		out.append(e)
		for c in children_of(scene, e["id"]):
			stack.append(c)
	return out

static func is_descendant_of(scene: Dictionary, id: String, ancestor_id: String) -> bool:
	var cur := find_entity(scene, id)
	var guard := 0
	while not cur.is_empty() and cur.get("parentId") != null and guard < 100000:
		guard += 1
		if cur["parentId"] == ancestor_id:
			return true
		cur = find_entity(scene, cur["parentId"])
	return false

static func unique_name(scene: Dictionary, base: String) -> String:
	var names := {}
	for e in scene.get("entities", []):
		names[e.get("name", "")] = true
	if not names.has(base):
		return base
	var n := 1
	while names.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]

# --- JSON file IO -----------------------------------------------------------------

static func to_json(data, indented: bool = true) -> String:
	return JSON.stringify(data, "\t" if indented else "", false)

## Parses JSON text. Returns {ok, data, error}.
static func parse_json(text: String) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return {"ok": false, "data": null, "error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	return {"ok": true, "data": json.data, "error": ""}

static func read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": null, "error": "file not found: " + path}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		return {"ok": false, "data": null, "error": "cannot read %s (error %d)" % [path, FileAccess.get_open_error()]}
	return parse_json(text)

## Writes text atomically: write <path>.tmp, keep the previous file as <path>.bak, then rename.
## A crash mid-write therefore never leaves a truncated file behind.
static func write_text_atomic(path: String, text: String, keep_backup: bool = true) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	f.close()
	if FileAccess.file_exists(path):
		if keep_backup:
			var bak := path + ".bak"
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			var e1 := DirAccess.rename_absolute(path, bak)
			if e1 != OK:
				return e1
		else:
			DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)

## Loads and validates a scene file. Returns {ok, scene, error}.
static func load_scene_file(path: String) -> Dictionary:
	var r := read_json_file(path)
	if not r.ok:
		return {"ok": false, "scene": {}, "error": r.error}
	var scene = r.data
	if scene is Dictionary and int(scene.get("formatVersion", 0)) < 1:
		scene["formatVersion"] = 1 # migration hook for pre-release files
	var problems := validate_scene(scene)
	if not problems.is_empty():
		return {"ok": false, "scene": {}, "error": "scene failed validation:\n - " + "\n - ".join(problems)}
	return {"ok": true, "scene": scene, "error": ""}

static func save_scene_file(path: String, scene: Dictionary) -> Error:
	var problems := validate_scene(scene)
	if not problems.is_empty():
		push_error("Refusing to save invalid scene: " + "; ".join(problems))
		return ERR_INVALID_DATA
	return write_text_atomic(path, to_json(scene))
