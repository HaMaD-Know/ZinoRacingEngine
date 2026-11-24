@tool
extends RefCounted
## Executes validated Zino Bridge commands inside the Godot editor.
## Requests are validated by ZinoProtocol.validate_request before they reach this class.

const WORLDS_DIR := "res://Worlds"

var plugin: EditorPlugin
var scene: Dictionary = {}
var scene_path := ""
var builder: ZinoSceneBuilder
var _known := {}          # id -> transform dict last sent/applied, for change detection
var _applying := false
## Selection most recently set by Zino; the matching (deferred) selection_changed signal is not echoed back.
var last_zino_selection: Array = []

func _init(owner_plugin: EditorPlugin) -> void:
	plugin = owner_plugin

func is_applying() -> bool:
	return _applying

func handle(cmd: String, p: Dictionary) -> Dictionary:
	_applying = true
	var r: Dictionary
	match cmd:
		ZinoProtocol.PING: r = _ok({"pong": true, "time": Time.get_unix_time_from_system()})
		ZinoProtocol.GET_INFO: r = _info()
		ZinoProtocol.LOAD_SCENE: r = _load_scene(p)
		ZinoProtocol.CREATE_OBJECT: r = _create(p["entity"])
		ZinoProtocol.UPDATE_OBJECT: r = _update(p["entity"])
		ZinoProtocol.DELETE_OBJECT: r = _delete(p["ids"])
		ZinoProtocol.SELECT_OBJECT: r = _select(p["ids"])
		ZinoProtocol.MOVE_OBJECT: r = _transform([{"id": p["id"], "position": p["position"]}])
		ZinoProtocol.ROTATE_OBJECT: r = _transform([{"id": p["id"], "rotation": p["rotation"]}])
		ZinoProtocol.SCALE_OBJECT: r = _transform([{"id": p["id"], "scale": p["scale"]}])
		ZinoProtocol.SET_TRANSFORM: r = _transform(p["items"])
		ZinoProtocol.ASSIGN_MATERIAL: r = _assign_material(p["id"], p["material"])
		ZinoProtocol.IMPORT_ASSET: r = _import_asset(p["path"])
		ZinoProtocol.SAVE_SCENE: r = _save()
		ZinoProtocol.START_PLAYTEST: r = _start_playtest()
		ZinoProtocol.STOP_PLAYTEST: r = _stop_playtest()
		_: r = _err(ZinoProtocol.ERR_UNKNOWN_COMMAND, cmd)
	_applying = false
	return r

# --- Commands -------------------------------------------------------------------------

func _info() -> Dictionary:
	_bind()
	var root := EditorInterface.get_edited_scene_root()
	return _ok({
		"godotVersion": Engine.get_version_info().string,
		"projectPath": ProjectSettings.globalize_path("res://"),
		"editedScene": root.scene_file_path if root else "",
		"zinoScene": scene_path,
		"entityCount": scene.get("entities", []).size(),
		"playing": EditorInterface.is_playing_scene(),
	})

## Builds the Zino scene as a real Godot scene (res://Worlds/<name>.tscn) and opens it in the editor.
func _load_scene(p: Dictionary) -> Dictionary:
	var doc: Dictionary = p["scene"].duplicate(true)
	var scene_name: String = str(p.get("sceneName", doc.get("name", "Main")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORLDS_DIR))
	var path := WORLDS_DIR.path_join(scene_name + ".tscn")
	var root := Node3D.new()
	root.name = scene_name.validate_node_name()
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_AUTHOR, _game_preset())
	b.owner_root = root
	b.build(doc)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		return _err(ZinoProtocol.ERR_FAILED, "pack failed (%d)" % err)
	err = ResourceSaver.save(packed, path)
	if err != OK:
		return _err(ZinoProtocol.ERR_FAILED, "could not save %s (%d)" % [path, err])
	EditorInterface.get_resource_filesystem().update_file(path)
	if path in EditorInterface.get_open_scenes():
		EditorInterface.reload_scene_from_path(path)
	else:
		EditorInterface.open_scene_from_path(path)
	scene = doc
	scene_path = path
	if not _bind():
		return _err(ZinoProtocol.ERR_FAILED, "scene saved to %s but could not be opened in the editor" % path)
	return _ok({"path": path, "entityCount": doc["entities"].size(), "nodeCount": builder.nodes.size()})

func _create(e: Dictionary) -> Dictionary:
	if not _bind():
		return _not_open()
	if not ZinoFormat.find_entity(scene, e["id"]).is_empty():
		return _err(ZinoProtocol.ERR_INVALID_PAYLOAD, "entity already exists: " + e["id"])
	if e.get("parentId") != null and ZinoFormat.find_entity(scene, e["parentId"]).is_empty():
		return _err(ZinoProtocol.ERR_NOT_FOUND, "parent not found: " + str(e["parentId"]))
	scene["entities"].append(e.duplicate(true))
	builder.apply_changes(scene, {"added": [e["id"]]})
	_remember(e["id"])
	_mark_unsaved()
	return _ok({"id": e["id"], "node": str(builder.node_for(e["id"]).name)})

func _update(e: Dictionary) -> Dictionary:
	if not _bind():
		return _not_open()
	var i := ZinoFormat.index_of(scene, e["id"])
	if i < 0:
		return _err(ZinoProtocol.ERR_NOT_FOUND, "entity not found: " + e["id"])
	scene["entities"][i] = e.duplicate(true)
	builder.apply_changes(scene, {"modified": [e["id"]]})
	_remember(e["id"])
	_mark_unsaved()
	return _ok({"id": e["id"]})

func _delete(ids: Array) -> Dictionary:
	if not _bind():
		return _not_open()
	var all: Array = []
	for id in ids:
		for e in ZinoFormat.with_descendants(scene, id):
			if not e["id"] in all:
				all.append(e["id"])
	if all.is_empty():
		return _err(ZinoProtocol.ERR_NOT_FOUND, "no such entities")
	for id in all:
		var i := ZinoFormat.index_of(scene, id)
		if i >= 0:
			scene["entities"].remove_at(i)
		_known.erase(id)
	builder.apply_changes(scene, {"removed": all})
	_mark_unsaved()
	return _ok({"deleted": all})

func _select(ids: Array) -> Dictionary:
	if not _bind():
		return _not_open()
	var sel := EditorInterface.get_selection()
	sel.clear()
	last_zino_selection = ids.duplicate()
	var found := 0
	for id in ids:
		var n := builder.node_for(id)
		if n:
			sel.add_node(n)
			found += 1
	return _ok({"selected": found})

func _transform(items: Array) -> Dictionary:
	if not _bind():
		return _not_open()
	var applied := 0
	for it in items:
		var n := builder.node_for(it["id"])
		var i := ZinoFormat.index_of(scene, it["id"])
		if n == null or i < 0:
			return _err(ZinoProtocol.ERR_NOT_FOUND, "entity not found: " + str(it["id"]))
		var t: Dictionary = scene["entities"][i]["transform"]
		for key in ["position", "rotation", "scale"]:
			if it.has(key):
				t[key] = ZinoFormat.arr3(ZinoFormat.v3(it[key]))
		n.transform = ZinoFormat.transform_from_entity(scene["entities"][i])
		_remember(it["id"])
		applied += 1
	_mark_unsaved()
	return _ok({"applied": applied})

func _assign_material(id: String, material: Dictionary) -> Dictionary:
	if not _bind():
		return _not_open()
	var i := ZinoFormat.index_of(scene, id)
	if i < 0:
		return _err(ZinoProtocol.ERR_NOT_FOUND, "entity not found: " + id)
	var e: Dictionary = scene["entities"][i]
	if not (e.get("mesh") is Dictionary):
		return _err(ZinoProtocol.ERR_INVALID_PAYLOAD, "entity has no mesh")
	var m: Dictionary = e["mesh"].get("material", {})
	for k in material:
		if k in ["preset", "color", "metallic", "roughness"]:
			m[k] = material[k]
	e["mesh"]["material"] = m
	builder.apply_changes(scene, {"modified": [id]})
	_mark_unsaved()
	return _ok({"id": id})

func _import_asset(rel: String) -> Dictionary:
	var res_path := "res://" + rel.replace("\\", "/")
	if not FileAccess.file_exists(res_path):
		return _err(ZinoProtocol.ERR_NOT_FOUND, "file not found: " + rel)
	var fs := EditorInterface.get_resource_filesystem()
	fs.update_file(res_path)
	fs.reimport_files(PackedStringArray([res_path]))
	return _ok({"imported": res_path, "type": fs.get_file_type(res_path)})

func _save() -> Dictionary:
	if not _bind():
		return _not_open()
	var err := EditorInterface.save_scene()
	if err != OK:
		return _err(ZinoProtocol.ERR_FAILED, "save failed (%d)" % err)
	return _ok({"path": scene_path})

func _start_playtest() -> Dictionary:
	if not _bind():
		return _not_open()
	EditorInterface.play_current_scene()
	return _ok({"playing": true, "scene": scene_path})

func _stop_playtest() -> Dictionary:
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
	return _ok({"playing": false})

# --- Change detection (Godot editor -> Zino) -----------------------------------------

## Returns transform changes the user made in the Godot editor since the last call.
func collect_transform_changes() -> Array:
	var out: Array = []
	if builder == null or _applying or not _bind():
		return out
	for id in builder.nodes.keys():
		var n := builder.node_for(id)
		if n == null:
			continue
		var t := ZinoFormat.node_transform_dict(n)
		if _known.get(id) != t:
			_known[id] = t
			var i := ZinoFormat.index_of(scene, id)
			if i >= 0:
				scene["entities"][i]["transform"] = t.duplicate(true)
			var item := t.duplicate(true)
			item["id"] = id
			out.append(item)
	return out

# --- Helpers --------------------------------------------------------------------------------

## Makes sure the builder is bound to the edited scene that holds the Zino world.
func _bind() -> bool:
	if scene_path == "":
		return false
	var root := EditorInterface.get_edited_scene_root() as Node3D
	if (root == null or root.scene_file_path != scene_path) and scene_path in EditorInterface.get_open_scenes():
		# The editor may open another scene after start-up (e.g. the main scene); switch back to ours.
		EditorInterface.open_scene_from_path(scene_path)
		root = EditorInterface.get_edited_scene_root() as Node3D
	if root == null or root.scene_file_path != scene_path:
		return false
	if builder != null and builder.root == root:
		return true
	builder = ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_AUTHOR, _game_preset())
	builder.owner_root = root
	builder.scene = scene
	builder.nodes = {}
	_scan(root)
	_known.clear()
	for id in builder.nodes:
		_remember(id)
	return true

func _scan(n: Node) -> void:
	for c in n.get_children():
		if c.has_meta(ZinoSceneBuilder.META_ID):
			builder.nodes[c.get_meta(ZinoSceneBuilder.META_ID)] = c
		_scan(c)

func _remember(id: String) -> void:
	var n := builder.node_for(id)
	if n:
		_known[id] = ZinoFormat.node_transform_dict(n)

func _mark_unsaved() -> void:
	EditorInterface.mark_scene_as_unsaved()

func _game_preset() -> String:
	var r := ZinoFormat.read_json_file("res://project.zino")
	if r.ok and r.data is Dictionary:
		return str(r.data.get("graphics", {}).get("gameOutput", ZinoGraphics.DEFAULT_PRESET))
	return ZinoGraphics.DEFAULT_PRESET

func _ok(payload: Dictionary = {}) -> Dictionary:
	return {"ok": true, "payload": payload}

func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

func _not_open() -> Dictionary:
	return _err(ZinoProtocol.ERR_FAILED, "no Zino scene is open in the Godot editor; send LOAD_SCENE first")
