@tool
class_name ZinoProtocol
extends RefCounted
## Zino Bridge protocol v1 — shared by the Zino Editor (server) and the Godot editor plugin (client).
## See docs/PROTOCOL.md. Every request is validated against this whitelist by the receiving side;
## anything unknown or malformed is rejected without being executed.

const VERSION := 1
const SESSION_FILE := "Cache/zino_bridge_session.json"
const MAX_MESSAGE_BYTES := 8 * 1024 * 1024
const HELLO_TIMEOUT_MS := 5000
const REQUEST_TIMEOUT_MS := 15000

# Commands sent by the Zino Editor to the Godot editor plugin.
const PING := "PING"
const GET_INFO := "GET_INFO"
const LOAD_SCENE := "LOAD_SCENE"
const CREATE_OBJECT := "CREATE_OBJECT"
const UPDATE_OBJECT := "UPDATE_OBJECT"
const DELETE_OBJECT := "DELETE_OBJECT"
const SELECT_OBJECT := "SELECT_OBJECT"
const MOVE_OBJECT := "MOVE_OBJECT"
const ROTATE_OBJECT := "ROTATE_OBJECT"
const SCALE_OBJECT := "SCALE_OBJECT"
const SET_TRANSFORM := "SET_TRANSFORM"
const ASSIGN_MATERIAL := "ASSIGN_MATERIAL"
const IMPORT_ASSET := "IMPORT_ASSET"
const SAVE_SCENE := "SAVE_SCENE"
const START_PLAYTEST := "START_PLAYTEST"
const STOP_PLAYTEST := "STOP_PLAYTEST"

const COMMANDS := [PING, GET_INFO, LOAD_SCENE, CREATE_OBJECT, UPDATE_OBJECT, DELETE_OBJECT, SELECT_OBJECT,
	MOVE_OBJECT, ROTATE_OBJECT, SCALE_OBJECT, SET_TRANSFORM, ASSIGN_MATERIAL, IMPORT_ASSET, SAVE_SCENE,
	START_PLAYTEST, STOP_PLAYTEST]

# Events sent by the Godot editor plugin to the Zino Editor.
const EV_SELECTION_CHANGED := "SELECTION_CHANGED"
const EV_TRANSFORM_CHANGED := "TRANSFORM_CHANGED"
const EV_PLAYTEST_STATE := "PLAYTEST_STATE"
const EV_LOG := "LOG"
const EVENTS := [EV_SELECTION_CHANGED, EV_TRANSFORM_CHANGED, EV_PLAYTEST_STATE, EV_LOG]

const ERR_UNKNOWN_COMMAND := "UNKNOWN_COMMAND"
const ERR_INVALID_PAYLOAD := "INVALID_PAYLOAD"
const ERR_NOT_FOUND := "NOT_FOUND"
const ERR_FAILED := "FAILED"
const ERR_TIMEOUT := "TIMEOUT"
const ERR_DISCONNECTED := "DISCONNECTED"

static func request(id: int, cmd: String, payload: Dictionary = {}) -> Dictionary:
	return {"type": "request", "id": id, "cmd": cmd, "payload": payload}

static func response_ok(id: int, payload: Dictionary = {}) -> Dictionary:
	return {"type": "response", "id": id, "ok": true, "payload": payload}

static func response_error(id: int, code: String, message: String) -> Dictionary:
	return {"type": "response", "id": id, "ok": false, "error": {"code": code, "message": message}}

static func event(name: String, payload: Dictionary = {}) -> Dictionary:
	return {"type": "event", "name": name, "payload": payload}

static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)

## Parses one message. Returns {} for anything that is not a JSON object with a string "type".
static func decode(text: String) -> Dictionary:
	if text.length() > MAX_MESSAGE_BYTES:
		return {}
	var data = JSON.parse_string(text)
	if data is Dictionary and data.get("type") is String:
		return data
	return {}

static func new_token() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()

## Constant-time comparison so the token cannot be guessed byte by byte from timing.
static func tokens_equal(a: String, b: String) -> bool:
	var ba := a.to_utf8_buffer()
	var bb := b.to_utf8_buffer()
	if ba.size() != bb.size() or ba.is_empty():
		return false
	var diff := 0
	for i in ba.size():
		diff |= ba[i] ^ bb[i]
	return diff == 0

# --- Validation ---------------------------------------------------------------------

## Returns "" when the request is acceptable, otherwise a reason. Called before any command executes.
static func validate_request(cmd, payload) -> String:
	if not (cmd is String) or not cmd in COMMANDS:
		return "unknown command '%s'" % str(cmd)
	if not (payload is Dictionary):
		return "payload must be an object"
	match cmd:
		PING, GET_INFO, START_PLAYTEST, STOP_PLAYTEST:
			return ""
		LOAD_SCENE:
			var problems := ZinoFormat.validate_scene(payload.get("scene"))
			if not problems.is_empty():
				return "invalid scene: " + "; ".join(problems)
			return _check_scene_name(payload.get("sceneName"))
		CREATE_OBJECT, UPDATE_OBJECT:
			var e = payload.get("entity")
			if not (e is Dictionary):
				return "entity must be an object"
			var problems2 := ZinoFormat.validate_entity(e)
			return "" if problems2.is_empty() else "invalid entity: " + "; ".join(problems2)
		DELETE_OBJECT, SELECT_OBJECT:
			return _check_ids(payload.get("ids"), cmd == SELECT_OBJECT)
		MOVE_OBJECT:
			return _check_id(payload.get("id")) + _check_vec(payload.get("position"), "position")
		ROTATE_OBJECT:
			return _check_id(payload.get("id")) + _check_vec(payload.get("rotation"), "rotation")
		SCALE_OBJECT:
			return _check_id(payload.get("id")) + _check_vec(payload.get("scale"), "scale")
		SET_TRANSFORM:
			var items = payload.get("items")
			if not (items is Array) or items.is_empty() or items.size() > 10000:
				return "items must be a non-empty array"
			for it in items:
				if not (it is Dictionary):
					return "item must be an object"
				var r := _check_id(it.get("id"))
				for k in ["position", "rotation", "scale"]:
					r += _check_vec(it.get(k), k)
				if r != "":
					return r
			return ""
		ASSIGN_MATERIAL:
			var m = payload.get("material")
			if not (m is Dictionary):
				return "material must be an object"
			if m.has("color") and not ZinoFormat.is_finite_array(m["color"], 4):
				return "material.color must be 4 numbers"
			return _check_id(payload.get("id"))
		IMPORT_ASSET:
			return _check_relative_asset_path(payload.get("path"))
		SAVE_SCENE:
			return _check_scene_name(payload.get("sceneName"))
	return ""

static func _check_id(id) -> String:
	return "" if ZinoFormat.is_valid_id(id) else "invalid id '%s'; " % str(id)

static func _check_ids(ids, allow_empty: bool) -> String:
	if not (ids is Array) or ids.size() > 10000 or (ids.is_empty() and not allow_empty):
		return "ids must be an array of entity ids"
	for id in ids:
		if not ZinoFormat.is_valid_id(id):
			return "invalid id '%s'" % str(id)
	return ""

static func _check_vec(v, name: String) -> String:
	return "" if ZinoFormat.is_finite_array(v, 3) else "%s must be 3 finite numbers; " % name

static func _check_scene_name(n) -> String:
	if n == null:
		return ""
	return "" if ZinoFormat.is_safe_name(n) and str(n).is_valid_filename() else "invalid scene name"

## Asset imports may only reference files inside the project's Assets/ folder.
static func _check_relative_asset_path(p) -> String:
	if not (p is String) or p.is_empty() or p.length() > 512:
		return "path must be a string"
	var s: String = p.replace("\\", "/")
	if s.begins_with("/") or s.contains(":") or s.contains("..") or not s.begins_with("Assets/"):
		return "path must be relative and inside Assets/"
	return ""
