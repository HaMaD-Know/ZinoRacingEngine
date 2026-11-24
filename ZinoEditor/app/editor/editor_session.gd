class_name ZinoEditorSession
extends Node
## State of one open project in the Zino Editor: the scene document, undo history, selection,
## play mode, autosave and synchronisation with the Godot editor through the Zino Bridge.

signal scene_changed(changes: Dictionary)
signal selection_changed(ids: Array)
signal state_changed()                       # dirty flag, undo/redo availability, mode
signal bridge_status_changed(status: String)

var app: ZinoApp
var project_dir := ""
var manifest: Dictionary = {}
var scene_rel := "Scenes/Main.zscene"
var stack: ZinoCommandStack
var selection: Array = []
var mode := "edit"                           # edit, play, paused
var bridge: ZinoBridgeServer
## Returns where newly added objects should be placed (the viewport supplies its focus point).
var placement_provider: Callable = func(): return Vector3.ZERO

var _from_bridge := false
var _autosave_due := 0
var _autosaved_counter := -1
var _edit_counter := 0
var _godot_pid := -1

func _ready() -> void:
	bridge = ZinoBridgeServer.new()
	bridge.name = "Bridge"
	add_child(bridge)
	bridge.status_changed.connect(_on_bridge_status)
	bridge.event_received.connect(_on_bridge_event)
	bridge.log_message.connect(func(level, msg): ZinoAppLog.write(level, "Bridge", msg))

## Loads the project scene (or its newer autosave). Returns "" on success, else an error.
func load_project(dir: String, project_manifest: Dictionary, use_autosave: bool) -> String:
	project_dir = dir
	manifest = project_manifest
	ZinoModelLoader.project_root = dir
	ZinoModelLoader.clear_cache()
	scene_rel = manifest.get("startScene", "Scenes/Main.zscene")
	var path := ZinoProjectService.autosave_path(dir, scene_rel) if use_autosave else dir.path_join(scene_rel)
	var r := ZinoFormat.load_scene_file(path)
	if not r.ok:
		return r.error
	stack = ZinoCommandStack.new(r.scene)
	stack.changed.connect(_on_stack_changed)
	if use_autosave:
		stack.reset(r.scene, false)   # recovered work counts as unsaved
		ZinoAppLog.warn("Project", "Recovered unsaved work from " + path.get_file())
	ZinoAppLog.info("Project", "Opened %s (%s, %d entities)" % [manifest.get("project", {}).get("name", "?"), scene_rel, r.scene["entities"].size()])
	_autosave_due = Time.get_ticks_msec() + _autosave_ms()
	if OS.has_feature("mobile"):
		return ""   # no Godot editor exists on iPhone/iPad: the bridge is desktop-only
	var err := bridge.start(dir)
	if err != OK:
		ZinoAppLog.error("Bridge", "Could not start the bridge (%d). Godot editor sync is unavailable." % err)
	return ""

func scene() -> Dictionary:
	return stack.scene

# --- Scenes ----------------------------------------------------------------------------

## Scene files in the project (Scenes/*.zscene), relative paths.
func list_scenes() -> Array:
	var out: Array = []
	var d := DirAccess.open(project_dir.path_join("Scenes"))
	if d:
		for f in d.get_files():
			if f.ends_with("." + ZinoFormat.SCENE_EXTENSION):
				out.append("Scenes/" + f)
	out.sort()
	return out

## Opens another scene of the project (the caller handles unsaved changes). Returns "" or an error.
func open_scene(rel: String) -> String:
	if mode != "edit":
		return "Stop the playtest first."
	var r := ZinoFormat.load_scene_file(project_dir.path_join(rel))
	if not r.ok:
		return r.error
	scene_rel = rel
	selection = []
	stack.reset(r.scene)
	selection_changed.emit(selection)
	_register_scene(rel)
	ZinoAppLog.info("Project", "Opened scene %s (%d entities)" % [rel, r.scene["entities"].size()])
	return ""

## Creates Scenes/<name>.zscene from a template ("empty", "circuit", ...) and opens it.
func new_scene(scene_name: String, template_id: String) -> String:
	if not ZinoFormat.is_safe_name(scene_name) or not scene_name.is_valid_filename():
		return "Invalid scene name."
	var rel := "Scenes/%s.%s" % [scene_name, ZinoFormat.SCENE_EXTENSION]
	if FileAccess.file_exists(project_dir.path_join(rel)):
		return "A scene named %s already exists." % scene_name
	var doc := ZinoTemplates.scene_for_template(template_id, scene_name)
	var err := ZinoFormat.save_scene_file(project_dir.path_join(rel), doc)
	if err != OK:
		return "Could not write %s (error %d)" % [rel, err]
	return open_scene(rel)

## Saves the current scene under a new name and continues editing the copy.
func save_scene_as(scene_name: String) -> String:
	if not ZinoFormat.is_safe_name(scene_name) or not scene_name.is_valid_filename():
		return "Invalid scene name."
	var rel := "Scenes/%s.%s" % [scene_name, ZinoFormat.SCENE_EXTENSION]
	if FileAccess.file_exists(project_dir.path_join(rel)):
		return "A scene named %s already exists." % scene_name
	scene()["name"] = scene_name
	var err := ZinoProjectService.save_scene(project_dir, rel, scene())
	if err != OK:
		return "Could not write %s (error %d)" % [rel, err]
	scene_rel = rel
	stack.mark_saved()
	_register_scene(rel)
	state_changed.emit()
	ZinoAppLog.info("Project", "Saved scene as " + rel)
	return ""

func set_start_scene() -> void:
	manifest["startScene"] = scene_rel
	ZinoProjectService.save_manifest(project_dir, manifest)
	ZinoAppLog.info("Project", "Start scene is now " + scene_rel)

func _register_scene(rel: String) -> void:
	var scenes: Array = manifest.get("scenes", [])
	if not rel in scenes:
		scenes.append(rel)
		manifest["scenes"] = scenes
		ZinoProjectService.save_manifest(project_dir, manifest)

func project_name() -> String:
	return str(manifest.get("project", {}).get("name", project_dir.get_file()))

func preview_preset() -> String:
	return str(manifest.get("graphics", {}).get("editorPreview", ZinoGraphics.DEFAULT_PRESET))

func game_preset() -> String:
	return str(manifest.get("graphics", {}).get("gameOutput", ZinoGraphics.DEFAULT_PRESET))

func set_preview_preset(p: String) -> void:
	manifest["graphics"]["editorPreview"] = p
	ZinoProjectService.save_manifest(project_dir, manifest)
	ZinoAppLog.info("Graphics", "Editor preview quality: %s (game output stays %s)" % [ZinoGraphics.label(p), ZinoGraphics.label(game_preset())])

# --- Editing ---------------------------------------------------------------------------

func execute(cmd: Dictionary) -> Dictionary:
	if mode != "edit":
		ZinoAppLog.warn("Editor", "Stop the playtest before editing the scene.")
		return {}
	return stack.execute(cmd)

func undo() -> void:
	if mode == "edit" and stack.can_undo():
		var label := stack.undo_label()
		stack.undo()
		ZinoAppLog.info("Edit", "Undo " + label)

func redo() -> void:
	if mode == "edit" and stack.can_redo():
		var label := stack.redo_label()
		stack.redo()
		ZinoAppLog.info("Edit", "Redo " + label)

func add_entity(kind: String) -> void:
	var e := ZinoEntities.create(kind)
	if e.is_empty():
		return
	e["name"] = ZinoFormat.unique_name(scene(), e["name"])
	if not kind in ["road", "directionalLight"]:
		var p: Vector3 = placement_provider.call()
		var cur := ZinoFormat.v3(e["transform"]["position"])
		ZinoEntities.set_pos(e, Vector3(p.x, cur.y + p.y, p.z))
	execute(ZinoSceneEdits.create(scene(), [e], "Add " + ZinoEntities.CREATABLE.get(kind, kind)))
	select([e["id"]])

func delete_selection() -> void:
	if selection.is_empty():
		return
	var ids := selection.duplicate()
	select([])
	execute(ZinoSceneEdits.delete(scene(), ids))

func duplicate_selection() -> void:
	if selection.is_empty():
		return
	var d := ZinoSceneEdits.duplicate_entities(scene(), selection)
	execute(d.cmd)
	select(d.newIds)

func modify_selected(mutate: Callable, label: String) -> void:
	execute(ZinoSceneEdits.modify(scene(), selection, mutate, label))

func select(ids: Array, additive: bool = false) -> void:
	var next: Array = selection.duplicate() if additive else []
	for id in ids:
		if additive and id in next:
			next.erase(id)
		elif not id in next and not ZinoFormat.find_entity(scene(), id).is_empty():
			next.append(id)
	if next == selection:
		return
	selection = next
	selection_changed.emit(selection)
	if not _from_bridge and bridge.is_connected_to_editor():
		bridge.send_command(ZinoProtocol.SELECT_OBJECT, {"ids": selection})

func select_all() -> void:
	select(scene()["entities"].map(func(e): return e["id"]))

func save() -> bool:
	if mode != "edit":
		ZinoAppLog.warn("Project", "Stop the playtest before saving.")
		return false
	var err := ZinoProjectService.save_scene(project_dir, scene_rel, scene())
	if err != OK:
		ZinoAppLog.error("Project", "Save failed (error %d)" % err)
		app.show_message("Save failed", "Could not write %s (error %d)." % [scene_rel, err])
		return false
	stack.mark_saved()
	ZinoProjectService.save_manifest(project_dir, manifest)
	ZinoAppLog.info("Project", "Saved %s" % scene_rel)
	state_changed.emit()
	return true

func is_dirty() -> bool:
	return stack != null and stack.is_dirty()

func set_mode(m: String) -> void:
	mode = m
	state_changed.emit()

# --- Autosave ------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if stack == null or mode != "edit":
		return
	if Time.get_ticks_msec() >= _autosave_due:
		_autosave_due = Time.get_ticks_msec() + _autosave_ms()
		if is_dirty() and _autosaved_counter != _edit_counter:
			if ZinoProjectService.write_autosave(project_dir, scene_rel, scene()) == OK:
				_autosaved_counter = _edit_counter
				ZinoAppLog.info("Project", "Autosaved")

func _autosave_ms() -> int:
	return int(app.settings.get_value("autosaveSeconds", 60)) * 1000 if app else 60000

# --- Change propagation --------------------------------------------------------------------

func _on_stack_changed(changes: Dictionary) -> void:
	_edit_counter += 1
	# Drop selected ids that no longer exist.
	var still: Array = selection.filter(func(id): return not ZinoFormat.find_entity(scene(), id).is_empty())
	if still != selection:
		selection = still
		selection_changed.emit(selection)
	scene_changed.emit(changes)
	state_changed.emit()
	if not _from_bridge:
		_sync_to_godot(changes)

func _sync_to_godot(changes: Dictionary) -> void:
	if not bridge.is_connected_to_editor():
		return
	var big: bool = changes.get("added", []).size() + changes.get("modified", []).size() + changes.get("removed", []).size() > 40
	if changes.get("reloaded", false) or changes.get("settingsChanged", false) or big:
		sync_scene_to_godot()
		return
	if not changes.get("removed", []).is_empty():
		_send(ZinoProtocol.DELETE_OBJECT, {"ids": changes["removed"]})
	for id in _parents_first(changes.get("added", [])):
		_send(ZinoProtocol.CREATE_OBJECT, {"entity": ZinoFormat.find_entity(scene(), id)})
	for id in changes.get("modified", []):
		_send(ZinoProtocol.UPDATE_OBJECT, {"entity": ZinoFormat.find_entity(scene(), id)})

func _parents_first(ids: Array) -> Array:
	var pending := ids.duplicate()
	var out: Array = []
	var guard := pending.size() + 1
	while not pending.is_empty() and guard > 0:
		guard -= 1
		for id in pending.duplicate():
			var p = ZinoFormat.find_entity(scene(), id).get("parentId")
			if p == null or not p in pending:
				out.append(id)
				pending.erase(id)
	out.append_array(pending)
	return out

func sync_scene_to_godot() -> void:
	_send(ZinoProtocol.LOAD_SCENE, {"scene": scene(), "sceneName": scene_rel.get_file().get_basename()})

func _send(cmd: String, payload: Dictionary) -> void:
	bridge.send_command(cmd, payload, func(ok, pl, err):
		if ok:
			if cmd == ZinoProtocol.LOAD_SCENE:
				ZinoAppLog.info("Bridge", "Godot editor built %s (%d entities)" % [pl.get("path", ""), int(pl.get("entityCount", 0))])
			elif cmd in [ZinoProtocol.SAVE_SCENE, ZinoProtocol.START_PLAYTEST, ZinoProtocol.STOP_PLAYTEST]:
				ZinoAppLog.info("Bridge", "%s ok %s" % [cmd, str(pl)])
		else:
			ZinoAppLog.error("Bridge", "%s failed: %s" % [cmd, err.get("message", "?")]))

func send_bridge_command(cmd: String, payload: Dictionary = {}) -> void:
	if not bridge.is_connected_to_editor():
		ZinoAppLog.warn("Bridge", "The Godot editor is not connected. Use Tools > Open in Godot Editor first.")
		return
	_send(cmd, payload)

func _on_bridge_status(status: String) -> void:
	bridge_status_changed.emit(status)
	if status == "connected":
		sync_scene_to_godot()

func _on_bridge_event(name: String, payload: Dictionary) -> void:
	_from_bridge = true
	match name:
		ZinoProtocol.EV_SELECTION_CHANGED:
			var ids: Array = payload.get("ids", []).filter(func(id): return ZinoFormat.is_valid_id(id))
			select(ids)
		ZinoProtocol.EV_TRANSFORM_CHANGED:
			var t := {}
			for it in payload.get("items", []):
				if it is Dictionary and ZinoFormat.is_valid_id(it.get("id")) and not ZinoFormat.find_entity(scene(), it["id"]).is_empty() \
						and ZinoFormat.is_finite_array(it.get("position"), 3) and ZinoFormat.is_finite_array(it.get("rotation"), 3) \
						and ZinoFormat.is_finite_array(it.get("scale"), 3):
					t[it["id"]] = {"position": ZinoFormat.v3(it.get("position")), "rotation": ZinoFormat.v3(it.get("rotation")), "scale": ZinoFormat.v3(it.get("scale"), Vector3.ONE)}
			if not t.is_empty() and mode == "edit":
				stack.execute(ZinoSceneEdits.set_transforms(scene(), t, "Move in Godot"))
		ZinoProtocol.EV_PLAYTEST_STATE:
			ZinoAppLog.info("Bridge", "Godot playtest %s" % ("started" if payload.get("playing") else "stopped"))
		ZinoProtocol.EV_LOG:
			ZinoAppLog.info("Godot", str(payload.get("message", "")))
	_from_bridge = false

# --- Godot editor process ------------------------------------------------------------------

func launch_godot_editor() -> void:
	if _godot_pid > 0 and OS.is_process_running(_godot_pid):
		ZinoAppLog.info("Bridge", "The Godot editor is already running (pid %d)." % _godot_pid)
		return
	if OS.has_feature("mobile"):
		app.show_message("Not available on iPhone/iPad", "The Godot editor runs on Windows, Mac and Linux. Open this project there to use it.")
		return
	var exe := app.settings.godot_editor_path()
	if exe == "":
		app.show_message("Godot editor not found", "Set the Godot 4.7 editor executable in Home › Settings › Godot integration.")
		return
	_godot_pid = OS.create_process(exe, ["--editor", "--path", project_dir])
	if _godot_pid <= 0:
		ZinoAppLog.error("Bridge", "Could not start the Godot editor: " + exe)
	else:
		ZinoAppLog.info("Bridge", "Started the Godot editor (pid %d). The Zino Bridge plugin connects automatically." % _godot_pid)

func shutdown() -> void:
	bridge.stop()
