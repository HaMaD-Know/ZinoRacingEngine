@tool
class_name ZinoBlockLibrary
extends RefCounted
## Every Zino block: id, category, kind, label and typed inputs.
##
## kinds: "event" (starts a script), "function" (defines a function), "stmt" (runs, then continues
## to `next`), "control" (has extra exec outputs such as then/else/body), "value" (returns a value).
## Input types: number, bool, text, vector, color, any, list, vehicle (entity name or "player"),
## var (variable name), enum:a|b|c. Values are passed to ZinoBlockRuntime, which implements them.

const TYPES := ["exec", "number", "bool", "text", "vector", "any", "list"]
## Port colours shown in the Block Studio, indexed like TYPES.
const TYPE_COLORS := [Color("f5f5f7"), Color("30d158"), Color("ff453a"), Color("ff375f"), Color("ffd60a"), Color("98989d"), Color("bf5af2")]

const CATEGORIES := [
	["Events", "ff9f0a"], ["Race", "ff453a"], ["Vehicles", "0a84ff"], ["Physics", "5e5ce6"], ["AI", "bf5af2"],
	["Camera", "64d2ff"], ["Environment", "30d158"], ["Audio", "ff375f"], ["UI", "ffd60a"], ["Input", "ac8e68"],
	["Logic", "5ac8fa"], ["Loops", "ff9f0a"], ["Math", "34c759"], ["Text", "ff6482"], ["Variables", "ff9500"],
	["Lists", "af52de"], ["Functions", "8e8e93"], ["Data", "a2845e"], ["Debug", "636366"],
]

const KEYS := "space|enter|w|a|s|d|q|e|r|f|c|n|m|up|down|left|right|shift|ctrl|1|2|3|4|5|f1|escape"
const ACTIONS := "zino_accelerate|zino_brake|zino_steer_left|zino_steer_right|zino_handbrake|zino_reset_vehicle|zino_camera_next|zino_nitro|zino_pause"

## [id, category, kind, label, inputs [[name, type, default]], output type, extra exec outputs]
const DEFS := [
	# --- Events
	["ev_game_start", "Events", "event", "When game starts", [], "", []],
	["ev_player_join", "Events", "event", "When player joins", [], "", []],
	["ev_every_frame", "Events", "event", "Every frame", [], "", []],
	["ev_timer", "Events", "event", "Every {seconds} seconds", [["seconds", "number", 1.0]], "", []],
	["ev_countdown", "Events", "event", "When countdown starts", [], "", []],
	["ev_race_start", "Events", "event", "When race starts", [], "", []],
	["ev_race_finish", "Events", "event", "When race finishes", [], "", []],
	["ev_lap", "Events", "event", "When a lap is completed", [], "", []],
	["ev_checkpoint", "Events", "event", "When checkpoint is reached", [], "", []],
	["ev_collision", "Events", "event", "When vehicle collides", [], "", []],
	["ev_key", "Events", "event", "When key {key} is pressed", [["key", "enum:" + KEYS, "space"]], "", []],
	["ev_action", "Events", "event", "When button {action} is pressed", [["action", "enum:" + ACTIONS, "zino_nitro"]], "", []],
	["ev_area", "Events", "event", "When player enters {area}", [["area", "text", "Checkpoint 1"]], "", []],
	["ev_message", "Events", "event", "When I receive {message}", [["message", "text", "go"]], "", []],
	["msg_broadcast", "Events", "stmt", "Broadcast {message}", [["message", "text", "go"]], "", []],
	# --- Race
	["race_start", "Race", "stmt", "Start race", [], "", []],
	["race_stop", "Race", "stmt", "Stop race", [], "", []],
	["race_restart", "Race", "stmt", "Restart race", [], "", []],
	["race_finish", "Race", "stmt", "Finish race for {vehicle}", [["vehicle", "vehicle", "player"]], "", []],
	["race_set_laps", "Race", "stmt", "Set laps to {laps}", [["laps", "number", 3]], "", []],
	["race_set_countdown", "Race", "stmt", "Set countdown to {seconds} s", [["seconds", "number", 3]], "", []],
	["race_add_score", "Race", "stmt", "Add {points} to score", [["points", "number", 100]], "", []],
	["race_running", "Race", "value", "Race is running", [], "bool", []],
	["race_lap", "Race", "value", "Current lap of {vehicle}", [["vehicle", "vehicle", "player"]], "number", []],
	["race_total_laps", "Race", "value", "Total laps", [], "number", []],
	["race_position", "Race", "value", "Race position of {vehicle}", [["vehicle", "vehicle", "player"]], "number", []],
	["race_lap_time", "Race", "value", "Current lap time of {vehicle}", [["vehicle", "vehicle", "player"]], "number", []],
	["race_last_lap", "Race", "value", "Last lap time of {vehicle}", [["vehicle", "vehicle", "player"]], "number", []],
	["race_best_lap", "Race", "value", "Best lap time of {vehicle}", [["vehicle", "vehicle", "player"]], "number", []],
	["race_time", "Race", "value", "Race time", [], "number", []],
	["race_checkpoint", "Race", "value", "Last checkpoint of {vehicle}", [["vehicle", "vehicle", "player"]], "number", []],
	["race_racers", "Race", "value", "Number of racers", [], "number", []],
	["race_score", "Race", "value", "Score", [], "number", []],
	# --- Vehicles
	["veh_speed", "Vehicles", "value", "Speed (km/h) of {vehicle}", [["vehicle", "vehicle", "player"]], "number", []],
	["veh_rpm", "Vehicles", "value", "RPM of {vehicle}", [["vehicle", "vehicle", "player"]], "number", []],
	["veh_gear", "Vehicles", "value", "Gear of {vehicle}", [["vehicle", "vehicle", "player"]], "number", []],
	["veh_position", "Vehicles", "value", "Position of {vehicle}", [["vehicle", "vehicle", "player"]], "vector", []],
	["veh_rotation", "Vehicles", "value", "Rotation of {vehicle}", [["vehicle", "vehicle", "player"]], "vector", []],
	["veh_grounded", "Vehicles", "value", "{vehicle} is on the ground", [["vehicle", "vehicle", "player"]], "bool", []],
	["veh_set_power", "Vehicles", "stmt", "Set engine power of {vehicle} to {percent} %", [["vehicle", "vehicle", "player"], ["percent", "number", 100]], "", []],
	["veh_set_top_speed", "Vehicles", "stmt", "Set top speed of {vehicle} to {kmh} km/h", [["vehicle", "vehicle", "player"], ["kmh", "number", 230]], "", []],
	["veh_accelerate", "Vehicles", "stmt", "Accelerate {vehicle} at {amount}", [["vehicle", "vehicle", "player"], ["amount", "number", 1.0]], "", []],
	["veh_brake", "Vehicles", "stmt", "Brake {vehicle} at {amount}", [["vehicle", "vehicle", "player"], ["amount", "number", 1.0]], "", []],
	["veh_steer", "Vehicles", "stmt", "Steer {vehicle} to {amount}", [["vehicle", "vehicle", "player"], ["amount", "number", 0.0]], "", []],
	["veh_handbrake", "Vehicles", "stmt", "Handbrake of {vehicle} {on}", [["vehicle", "vehicle", "player"], ["on", "bool", true]], "", []],
	["veh_release", "Vehicles", "stmt", "Release script control of {vehicle}", [["vehicle", "vehicle", "player"]], "", []],
	["veh_set_gear", "Vehicles", "stmt", "Change gear of {vehicle} to {gear}", [["vehicle", "vehicle", "player"], ["gear", "number", 1]], "", []],
	["veh_auto", "Vehicles", "stmt", "Automatic gearbox of {vehicle} {on}", [["vehicle", "vehicle", "player"], ["on", "bool", true]], "", []],
	["veh_control", "Vehicles", "stmt", "Player control of {vehicle} {on}", [["vehicle", "vehicle", "player"], ["on", "bool", true]], "", []],
	["veh_reset", "Vehicles", "stmt", "Reset {vehicle} to its start", [["vehicle", "vehicle", "player"]], "", []],
	["veh_teleport", "Vehicles", "stmt", "Move {vehicle} to {position}", [["vehicle", "vehicle", "player"], ["position", "vector", [0, 1, 0]]], "", []],
	["veh_paint", "Vehicles", "stmt", "Paint {vehicle} {color}", [["vehicle", "vehicle", "player"], ["color", "color", "#d01010"]], "", []],
	["veh_profile", "Vehicles", "stmt", "Use {profile} handling on {vehicle}", [["profile", "enum:arcade|simulation|drift|drag|kart|circuit|openWorld", "arcade"], ["vehicle", "vehicle", "player"]], "", []],
	["veh_nitro", "Vehicles", "stmt", "Nitro boost {vehicle} for {seconds} s at {strength} x", [["vehicle", "vehicle", "player"], ["seconds", "number", 2.0], ["strength", "number", 1.6]], "", []],
	# --- Physics
	["phy_velocity", "Physics", "value", "Velocity of {vehicle}", [["vehicle", "vehicle", "player"]], "vector", []],
	["phy_force", "Physics", "stmt", "Apply force {force} to {vehicle}", [["force", "vector", [0, 0, -5000]], ["vehicle", "vehicle", "player"]], "", []],
	["phy_impulse", "Physics", "stmt", "Apply impulse {impulse} to {vehicle}", [["impulse", "vector", [0, 2000, 0]], ["vehicle", "vehicle", "player"]], "", []],
	["phy_gravity", "Physics", "value", "Gravity", [], "number", []],
	["phy_set_gravity", "Physics", "stmt", "Set gravity to {g} m/s²", [["g", "number", 9.8]], "", []],
	["phy_suspension", "Physics", "stmt", "Set suspension stiffness of {vehicle} to {stiffness}", [["vehicle", "vehicle", "player"], ["stiffness", "number", 45]], "", []],
	["phy_friction", "Physics", "stmt", "Set tyre grip of {vehicle} front {front} rear {rear}", [["vehicle", "vehicle", "player"], ["front", "number", 10.5], ["rear", "number", 10.5]], "", []],
	["phy_wheel_contact", "Physics", "value", "Wheel {wheel} of {vehicle} touches ground", [["wheel", "number", 1], ["vehicle", "vehicle", "player"]], "bool", []],
	["phy_mass", "Physics", "stmt", "Set mass of {vehicle} to {kg} kg", [["vehicle", "vehicle", "player"], ["kg", "number", 1350]], "", []],
	["phy_downforce", "Physics", "stmt", "Set downforce of {vehicle} to {amount}", [["vehicle", "vehicle", "player"], ["amount", "number", 3]], "", []],
	# --- AI
	["ai_start", "AI", "stmt", "Start AI opponents", [], "", []],
	["ai_stop", "AI", "stmt", "Stop AI opponents", [], "", []],
	["ai_difficulty", "AI", "stmt", "Set AI difficulty to {level} %", [["level", "number", 70]], "", []],
	["ai_behavior", "AI", "stmt", "Set AI behaviour to {style}", [["style", "enum:cautious|balanced|aggressive", "balanced"]], "", []],
	["ai_follow_line", "AI", "stmt", "AI follows racing line {on}", [["on", "bool", true]], "", []],
	["ai_target", "AI", "stmt", "Send {vehicle} to {position}", [["vehicle", "vehicle", "AI 1"], ["position", "vector", [0, 0, 0]]], "", []],
	["ai_count", "AI", "value", "Number of AI opponents", [], "number", []],
	["ai_player_position", "AI", "value", "Player position", [], "vector", []],
	# --- Camera
	["cam_mode", "Camera", "stmt", "Set camera to {mode}", [["mode", "enum:chase|closeChase|hood|bumper|cockpit|orbit", "chase"]], "", []],
	["cam_fov", "Camera", "stmt", "Set field of view to {fov}°", [["fov", "number", 70]], "", []],
	["cam_shake", "Camera", "stmt", "Shake camera {strength} for {seconds} s", [["strength", "number", 0.3], ["seconds", "number", 0.5]], "", []],
	["cam_target", "Camera", "stmt", "Camera follows {vehicle}", [["vehicle", "vehicle", "player"]], "", []],
	# --- Environment
	["env_time", "Environment", "stmt", "Set time of day to {hours} h", [["hours", "number", 18.5]], "", []],
	["env_weather", "Environment", "stmt", "Set weather to {weather}", [["weather", "enum:clear|cloudy|rain|storm|fog", "rain"]], "", []],
	["env_fog", "Environment", "stmt", "Set fog density to {density}", [["density", "number", 0.002]], "", []],
	["env_exposure", "Environment", "stmt", "Set exposure to {value}", [["value", "number", 1.0]], "", []],
	["env_preset", "Environment", "stmt", "Use {preset} environment", [["preset", "enum:day|sunset|overcast|night", "sunset"]], "", []],
	["env_sun", "Environment", "stmt", "Set sunlight to {intensity}", [["intensity", "number", 1.3]], "", []],
	["env_time_value", "Environment", "value", "Time of day", [], "number", []],
	# --- Audio
	["aud_play", "Audio", "stmt", "Play sound {sound}", [["sound", "text", "Assets/Audio/horn.ogg"]], "", []],
	["aud_stop", "Audio", "stmt", "Stop all sounds", [], "", []],
	["aud_volume", "Audio", "stmt", "Set {bus} volume to {percent} %", [["bus", "enum:Master|Music|SFX|Engine", "Music"], ["percent", "number", 80]], "", []],
	["aud_music", "Audio", "stmt", "Play music {sound} loop {loop}", [["sound", "text", "Assets/Audio/music.ogg"], ["loop", "bool", true]], "", []],
	["aud_stop_music", "Audio", "stmt", "Stop music", [], "", []],
	["aud_engine", "Audio", "stmt", "Engine sound {on}", [["on", "bool", true]], "", []],
	["aud_tires", "Audio", "stmt", "Tyre sounds {on}", [["on", "bool", true]], "", []],
	# --- UI
	["ui_message", "UI", "stmt", "Show message {text} for {seconds} s", [["text", "text", "Go!"], ["seconds", "number", 2.0]], "", []],
	["ui_hide_message", "UI", "stmt", "Hide message", [], "", []],
	["ui_big", "UI", "stmt", "Show big text {text} for {seconds} s", [["text", "text", "FINAL LAP"], ["seconds", "number", 2.0]], "", []],
	["ui_hud", "UI", "stmt", "Show {element} {visible}", [["element", "enum:speedometer|laps|position|timer|minimap|all", "all"], ["visible", "bool", true]], "", []],
	["ui_progress", "UI", "stmt", "Set progress bar {label} to {value}", [["label", "text", "Boost"], ["value", "number", 0.5]], "", []],
	["ui_label", "UI", "stmt", "Set label {slot} to {text}", [["slot", "number", 1], ["text", "any", "Hello"]], "", []],
	["ui_results", "UI", "stmt", "Show results", [], "", []],
	["ui_menu", "UI", "stmt", "Show {menu} menu", [["menu", "enum:pause|main|results", "pause"]], "", []],
	["ui_hide_menu", "UI", "stmt", "Hide menus", [], "", []],
	# --- Input
	["in_key", "Input", "value", "Key {key} is down", [["key", "enum:" + KEYS, "space"]], "bool", []],
	["in_action", "Input", "value", "Button {action} is down", [["action", "enum:" + ACTIONS, "zino_accelerate"]], "bool", []],
	["in_throttle", "Input", "value", "Throttle input", [], "number", []],
	["in_steer", "Input", "value", "Steering input", [], "number", []],
	# --- Logic
	["ctl_if", "Logic", "control", "If {condition}", [["condition", "bool", true]], "", ["then"]],
	["ctl_if_else", "Logic", "control", "If {condition} else", [["condition", "bool", true]], "", ["then", "else"]],
	["log_compare", "Logic", "value", "{a} {op} {b}", [["a", "any", 0], ["op", "enum:=|≠|<|>|≤|≥", "="], ["b", "any", 0]], "bool", []],
	["log_and", "Logic", "value", "{a} and {b}", [["a", "bool", true], ["b", "bool", true]], "bool", []],
	["log_or", "Logic", "value", "{a} or {b}", [["a", "bool", false], ["b", "bool", false]], "bool", []],
	["log_not", "Logic", "value", "not {a}", [["a", "bool", false]], "bool", []],
	["log_bool", "Logic", "value", "{value}", [["value", "bool", true]], "bool", []],
	# --- Loops
	["loop_repeat", "Loops", "control", "Repeat {times} times", [["times", "number", 10]], "", ["body"]],
	["loop_forever", "Loops", "control", "Forever", [], "", ["body"]],
	["loop_while", "Loops", "control", "While {condition}", [["condition", "bool", true]], "", ["body"]],
	["loop_until", "Loops", "control", "Repeat until {condition}", [["condition", "bool", false]], "", ["body"]],
	["loop_for", "Loops", "control", "For {var} from {from} to {to}", [["var", "var", "i"], ["from", "number", 1], ["to", "number", 10]], "", ["body"]],
	["loop_for_each", "Loops", "control", "For each {var} in list {list}", [["var", "var", "item"], ["list", "var", "my list"]], "", ["body"]],
	["loop_break", "Loops", "stmt", "Break out of loop", [], "", []],
	["loop_wait", "Loops", "stmt", "Wait {seconds} seconds", [["seconds", "number", 1.0]], "", []],
	["loop_wait_until", "Loops", "stmt", "Wait until {condition}", [["condition", "bool", true]], "", []],
	["flow_stop", "Loops", "stmt", "Stop this script", [], "", []],
	# --- Math
	["m_num", "Math", "value", "{value}", [["value", "number", 0]], "number", []],
	["m_op", "Math", "value", "{a} {op} {b}", [["a", "number", 0], ["op", "enum:+|-|×|÷|mod|^", "+"], ["b", "number", 0]], "number", []],
	["m_fn", "Math", "value", "{fn} of {a}", [["fn", "enum:abs|round|floor|ceil|sqrt|sin|cos|tan|ln|exp|sign", "abs"], ["a", "number", 0]], "number", []],
	["m_minmax", "Math", "value", "{fn} of {a} and {b}", [["fn", "enum:min|max", "min"], ["a", "number", 0], ["b", "number", 0]], "number", []],
	["m_clamp", "Math", "value", "Clamp {value} between {min} and {max}", [["value", "number", 0], ["min", "number", 0], ["max", "number", 1]], "number", []],
	["m_lerp", "Math", "value", "Blend {a} to {b} by {t}", [["a", "number", 0], ["b", "number", 1], ["t", "number", 0.5]], "number", []],
	["m_random", "Math", "value", "Random from {min} to {max}", [["min", "number", 1], ["max", "number", 10]], "number", []],
	["m_vec", "Math", "value", "Vector {x} {y} {z}", [["x", "number", 0], ["y", "number", 0], ["z", "number", 0]], "vector", []],
	["m_vec_part", "Math", "value", "{axis} of {v}", [["axis", "enum:x|y|z|length", "x"], ["v", "vector", [0, 0, 0]]], "number", []],
	["m_vec_op", "Math", "value", "{a} {op} {b}", [["a", "vector", [0, 0, 0]], ["op", "enum:+|-", "+"], ["b", "vector", [0, 0, 0]]], "vector", []],
	["m_vec_scale", "Math", "value", "{v} × {s}", [["v", "vector", [0, 0, 1]], ["s", "number", 1]], "vector", []],
	["m_distance", "Math", "value", "Distance from {a} to {b}", [["a", "vector", [0, 0, 0]], ["b", "vector", [0, 0, 0]]], "number", []],
	["m_delta", "Math", "value", "Frame time (s)", [], "number", []],
	["m_time", "Math", "value", "Seconds since start", [], "number", []],
	# --- Text
	["t_text", "Text", "value", "{value}", [["value", "text", "Hello"]], "text", []],
	["t_join", "Text", "value", "Join {a} {b}", [["a", "any", "Lap "], ["b", "any", 1]], "text", []],
	["t_length", "Text", "value", "Length of {a}", [["a", "text", "abc"]], "number", []],
	["t_contains", "Text", "value", "{a} contains {b}", [["a", "text", "abc"], ["b", "text", "b"]], "bool", []],
	["t_time", "Text", "value", "Format {seconds} as lap time", [["seconds", "number", 83.456]], "text", []],
	["t_number", "Text", "value", "Format {value} with {decimals} decimals", [["value", "number", 0], ["decimals", "number", 0]], "text", []],
	["t_to_number", "Text", "value", "Number from {text}", [["text", "text", "42"]], "number", []],
	# --- Variables
	["var_set", "Variables", "stmt", "Set {var} to {value}", [["var", "var", "score"], ["value", "any", 0]], "", []],
	["var_change", "Variables", "stmt", "Change {var} by {by}", [["var", "var", "score"], ["by", "number", 1]], "", []],
	["var_get", "Variables", "value", "{var}", [["var", "var", "score"]], "any", []],
	# --- Lists
	["list_new", "Lists", "stmt", "Make {var} an empty list", [["var", "var", "my list"]], "", []],
	["list_add", "Lists", "stmt", "Add {item} to {var}", [["item", "any", 0], ["var", "var", "my list"]], "", []],
	["list_remove", "Lists", "stmt", "Remove item {index} of {var}", [["index", "number", 1], ["var", "var", "my list"]], "", []],
	["list_clear", "Lists", "stmt", "Clear {var}", [["var", "var", "my list"]], "", []],
	["list_get", "Lists", "value", "Item {index} of {var}", [["index", "number", 1], ["var", "var", "my list"]], "any", []],
	["list_length", "Lists", "value", "Length of {var}", [["var", "var", "my list"]], "number", []],
	["list_contains", "Lists", "value", "{var} contains {item}", [["var", "var", "my list"], ["item", "any", 0]], "bool", []],
	# --- Functions
	["fn_define", "Functions", "function", "Define {name} ( {params} )", [["name", "text", "my function"], ["params", "text", "a, b"]], "", []],
	["fn_call", "Functions", "stmt", "Call {name} ( {arg1} {arg2} {arg3} )", [["name", "text", "my function"], ["arg1", "any", 0], ["arg2", "any", 0], ["arg3", "any", 0]], "", []],
	["fn_call_value", "Functions", "value", "Result of {name} ( {arg1} {arg2} {arg3} )", [["name", "text", "my function"], ["arg1", "any", 0], ["arg2", "any", 0], ["arg3", "any", 0]], "any", []],
	["fn_return", "Functions", "stmt", "Return {value}", [["value", "any", 0]], "", []],
	["fn_param", "Functions", "value", "Parameter {name}", [["name", "text", "a"]], "any", []],
	# --- Data
	["data_save", "Data", "stmt", "Save {value} as {key}", [["value", "any", 0], ["key", "text", "best lap"]], "", []],
	["data_load", "Data", "value", "Saved {key} or {default}", [["key", "text", "best lap"], ["default", "any", 0]], "any", []],
	["data_has", "Data", "value", "Saved {key} exists", [["key", "text", "best lap"]], "bool", []],
	# --- Debug
	["dbg_log", "Debug", "stmt", "Log {value}", [["value", "any", "Hello"]], "", []],
	["dbg_warn", "Debug", "stmt", "Warn {value}", [["value", "any", "Careful"]], "", []],
]

static var _by_id := {}

static func get_def(id: String) -> Dictionary:
	if _by_id.is_empty():
		for d in DEFS:
			_by_id[d[0]] = {"id": d[0], "category": d[1], "kind": d[2], "label": d[3], "inputs": d[4], "output": d[5], "exec_outs": d[6]}
	return _by_id.get(id, {})

static func has(id: String) -> bool:
	return not get_def(id).is_empty()

static func category_color(category: String) -> Color:
	for c in CATEGORIES:
		if c[0] == category:
			return Color(c[1])
	return Color("8e8e93")

static func blocks_in(category: String) -> Array:
	var out: Array = []
	for d in DEFS:
		if d[1] == category:
			out.append(d[0])
	return out

static func search(query: String) -> Array:
	var q := query.strip_edges().to_lower()
	var out: Array = []
	for d in DEFS:
		if q == "" or str(d[3]).to_lower().contains(q) or str(d[1]).to_lower().contains(q) or str(d[0]).contains(q):
			out.append(d[0])
	return out

## Exec outputs of a block: "next" for statements/events/functions, plus extra outputs for control blocks.
static func exec_outputs(id: String) -> Array:
	var d := get_def(id)
	if d.is_empty() or d.kind == "value":
		return []
	var outs: Array = d.exec_outs.duplicate()
	outs.append("next")
	return outs

static func has_exec_input(id: String) -> bool:
	var d := get_def(id)
	return not d.is_empty() and d.kind in ["stmt", "control"]

static func type_index(t: String) -> int:
	if t.begins_with("enum:") or t == "var" or t == "vehicle" or t == "color":
		return TYPES.find("text")
	var i := TYPES.find(t)
	return i if i >= 0 else TYPES.find("any")

## Can a value of type `from` feed an input of type `to`?
static func compatible(from: String, to: String) -> bool:
	if from == to or from == "any" or to == "any":
		return true
	if to == "text" and from in ["number", "bool"]:
		return true      # numbers and booleans print as text
	if to in ["vehicle", "var", "color"] or to.begins_with("enum:"):
		return from == "text"
	return false

## Human-readable label with inputs replaced (used by the code view).
static func render_label(id: String, args: Dictionary) -> String:
	var d := get_def(id)
	var s: String = d.get("label", id)
	for k in args:
		s = s.replace("{%s}" % k, str(args[k]))
	return s
