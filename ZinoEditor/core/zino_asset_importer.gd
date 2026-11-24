class_name ZinoAssetImporter
extends RefCounted
## Copies external files into a project's Assets/<category>/ folder. Never overwrites: a name clash
## gets a numbered name. .gltf dependencies (buffers, textures) are copied alongside. Every import is
## recorded in Assets/asset_index.json with its source, date, size and licence.

const CATEGORIES := ["Vehicles", "Tracks", "Materials", "Textures", "Audio", "Environment", "UI"]
const TYPES := {
	"glb": "model", "gltf": "model", "fbx": "model", "obj": "model",
	"png": "texture", "jpg": "texture", "jpeg": "texture", "webp": "texture", "hdr": "hdri", "exr": "hdri",
	"wav": "audio", "ogg": "audio", "mp3": "audio",
	"ttf": "font", "otf": "font",
}
const INDEX := "Assets/asset_index.json"

static func asset_type(path: String) -> String:
	return TYPES.get(path.get_extension().to_lower(), "")

static func category_for(path: String) -> String:
	match asset_type(path):
		"model": return "Vehicles"
		"texture": return "Textures"
		"hdri": return "Environment"
		"audio": return "Audio"
		"font": return "UI"
	return "Environment"

## Returns {rel, type} or {error}.
static func import_file(project_dir: String, source: String, category: String = "", meta: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(source):
		return {"error": "File not found: " + source}
	var t := asset_type(source)
	if t == "":
		return {"error": "Unsupported file type: ." + source.get_extension()}
	if category == "" or not category in CATEGORIES:
		category = category_for(source)
	var dest_dir := project_dir.path_join("Assets").path_join(category)
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var file_name := _unique(dest_dir, source.get_file().validate_filename())
	var err := DirAccess.copy_absolute(source, dest_dir.path_join(file_name))
	if err != OK:
		return {"error": "Copy failed (error %d)" % err}
	var copied: Array = [file_name]
	if source.get_extension().to_lower() == "gltf":
		copied.append_array(_copy_gltf_dependencies(source, dest_dir))
	var rel := "Assets/%s/%s" % [category, file_name]
	_record(project_dir, rel, {"source": meta.get("source", source), "type": t, "license": meta.get("license", "user supplied"),
		"author": meta.get("author", ""), "files": copied, "bytes": FileAccess.get_size(dest_dir.path_join(file_name)),
		"imported": Time.get_datetime_string_from_system(true) + "Z"})
	return {"rel": rel, "type": t}

static func _unique(dir: String, file_name: String) -> String:
	if not FileAccess.file_exists(dir.path_join(file_name)):
		return file_name
	var base := file_name.get_basename()
	var ext := file_name.get_extension()
	var i := 2
	while FileAccess.file_exists(dir.path_join("%s_%d.%s" % [base, i, ext])):
		i += 1
	return "%s_%d.%s" % [base, i, ext]

static func _copy_gltf_dependencies(source: String, dest_dir: String) -> Array:
	var out: Array = []
	var r := ZinoFormat.read_json_file(source)
	if not r.ok or not (r.data is Dictionary):
		return out
	for section in ["buffers", "images"]:
		for item in r.data.get(section, []):
			var uri := str(item.get("uri", "")) if item is Dictionary else ""
			if uri == "" or uri.begins_with("data:") or uri.contains("..") or uri.contains(":"):
				continue
			var src := source.get_base_dir().path_join(uri.uri_decode())
			var dst := dest_dir.path_join(uri.uri_decode())
			if FileAccess.file_exists(src) and not FileAccess.file_exists(dst):
				DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
				if DirAccess.copy_absolute(src, dst) == OK:
					out.append(uri)
	return out

static func _record(project_dir: String, rel: String, info: Dictionary) -> void:
	var path := project_dir.path_join(INDEX)
	var r := ZinoFormat.read_json_file(path)
	var index: Dictionary = r.data if r.ok and r.data is Dictionary else {"format": "zino-asset-index", "assets": {}}
	index["assets"][rel] = info
	ZinoFormat.write_text_atomic(path, ZinoFormat.to_json(index), false)

static func read_index(project_dir: String) -> Dictionary:
	var r := ZinoFormat.read_json_file(project_dir.path_join(INDEX))
	return r.data.get("assets", {}) if r.ok and r.data is Dictionary else {}
