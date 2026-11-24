class_name ZinoBlockRecipes
extends RefCounted
## Block recipes: ready-made, pre-wired groups of blocks for common racing-game rules.
## A recipe inserts ordinary blocks, so it can be changed afterwards like anything you built yourself.
## Format: n = [key, block id, x, y, values], l = [from key, output, to key, input].

const RECIPES := [
	{"id": "boost_key", "icon": "🚀", "name": "Boost on a key", "desc": "Press F for a 2-second nitro boost.",
		"n": [["ev", "ev_key", 0, 0, {"key": "f"}], ["nitro", "veh_nitro", 320, 0, {"seconds": 2.0, "strength": 1.6}],
			["msg", "ui_message", 640, 0, {"text": "BOOST!", "seconds": 1.0}]],
		"l": [["ev", "next", "nitro", "exec"], ["nitro", "next", "msg", "exec"]]},
	{"id": "final_lap", "icon": "🏁", "name": "Final lap alert", "desc": "Big \"FINAL LAP\" text when the last lap starts.",
		"n": [["ev", "ev_lap", 0, 0, {}], ["if", "ctl_if", 320, 0, {}], ["cmp", "log_compare", 0, 140, {"op": "="}],
			["cur", "race_lap", -320, 140, {}], ["tot", "race_total_laps", -320, 240, {}],
			["big", "ui_big", 640, 0, {"text": "FINAL LAP", "seconds": 2.5}]],
		"l": [["ev", "next", "if", "exec"], ["cur", "value", "cmp", "a"], ["tot", "value", "cmp", "b"],
			["cmp", "value", "if", "condition"], ["if", "then", "big", "exec"]]},
	{"id": "lap_timer", "icon": "⏱", "name": "Lap timer on screen", "desc": "Shows the running lap time in a label.",
		"n": [["ev", "ev_every_frame", 0, 0, {}], ["label", "ui_label", 320, 0, {"slot": 1}],
			["join", "t_join", 0, 140, {"a": "Lap time  "}], ["fmt", "t_time", -320, 140, {}], ["lt", "race_lap_time", -640, 140, {}]],
		"l": [["ev", "next", "label", "exec"], ["lt", "value", "fmt", "seconds"], ["fmt", "value", "join", "b"], ["join", "value", "label", "text"]]},
	{"id": "rain_lap2", "icon": "🌧", "name": "Rain from lap 2", "desc": "The weather turns to rain once lap 2 begins.",
		"n": [["ev", "ev_lap", 0, 0, {}], ["if", "ctl_if", 320, 0, {}], ["cmp", "log_compare", 0, 140, {"op": "≥", "b": 2}],
			["cur", "race_lap", -320, 140, {}], ["rain", "env_weather", 640, 0, {"weather": "rain"}],
			["msg", "ui_message", 960, 0, {"text": "Rain is coming — watch your grip!", "seconds": 2.5}]],
		"l": [["ev", "next", "if", "exec"], ["cur", "value", "cmp", "a"], ["cmp", "value", "if", "condition"],
			["if", "then", "rain", "exec"], ["rain", "next", "msg", "exec"]]},
	{"id": "save_best", "icon": "🏆", "name": "Save your best lap", "desc": "Keeps your record between plays and shows it at the start.",
		"n": [["fin", "ev_race_finish", 0, 0, {}], ["if", "ctl_if", 320, 0, {}], ["or", "log_or", 0, 140, {}],
			["has", "data_has", -320, 120, {"key": "best lap"}], ["nothas", "log_not", -160, 120, {}],
			["better", "log_compare", -160, 240, {"op": "<"}], ["mine", "race_best_lap", -480, 240, {}],
			["old", "data_load", -480, 340, {"key": "best lap", "default": 0}],
			["save", "data_save", 640, 0, {"key": "best lap"}], ["mine2", "race_best_lap", 320, 160, {}],
			["rec", "ui_message", 960, 0, {"text": "New record saved!", "seconds": 3.0}],
			["st", "ev_race_start", 0, 480, {}], ["if2", "ctl_if", 320, 480, {}], ["has2", "data_has", 0, 600, {"key": "best lap"}],
			["show", "ui_message", 640, 480, {"seconds": 3.0}], ["join", "t_join", 320, 640, {"a": "Your record: "}],
			["fmt", "t_time", 0, 720, {}], ["old2", "data_load", -320, 720, {"key": "best lap", "default": 0}]],
		"l": [["fin", "next", "if", "exec"], ["has", "value", "nothas", "a"], ["nothas", "value", "or", "a"],
			["mine", "value", "better", "a"], ["old", "value", "better", "b"], ["better", "value", "or", "b"],
			["or", "value", "if", "condition"], ["if", "then", "save", "exec"], ["mine2", "value", "save", "value"],
			["save", "next", "rec", "exec"],
			["st", "next", "if2", "exec"], ["has2", "value", "if2", "condition"], ["if2", "then", "show", "exec"],
			["old2", "value", "fmt", "seconds"], ["fmt", "value", "join", "b"], ["join", "value", "show", "text"]]},
	{"id": "stuck_help", "icon": "🛟", "name": "Stuck helper", "desc": "If the car stops during the race, tells the player to press R.",
		"n": [["ev", "ev_timer", 0, 0, {"seconds": 3.0}], ["if", "ctl_if", 320, 0, {}], ["and", "log_and", 0, 140, {}],
			["run", "race_running", -320, 120, {}], ["slow", "log_compare", -320, 220, {"op": "<", "b": 3}],
			["spd", "veh_speed", -640, 220, {}], ["msg", "ui_message", 640, 0, {"text": "Stuck? Press R to reset", "seconds": 2.5}]],
		"l": [["ev", "next", "if", "exec"], ["run", "value", "and", "a"], ["spd", "value", "slow", "a"], ["slow", "value", "and", "b"],
			["and", "value", "if", "condition"], ["if", "then", "msg", "exec"]]},
	{"id": "speed_score", "icon": "⭐", "name": "Speed bonus score", "desc": "+10 points every second you drive over 150 km/h.",
		"n": [["ev", "ev_timer", 0, 0, {"seconds": 1.0}], ["if", "ctl_if", 320, 0, {}], ["fast", "log_compare", 0, 140, {"op": ">", "b": 150}],
			["spd", "veh_speed", -320, 140, {}], ["add", "race_add_score", 640, 0, {"points": 10}],
			["label", "ui_label", 960, 0, {"slot": 2}], ["join", "t_join", 640, 160, {"a": "Score  "}], ["sc", "race_score", 320, 200, {}]],
		"l": [["ev", "next", "if", "exec"], ["spd", "value", "fast", "a"], ["fast", "value", "if", "condition"],
			["if", "then", "add", "exec"], ["add", "next", "label", "exec"], ["sc", "value", "join", "b"], ["join", "value", "label", "text"]]},
	{"id": "night_race", "icon": "🌙", "name": "Night race", "desc": "The race always starts at night.",
		"n": [["ev", "ev_game_start", 0, 0, {}], ["t", "env_time", 320, 0, {"hours": 23.0}]],
		"l": [["ev", "next", "t", "exec"]]},
	{"id": "get_ready", "icon": "🚦", "name": "\"GET READY\" countdown", "desc": "Big text while the start lights count down.",
		"n": [["ev", "ev_countdown", 0, 0, {}], ["big", "ui_big", 320, 0, {"text": "GET READY", "seconds": 2.0}]],
		"l": [["ev", "next", "big", "exec"]]},
	{"id": "victory", "icon": "🥇", "name": "Victory message", "desc": "\"YOU WIN!\" for first place, \"Try again\" otherwise.",
		"n": [["ev", "ev_race_finish", 0, 0, {}], ["if", "ctl_if_else", 320, 0, {}], ["first", "log_compare", 0, 140, {"op": "=", "b": 1}],
			["pos", "race_position", -320, 140, {}], ["win", "ui_big", 640, 0, {"text": "YOU WIN!", "seconds": 3.0}],
			["lose", "ui_big", 640, 140, {"text": "Try again!", "seconds": 3.0}]],
		"l": [["ev", "next", "if", "exec"], ["pos", "value", "first", "a"], ["first", "value", "if", "condition"],
			["if", "then", "win", "exec"], ["if", "else", "lose", "exec"]]},
]

static func find(id: String) -> Dictionary:
	for r in RECIPES:
		if r.id == id:
			return r
	return {}

## Builds the nodes and links of a recipe with fresh ids, placed with its first block at `origin`.
## Returns {nodes, links} or {} for an unknown recipe.
static func build(id: String, origin: Vector2 = Vector2.ZERO) -> Dictionary:
	var r := find(id)
	if r.is_empty():
		return {}
	var ids := {}
	var nodes: Array = []
	var links: Array = []
	for d in r.n:
		var pos := origin + Vector2(float(d[2]), float(d[3]))
		var n := ZinoBlockCompiler.node(str(d[1]), pos, d[4])
		ids[d[0]] = n.id
		nodes.append(n)
	for l in r.l:
		links.append(ZinoBlockCompiler.link(ids[l[0]], str(l[1]), ids[l[2]], str(l[3])))
	return {"nodes": nodes, "links": links}
