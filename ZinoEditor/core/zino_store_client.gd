class_name ZinoStoreClient
extends Node
## Asset Store backend: Poly Haven's public CC0 catalogue (textures, HDRIs, models).
## Lists assets, caches thumbnails, and downloads files into a project's Assets/ folder with MD5
## verification. Nothing personal is sent; requests carry only a generic app user-agent.

signal catalog_loaded(kind: String, items: Array)
signal catalog_failed(kind: String, message: String)
signal thumbnail_ready(id: String, texture: Texture2D)
signal download_progress(id: String, done: int, total: int)
signal download_finished(id: String, result: Dictionary)   # {ok, files:[rel], main:rel, error}

const API := "https://api.polyhaven.com"
const THUMBS := "https://cdn.polyhaven.com/asset_img/thumbs/%s.png?width=256&height=256"
const HEADERS := ["User-Agent: ZinoRacingEngine/0.1 (asset store)"]
const KINDS := {"textures": "Textures", "hdris": "HDRIs", "models": "Models"}
const MAX_THUMBS := 6

var _thumb_queue: Array = []
var _thumb_active := 0
var cache_dir := "user://store_cache"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))

# --- Catalogue --------------------------------------------------------------------------------------

func load_catalog(kind: String) -> void:
	var cached := cache_dir.path_join("catalog_%s.json" % kind)
	_get_json("%s/assets?t=%s" % [API, kind], func(ok, data, err):
		if not ok:
			# Offline: fall back to the last catalogue we saw.
			var r := ZinoFormat.read_json_file(cached)
			if r.ok and r.data is Dictionary:
				catalog_loaded.emit(kind, _items(kind, r.data))
			else:
				catalog_failed.emit(kind, err)
			return
		ZinoFormat.write_text_atomic(ProjectSettings.globalize_path(cached), JSON.stringify(data), false)
		catalog_loaded.emit(kind, _items(kind, data)))

static func _items(kind: String, data: Dictionary) -> Array:
	var out: Array = []
	for id in data:
		var a: Dictionary = data[id]
		out.append({"id": id, "kind": kind, "name": a.get("name", id), "categories": a.get("categories", []),
			"tags": a.get("tags", []), "authors": a.get("authors", {}).keys(), "downloads": int(a.get("download_count", 0))})
	out.sort_custom(func(x, y): return x.downloads > y.downloads)
	return out

static func filter(items: Array, query: String, category: String) -> Array:
	var q := query.strip_edges().to_lower()
	return items.filter(func(it):
		if category != "" and not category in it.categories:
			return false
		if q == "":
			return true
		return str(it.name).to_lower().contains(q) or str(it.id).contains(q) or it.tags.any(func(t): return str(t).to_lower().contains(q)) or it.categories.any(func(c): return str(c).to_lower().contains(q)))

static func categories(items: Array) -> Array:
	var counts := {}
	for it in items:
		for c in it.categories:
			counts[c] = counts.get(c, 0) + 1
	var cats := counts.keys()
	cats.sort_custom(func(a, b): return counts[a] > counts[b])
	return cats.slice(0, 30)

# --- Thumbnails -------------------------------------------------------------------------------------

func request_thumbnail(id: String) -> void:
	var path := cache_dir.path_join(id.validate_filename() + ".png")
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img:
			thumbnail_ready.emit(id, ImageTexture.create_from_image(img))
			return
	_thumb_queue.append(id)
	_pump_thumbs()

func _pump_thumbs() -> void:
	while _thumb_active < MAX_THUMBS and not _thumb_queue.is_empty():
		var id: String = _thumb_queue.pop_front()
		_thumb_active += 1
		var req := HTTPRequest.new()
		add_child(req)
		req.request_completed.connect(func(result, code, _h, body):
			req.queue_free()
			_thumb_active -= 1
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				var img := Image.new()
				if img.load_png_from_buffer(body) == OK or img.load_webp_from_buffer(body) == OK or img.load_jpg_from_buffer(body) == OK:
					img.save_png(ProjectSettings.globalize_path(cache_dir.path_join(id.validate_filename() + ".png")))
					thumbnail_ready.emit(id, ImageTexture.create_from_image(img))
			_pump_thumbs())
		req.request(THUMBS % id.uri_encode(), HEADERS)

# --- Downloads --------------------------------------------------------------------------------------

## Downloads an asset into project_dir/Assets/... resolution: "1k", "2k", "4k".
func download(item: Dictionary, project_dir: String, resolution: String = "1k") -> void:
	var id: String = item.id
	_get_json("%s/files/%s" % [API, id.uri_encode()], func(ok, files, err):
		if not ok:
			download_finished.emit(id, {"ok": false, "error": err})
			return
		var plan := plan_files(item.kind, id, files, resolution)
		if plan.is_empty():
			download_finished.emit(id, {"ok": false, "error": "no %s files available for %s" % [resolution, id]})
			return
		_download_plan(id, item, plan, project_dir, 0, []))

## Which files to fetch for an asset: [{url, rel, md5}] relative to the project.
static func plan_files(kind: String, id: String, files: Dictionary, res: String) -> Array:
	var safe_id := id.validate_filename()
	var plan: Array = []
	match kind:
		"textures":
			for map in [["Diffuse", "diff"], ["nor_gl", "nor_gl"], ["Rough", "rough"]]:
				var f = files.get(map[0], {}).get(res, {}).get("jpg")
				if f is Dictionary:
					plan.append({"url": f.url, "rel": "Assets/Textures/%s/%s" % [safe_id, str(f.url).get_file()], "md5": f.get("md5", ""), "role": map[1]})
		"hdris":
			var f = files.get("hdri", {}).get(res, {}).get("hdr")
			if f is Dictionary:
				plan.append({"url": f.url, "rel": "Assets/Environment/%s" % str(f.url).get_file(), "md5": f.get("md5", ""), "role": "hdri"})
		"models":
			var g = files.get("gltf", {}).get(res, {}).get("gltf")
			if g is Dictionary:
				plan.append({"url": g.url, "rel": "Assets/Environment/%s/%s" % [safe_id, str(g.url).get_file()], "md5": g.get("md5", ""), "role": "model"})
				for inc in g.get("include", {}):
					var f2: Dictionary = g.include[inc]
					if str(inc).contains(".."):
						continue
					plan.append({"url": f2.url, "rel": "Assets/Environment/%s/%s" % [safe_id, inc], "md5": f2.get("md5", ""), "role": "include"})
	return plan

func _download_plan(id: String, item: Dictionary, plan: Array, project_dir: String, index: int, done: Array) -> void:
	if index >= plan.size():
		var main := ""
		for p in plan:
			if p.role in ["diff", "hdri", "model"]:
				main = p.rel
				break
		var index_info := {"source": "https://polyhaven.com/a/" + id, "type": item.kind, "license": "CC0 1.0 (Poly Haven)",
			"author": ", ".join(item.get("authors", [])), "files": done, "imported": Time.get_datetime_string_from_system(true) + "Z"}
		ZinoAssetImporter._record(project_dir, main, index_info)
		download_finished.emit(id, {"ok": true, "files": done, "main": main, "maps": _maps(plan)})
		return
	var f: Dictionary = plan[index]
	var dest := project_dir.path_join(f.rel)
	if FileAccess.file_exists(dest):
		# Never overwrite: keep what is there (same asset, maybe edited by the user).
		done.append(f.rel)
		download_progress.emit(id, index + 1, plan.size())
		_download_plan(id, item, plan, project_dir, index + 1, done)
		return
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var req := HTTPRequest.new()
	add_child(req)
	req.download_file = dest + ".part"
	req.request_completed.connect(func(result, code, _h, _b):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			DirAccess.remove_absolute(dest + ".part")
			download_finished.emit(id, {"ok": false, "error": "download failed (%d / HTTP %d): %s" % [result, code, f.url]})
			return
		if f.md5 != "" and FileAccess.get_md5(dest + ".part") != f.md5:
			DirAccess.remove_absolute(dest + ".part")
			download_finished.emit(id, {"ok": false, "error": "checksum mismatch for " + str(f.rel).get_file()})
			return
		DirAccess.rename_absolute(dest + ".part", dest)
		done.append(f.rel)
		download_progress.emit(id, index + 1, plan.size())
		_download_plan(id, item, plan, project_dir, index + 1, done))
	req.request(f.url, HEADERS)

static func _maps(plan: Array) -> Dictionary:
	var out := {}
	for p in plan:
		out[p.role] = p.rel
	return out

func _get_json(url: String, cb: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 30.0
	req.request_completed.connect(func(result, code, _h, body):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			cb.call(false, {}, "network error (%d / HTTP %d) — check your internet connection" % [result, code])
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary:
			cb.call(true, data, "")
		else:
			cb.call(false, {}, "unexpected response"))
	var err := req.request(url, HEADERS)
	if err != OK:
		req.queue_free()
		cb.call(false, {}, "request failed (%d)" % err)
