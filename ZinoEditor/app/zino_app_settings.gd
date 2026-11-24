class_name ZinoAppSettings
extends RefCounted
## Per-user Zino Editor settings, stored in user://zino_settings.json (never inside projects).

const PATH := "user://zino_settings.json"
const MAX_RECENT := 12

var data := {
	"recentProjects": [],          # [{path, name, lastOpened}]
	"appearance": "system",       # system, light, dark
	"defaultLocation": "",
	"godotEditorPath": "",          # empty = the Godot binary running Zino
	"autosaveSeconds": 60,
	"lightweightMode": false,       # halves viewport render resolution while editing
	"translateSnap": 0.5,
	"rotateSnap": 15.0,
	"scaleSnap": 0.1,
	"snapEnabled": false,
	"showGrid": true,
	"autoLaunchGodot": false,
}

func load_settings() -> void:
	var r := ZinoFormat.read_json_file(PATH)
	if r.ok and r.data is Dictionary:
		for k in r.data:
			if data.has(k):
				data[k] = r.data[k]

func save_settings() -> void:
	ZinoFormat.write_text_atomic(ProjectSettings.globalize_path(PATH), ZinoFormat.to_json(data), false)

func get_value(key: String, fallback = null):
	return data.get(key, fallback)

func set_value(key: String, value) -> void:
	data[key] = value
	save_settings()

func recent_projects() -> Array:
	return data["recentProjects"]

func add_recent(path: String, project_name: String) -> void:
	var list: Array = data["recentProjects"].filter(func(r): return r.get("path") != path)
	list.push_front({"path": path, "name": project_name, "lastOpened": Time.get_datetime_string_from_system(false, true)})
	data["recentProjects"] = list.slice(0, MAX_RECENT)
	save_settings()

func remove_recent(path: String) -> void:
	data["recentProjects"] = data["recentProjects"].filter(func(r): return r.get("path") != path)
	save_settings()

## The Godot editor binary: Settings → zino_config.json next to Zino.exe (release) → the running
## binary when Zino runs from source. Returns "" when none is known (release without config).
func godot_editor_path() -> String:
	var p: String = data.get("godotEditorPath", "")
	if p != "" and FileAccess.file_exists(p):
		return p
	var cfg := ZinoFormat.read_json_file(OS.get_executable_path().get_base_dir().path_join("zino_config.json"))
	if cfg.ok and cfg.data is Dictionary and FileAccess.file_exists(str(cfg.data.get("godotPath", ""))):
		return str(cfg.data.godotPath)
	if OS.has_feature("editor"):
		return OS.get_executable_path()
	return ""
