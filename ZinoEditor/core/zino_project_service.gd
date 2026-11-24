class_name ZinoProjectService
extends RefCounted
## Creates, opens, validates and saves Zino projects.
##
## A Zino project folder is also a valid Godot project, so it can be opened in the Godot editor
## (with the Zino bridge plugin) and exported with Godot's official export pipeline.

const MANIFEST_FILE := "project.zino"
const FOLDERS := [
	"Config", "Assets", "Assets/Vehicles", "Assets/Tracks", "Assets/Materials", "Assets/Textures",
	"Assets/Audio", "Assets/Environment", "Assets/UI", "Scenes", "Scripts", "Blocks", "Worlds",
	"Builds", "Cache", "Cache/autosave", "Plugins",
]
const ADDONS := ["zino_runtime", "zino_bridge"]
const TARGET_PLATFORMS := ["ios", "windows", "android"]
const ENVIRONMENTS := {"day": "Clear day", "sunset": "Sunset", "overcast": "Overcast"}

# --- Paths ---------------------------------------------------------------------------

## Where the engine's add-ons are copied from: the Zino Editor's own res://addons when running
## from source, <install dir>/engine/addons for a desktop build, or (iPhone/iPad) the add-ons zip
## bundled inside the app, unpacked once into user://.
const BUNDLED_ADDONS := "res://engine_addons.zip"

static func engine_addons_dir() -> String:
	var dev := ProjectSettings.globalize_path("res://addons")
	if DirAccess.dir_exists_absolute(dev.path_join("zino_runtime")):
		return dev
	var installed := OS.get_executable_path().get_base_dir().path_join("engine/addons")
	if DirAccess.dir_exists_absolute(installed.path_join("zino_runtime")) or not FileAccess.file_exists(BUNDLED_ADDONS):
		return installed
	var dst := OS.get_user_data_dir().path_join("engine/%s" % ZinoFormat.ENGINE_VERSION)
	if not DirAccess.dir_exists_absolute(dst.path_join("addons/zino_runtime")):
		var err := extract_addons(BUNDLED_ADDONS, dst)
		if err != OK:
			ZinoAppLog.error("Project", "Could not unpack the engine add-ons (%d)" % err)
	return dst.path_join("addons")

## Packs res://addons/zino_runtime and zino_bridge into a zip (entries start with "addons/").
## Used when building the iPhone/iPad app, which has no engine folder next to it.
static func pack_engine_addons(zip_path: String) -> Error:
	var z := ZIPPacker.new()
	var err := z.open(zip_path)
	if err != OK:
		return err
	for addon in ["zino_runtime", "zino_bridge"]:
		err = _zip_dir(z, ProjectSettings.globalize_path("res://addons").path_join(addon), "addons/" + addon)
		if err != OK:
			z.close()
			return err
	return z.close()

static func _zip_dir(z: ZIPPacker, from: String, prefix: String) -> Error:
	var d := DirAccess.open(from)
	if d == null:
		return DirAccess.get_open_error()
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".tmp"):
			continue
		var err := z.start_file(prefix + "/" + f)
		if err != OK:
			return err
		z.write_file(FileAccess.get_file_as_bytes(from.path_join(f)))
		z.close_file()
	for sub in d.get_directories():
		var e2 := _zip_dir(z, from.path_join(sub), prefix + "/" + sub)
		if e2 != OK:
			return e2
	return OK

## Unpacks an add-ons zip into dst (atomically: a half-finished unpack is never used).
static func extract_addons(zip_path: String, dst: String) -> Error:
	var z := ZIPReader.new()
	var err := z.open(zip_path)
	if err != OK:
		return err
	var tmp := dst + ".part"
	_remove_tree(tmp)
	for f in z.get_files():
		if f.ends_with("/") or f.contains(".."):
			continue
		var out := tmp.path_join(f)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var fa := FileAccess.open(out, FileAccess.WRITE)
		if fa == null:
			z.close()
			return FileAccess.get_open_error()
		fa.store_buffer(z.read_file(f))
		fa.close()
	z.close()
	_remove_tree(dst)
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	return DirAccess.rename_absolute(tmp, dst)

static func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)

static func manifest_path(project_dir: String) -> String:
	return project_dir.path_join(MANIFEST_FILE)

static func normalize_project_dir(path: String) -> String:
	var p := path.strip_edges().replace("\\", "/")
	if p.ends_with(MANIFEST_FILE):
		p = p.get_base_dir()
	return p.trim_suffix("/")

# --- Create --------------------------------------------------------------------------

static func default_options() -> Dictionary:
	return {
		"name": "MyRacingGame",
		"location": "",
		"template": "circuit",
		"graphicsPreset": ZinoGraphics.DEFAULT_PRESET,
		"vehicleProfile": "",          # empty = template default
		"environment": "day",
		"targetPlatforms": ["ios", "windows"],
	}

static func validate_options(opts: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var name: String = str(opts.get("name", "")).strip_edges()
	if not ZinoFormat.is_safe_name(name):
		errors.append("Project name must be 1-64 characters without / \\ : * ? \" < > | or '..'.")
	elif not name.is_valid_filename():
		errors.append("Project name is not a valid folder name.")
	var loc: String = str(opts.get("location", "")).strip_edges()
	if loc.is_empty():
		errors.append("Choose a location for the project.")
	elif not DirAccess.dir_exists_absolute(loc):
		errors.append("Location does not exist: " + loc)
	if not ZinoTemplates.PROJECTS.has(opts.get("template", "")):
		errors.append("Unknown template.")
	if not ZinoGraphics.PRESETS.has(opts.get("graphicsPreset", "")):
		errors.append("Unknown graphics preset.")
	var profile: String = opts.get("vehicleProfile", "")
	if profile != "" and not profile in ZinoEntities.PROFILES:
		errors.append("Unknown vehicle profile.")
	if not ENVIRONMENTS.has(opts.get("environment", "day")):
		errors.append("Unknown starting environment.")
	var platforms: Array = opts.get("targetPlatforms", [])
	if platforms.is_empty():
		errors.append("Select at least one target platform.")
	for p in platforms:
		if not p in TARGET_PLATFORMS:
			errors.append("Unknown target platform: " + str(p))
	if errors.is_empty():
		var dir := loc.path_join(name)
		if DirAccess.dir_exists_absolute(dir) and not _dir_is_empty(dir):
			errors.append("A non-empty folder already exists at " + dir)
	return errors

## Creates a project on disk. Returns {ok, path, error}.
static func create_project(opts: Dictionary) -> Dictionary:
	var errors := validate_options(opts)
	if not errors.is_empty():
		return {"ok": false, "path": "", "error": "\n".join(errors)}
	var name: String = str(opts["name"]).strip_edges()
	var root := str(opts["location"]).strip_edges().replace("\\", "/").path_join(name)
	var err := DirAccess.make_dir_recursive_absolute(root)
	if err != OK:
		return {"ok": false, "path": root, "error": "Cannot create folder %s (error %d)" % [root, err]}
	for f in FOLDERS:
		DirAccess.make_dir_recursive_absolute(root.path_join(f))
		if f.begins_with("Assets/") or f in ["Scripts", "Blocks", "Worlds", "Plugins"]:
			_write(root.path_join(f).path_join(".gitkeep"), "")

	var template: Dictionary = ZinoTemplates.PROJECTS[opts["template"]]
	var profile: String = opts.get("vehicleProfile", "")
	if profile == "":
		profile = template["profile"]
	var scene := ZinoTemplates.scene_for_template(opts["template"], "Main")
	_apply_vehicle_profile(scene, profile)
	_apply_environment(scene, opts.get("environment", "day"))
	if ZinoFormat.save_scene_file(root.path_join("Scenes/Main.zscene"), scene) != OK:
		return {"ok": false, "path": root, "error": "Failed to write the starting scene."}
	ZinoFormat.write_text_atomic(root.path_join("Blocks/Game Logic.zblocks"), ZinoFormat.to_json(ZinoBlockCompiler.starter_program()), false)

	var now := Time.get_datetime_string_from_system(true) + "Z"
	var manifest := {
		"format": ZinoFormat.PROJECT_FORMAT,
		"formatVersion": ZinoFormat.PROJECT_FORMAT_VERSION,
		"engine": {"name": "Zino Racing Engine", "version": ZinoFormat.ENGINE_VERSION, "godotVersion": _godot_version()},
		"project": {"name": name, "version": "0.1.0", "created": now, "modified": now,
			"bundleIdentifier": "com.example." + name.to_lower().replace(" ", "").replace("-", "")},
		"template": opts["template"],
		"gameType": template["gameType"],
		"physicsProfile": profile,
		"startingEnvironment": opts.get("environment", "day"),
		"graphics": {"gameOutput": opts["graphicsPreset"], "editorPreview": opts["graphicsPreset"]},
		"targetPlatforms": opts["targetPlatforms"],
		"ios": {"teamId": "", "devices": "both"},
		"startScene": "Scenes/Main.zscene",
		"scenes": ["Scenes/Main.zscene"],
		"modules": {"vehicles": true, "tracks": true, "race": true, "blocks": true, "openWorld": template["gameType"] == "openWorld"},
		"dependencies": {"zino_runtime": ZinoFormat.ENGINE_VERSION, "zino_bridge": ZinoFormat.ENGINE_VERSION},
		"blockScripts": ["Blocks/Game Logic.zblocks"],
		"vehicleProfiles": [profile],
		"tracks": _track_names(scene),
	}
	if ZinoFormat.write_text_atomic(manifest_path(root), ZinoFormat.to_json(manifest), false) != OK:
		return {"ok": false, "path": root, "error": "Failed to write project.zino."}
	_write(root.path_join("Config/graphics.json"), ZinoFormat.to_json({"gameOutput": opts["graphicsPreset"], "editorPreview": opts["graphicsPreset"], "presets": ZinoGraphics.ORDER}))
	_write(root.path_join("project.godot"), _godot_project_file(name))
	_write(root.path_join(".gitignore"), ".godot/\nBuilds/\nCache/\n*.tmp\n")
	_write(root.path_join("README.md"), "# %s\n\nA Zino Racing Engine project (%s). Open it from the Zino Editor.\nIt is also a Godot %s project: open the folder in Godot to use the Zino Bridge plugin.\n" % [name, template["name"], _godot_version()])
	var icon := FileAccess.get_file_as_string("res://icon.svg")
	if icon != "":
		_write(root.path_join("icon.svg"), icon)
	var copy_err := install_addons(root)
	if copy_err != "":
		return {"ok": false, "path": root, "error": copy_err}
	return {"ok": true, "path": root, "error": ""}

## Copies (or repairs) the Zino add-ons into a project. Returns "" on success or an error message.
static func install_addons(project_dir: String) -> String:
	var src := engine_addons_dir()
	for addon in ADDONS:
		var from := src.path_join(addon)
		if not DirAccess.dir_exists_absolute(from):
			return "Engine add-on missing: " + from
		var err := _copy_dir(from, project_dir.path_join("addons").path_join(addon))
		if err != OK:
			return "Failed to copy add-on %s (error %d)" % [addon, err]
	return ""

static func _apply_vehicle_profile(scene: Dictionary, profile: String) -> void:
	for e in scene["entities"]:
		if e["type"] == ZinoEntities.TYPE_VEHICLE:
			var spec := ZinoEntities.default_vehicle_spec(profile)
			spec["bodyColor"] = e["vehicle"]["spec"].get("bodyColor", spec["bodyColor"])
			e["vehicle"]["spec"] = spec

static func _apply_environment(scene: Dictionary, env: String) -> void:
	var s: Dictionary = scene["settings"]
	s["environmentPreset"] = env
	for e in scene["entities"]:
		if e["type"] == ZinoEntities.TYPE_LIGHT and e["light"]["kind"] == "directional":
			match env:
				"sunset":
					e["transform"]["rotation"] = [-9.0, -60.0, 0.0]
					e["light"]["color"] = ZinoFormat.arr_col(Color(1.0, 0.72, 0.48))
					e["light"]["intensity"] = 1.1
					s["exposure"] = 1.15
				"overcast":
					e["light"]["intensity"] = 0.55
					e["light"]["color"] = ZinoFormat.arr_col(Color(0.86, 0.9, 0.95))
					s["fogDensity"] = 0.004
					s["exposure"] = 1.25

static func _track_names(scene: Dictionary) -> Array:
	var out: Array = []
	for e in scene["entities"]:
		if e["type"] == ZinoEntities.TYPE_ROAD:
			out.append(e["name"])
	return out

static func _godot_version() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v.major, v.minor, v.patch]

static func _godot_project_file(name: String) -> String:
	return """; Generated by Zino Racing Engine. Safe to edit; Zino only rewrites it on request.

config_version=5

[application]

config/name="%s"
run/main_scene="res://addons/zino_runtime/game/zino_game.tscn"
config/features=PackedStringArray("%s", "Forward Plus")
config/icon="res://icon.svg"

[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/handheld/orientation=4

[editor_plugins]

enabled=PackedStringArray("res://addons/zino_bridge/plugin.cfg")

[physics]

common/physics_ticks_per_second=120
common/max_physics_steps_per_frame=40

[rendering]

renderer/rendering_method="forward_plus"
renderer/rendering_method.mobile="mobile"
anti_aliasing/quality/msaa_3d=2
anti_aliasing/quality/use_taa=true
lights_and_shadows/directional_shadow/size=8192
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=5
lights_and_shadows/positional_shadow/soft_shadow_filter_quality=5
textures/default_filters/anisotropic_filtering_level=4
textures/vram_compression/import_etc2_astc=true
""" % [name.replace("\"", ""), "%d.%d" % [Engine.get_version_info().major, Engine.get_version_info().minor]]

# --- Open / validate -----------------------------------------------------------------

## Opens a project folder (or project.zino path). Returns {ok, path, manifest, warnings, recovery, error}.
static func open_project(path: String) -> Dictionary:
	var dir := normalize_project_dir(path)
	var result := {"ok": false, "path": dir, "manifest": {}, "warnings": PackedStringArray(), "recovery": {}, "error": ""}
	var mf := ZinoFormat.read_json_file(manifest_path(dir))
	if not mf.ok:
		result.error = "Not a Zino project (%s)" % mf.error
		return result
	var manifest = mf.data
	if not (manifest is Dictionary) or manifest.get("format") != ZinoFormat.PROJECT_FORMAT:
		result.error = "project.zino is not a Zino project manifest."
		return result
	if int(manifest.get("formatVersion", 0)) > ZinoFormat.PROJECT_FORMAT_VERSION:
		result.error = "This project was made with a newer Zino (format v%d). Update Zino to open it." % int(manifest.get("formatVersion"))
		return result
	result.manifest = manifest
	result.warnings = validate_project(dir, manifest)
	var start: String = manifest.get("startScene", "")
	if start == "" or not FileAccess.file_exists(dir.path_join(start)):
		result.error = "Start scene is missing: " + start
		# A newer autosave can still recover the project.
		var auto := autosave_path(dir, start if start != "" else "Scenes/Main.zscene")
		if FileAccess.file_exists(auto):
			result.recovery = {"scene": start, "autosave": auto}
			result.ok = true
			result.error = ""
		return result
	result.recovery = check_recovery(dir, start)
	result.ok = true
	return result

## Non-fatal problems with a project: missing add-ons, folders, Godot project file, etc.
static func validate_project(dir: String, manifest: Dictionary) -> PackedStringArray:
	var w := PackedStringArray()
	for addon in ADDONS:
		if not DirAccess.dir_exists_absolute(dir.path_join("addons").path_join(addon)):
			w.append("Add-on '%s' is missing (Project > Repair Add-ons reinstalls it)." % addon)
	if not FileAccess.file_exists(dir.path_join("project.godot")):
		w.append("project.godot is missing; the project cannot be opened in Godot.")
	for f in ["Scenes", "Assets", "Cache"]:
		if not DirAccess.dir_exists_absolute(dir.path_join(f)):
			w.append("Folder missing: " + f)
	for s in manifest.get("scenes", []):
		if not FileAccess.file_exists(dir.path_join(s)):
			w.append("Scene listed in manifest is missing: " + str(s))
	var dep_ver: String = manifest.get("dependencies", {}).get("zino_runtime", "")
	if dep_ver != "" and dep_ver != ZinoFormat.ENGINE_VERSION:
		w.append("Project uses Zino runtime %s; this editor is %s." % [dep_ver, ZinoFormat.ENGINE_VERSION])
	return w

static func save_manifest(dir: String, manifest: Dictionary) -> Error:
	manifest["project"]["modified"] = Time.get_datetime_string_from_system(true) + "Z"
	return ZinoFormat.write_text_atomic(manifest_path(dir), ZinoFormat.to_json(manifest))

# --- Scenes, autosave, recovery ----------------------------------------------------------

static func save_scene(dir: String, rel_path: String, scene: Dictionary) -> Error:
	var err := ZinoFormat.save_scene_file(dir.path_join(rel_path), scene)
	if err == OK:
		clear_autosave(dir, rel_path)
	return err

static func autosave_path(dir: String, rel_scene: String) -> String:
	return dir.path_join("Cache/autosave").path_join(rel_scene.get_file() + ".autosave")

static func write_autosave(dir: String, rel_scene: String, scene: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(dir.path_join("Cache/autosave"))
	return ZinoFormat.write_text_atomic(autosave_path(dir, rel_scene), ZinoFormat.to_json(scene), false)

static func clear_autosave(dir: String, rel_scene: String) -> void:
	var p := autosave_path(dir, rel_scene)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

## Returns {scene, autosave} when an autosave is newer than the saved scene (unsaved work after a crash).
static func check_recovery(dir: String, rel_scene: String) -> Dictionary:
	var auto := autosave_path(dir, rel_scene)
	if not FileAccess.file_exists(auto):
		return {}
	var scene_time := FileAccess.get_modified_time(dir.path_join(rel_scene))
	if FileAccess.get_modified_time(auto) >= scene_time:
		return {"scene": rel_scene, "autosave": auto}
	return {}

# --- Helpers -------------------------------------------------------------------------

static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()

static func _dir_is_empty(path: String) -> bool:
	var d := DirAccess.open(path)
	if d == null:
		return true
	d.include_hidden = true
	return d.get_files().is_empty() and d.get_directories().is_empty()

## Recursive copy. Never overwrites files that are newer than the source (keeps user edits);
## add-on files themselves are engine-owned, so a repair replaces older copies.
static func _copy_dir(from: String, to: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(to)
	if err != OK:
		return err
	var d := DirAccess.open(from)
	if d == null:
		return DirAccess.get_open_error()
	d.include_hidden = false
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".tmp"):
			continue
		var e := DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
		if e != OK:
			return e
	for sub in d.get_directories():
		var e2 := _copy_dir(from.path_join(sub), to.path_join(sub))
		if e2 != OK:
			return e2
	return OK
