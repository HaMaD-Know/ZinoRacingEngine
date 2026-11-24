class_name ZinoCommandStack
extends RefCounted
## Undo/redo history for one scene document.
##
## A command is a Dictionary {label, slots, settingsBefore?, settingsAfter?}. Each slot stores deep
## copies of an entity before and after the edit (null = entity does not exist in that state) and
## its original list index, so deleted entities are restored exactly where they were. Every edit in
## the editor — create, delete, duplicate, transform, property change, reparent — uses this format,
## and the `changed` signal reports exactly which entities changed so views and the Godot bridge
## can update incrementally.

signal changed(changes: Dictionary)

var scene: Dictionary
var max_depth := 300
var _undo: Array = []
var _redo: Array = []
var _counter := 0
var _saved := 0

func _init(scene_doc: Dictionary) -> void:
	scene = scene_doc

func can_undo() -> bool: return not _undo.is_empty()
func can_redo() -> bool: return not _redo.is_empty()
func undo_label() -> String: return _undo.back()["label"] if can_undo() else ""
func redo_label() -> String: return _redo.back()["label"] if can_redo() else ""
func undo_count() -> int: return _undo.size()
func redo_count() -> int: return _redo.size()
func is_dirty() -> bool: return _counter != _saved
func mark_saved() -> void: _saved = _counter

static func new_changes() -> Dictionary:
	return {"added": [], "removed": [], "modified": [], "settingsChanged": false, "reloaded": false}

## Executes and records a command. Returns the change set (empty commands are ignored).
func execute(cmd: Dictionary) -> Dictionary:
	if cmd.get("slots", []).is_empty() and not cmd.has("settingsAfter"):
		return new_changes()
	var changes := new_changes()
	_apply(cmd, true, changes)
	_undo.append(cmd)
	if _undo.size() > max_depth:
		_undo.pop_front()
	_redo.clear()
	_counter += 1
	if _saved > _counter:
		_saved = -1   # the saved state was on the discarded redo branch
	changed.emit(changes)
	return changes

func undo() -> Dictionary:
	if not can_undo():
		return {}
	var cmd: Dictionary = _undo.pop_back()
	var changes := new_changes()
	_apply(cmd, false, changes)
	_redo.append(cmd)
	_counter -= 1
	changed.emit(changes)
	return changes

func redo() -> Dictionary:
	if not can_redo():
		return {}
	var cmd: Dictionary = _redo.pop_back()
	var changes := new_changes()
	_apply(cmd, true, changes)
	_undo.append(cmd)
	_counter += 1
	changed.emit(changes)
	return changes

## Replaces the document (open, revert, recovery). Clears history.
func reset(scene_doc: Dictionary, saved: bool = true) -> void:
	scene = scene_doc
	_undo.clear()
	_redo.clear()
	_counter = 0
	_saved = 0 if saved else -1
	var c := new_changes()
	c["reloaded"] = true
	changed.emit(c)

func _apply(cmd: Dictionary, forward: bool, changes: Dictionary) -> void:
	var list: Array = scene["entities"]
	var slots: Array = cmd.get("slots", [])
	var state_key := "after" if forward else "before"
	var other_key := "before" if forward else "after"
	# 1. Remove entities that do not exist in the target state.
	for s in slots:
		if s[state_key] == null:
			var i := ZinoFormat.index_of(scene, s["id"])
			if i >= 0:
				list.remove_at(i)
			_mark(changes, "removed", s["id"])
	# 2. Re-insert entities that were deleted (undoing a delete restores the original index).
	var inserts: Array = slots.filter(func(s): return s[state_key] != null and s[other_key] == null)
	if not forward:
		inserts.sort_custom(func(a, b): return int(a["beforeIndex"]) < int(b["beforeIndex"]))
	for s in inserts:
		var at: int = int(s["beforeIndex"]) if not forward else list.size()
		if at < 0 or at > list.size():
			at = list.size()
		list.insert(at, s[state_key].duplicate(true))
		_mark(changes, "added", s["id"])
	# 3. Replace modified entities in place.
	for s in slots:
		if s[state_key] != null and s[other_key] != null:
			var i := ZinoFormat.index_of(scene, s["id"])
			if i >= 0:
				list[i] = s[state_key].duplicate(true)
				_mark(changes, "modified", s["id"])
	var settings_key := "settingsAfter" if forward else "settingsBefore"
	if cmd.has(settings_key):
		scene["settings"] = cmd[settings_key].duplicate(true)
		changes["settingsChanged"] = true

static func _mark(changes: Dictionary, kind: String, id: String) -> void:
	for k in ["added", "removed", "modified"]:
		changes[k].erase(id)
	if kind == "modified" and changes["added"].has(id):
		return
	changes[kind].append(id)
