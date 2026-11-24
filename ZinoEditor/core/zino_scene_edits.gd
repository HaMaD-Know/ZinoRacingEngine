class_name ZinoSceneEdits
extends RefCounted
## Turns editor intents into undoable commands for ZinoCommandStack. Never mutates the scene itself.

static func _slot(id: String, before, before_index: int, after) -> Dictionary:
	return {
		"id": id,
		"before": before.duplicate(true) if before != null else null,
		"after": after.duplicate(true) if after != null else null,
		"beforeIndex": before_index,
	}

static func create(scene: Dictionary, entities: Array, label: String = "Create") -> Dictionary:
	var slots: Array = []
	for e in entities:
		assert(ZinoFormat.is_valid_id(e.get("id")), "invalid id")
		assert(ZinoFormat.find_entity(scene, e["id"]).is_empty(), "id already exists")
		slots.append(_slot(e["id"], null, -1, e))
	return {"label": label, "slots": slots}

## Deletes the entities and all their descendants.
static func delete(scene: Dictionary, ids: Array, label: String = "Delete") -> Dictionary:
	var slots: Array = []
	var seen := {}
	for id in ids:
		for e in ZinoFormat.with_descendants(scene, id):
			if seen.has(e["id"]):
				continue
			seen[e["id"]] = true
			slots.append(_slot(e["id"], e, ZinoFormat.index_of(scene, e["id"]), null))
	return {"label": label, "slots": slots}

## Applies `mutate(entity_copy)` to copies of the entities. The callable must not change ids.
static func modify(scene: Dictionary, ids: Array, mutate: Callable, label: String = "Edit") -> Dictionary:
	var slots: Array = []
	var seen := {}
	for id in ids:
		if seen.has(id):
			continue
		seen[id] = true
		var e := ZinoFormat.find_entity(scene, id)
		if e.is_empty():
			continue
		var after: Dictionary = e.duplicate(true)
		mutate.call(after)
		after["id"] = id
		if after == e:
			continue   # no-op edits are not recorded
		slots.append(_slot(id, e, ZinoFormat.index_of(scene, id), after))
	return {"label": label, "slots": slots}

## transforms: id -> {position: Vector3, rotation: Vector3 (degrees), scale: Vector3}
static func set_transforms(scene: Dictionary, transforms: Dictionary, label: String = "Transform") -> Dictionary:
	var slots: Array = []
	for id in transforms:
		var e := ZinoFormat.find_entity(scene, id)
		if e.is_empty():
			continue
		var t: Dictionary = transforms[id]
		var after: Dictionary = e.duplicate(true)
		after["transform"] = ZinoFormat.transform_dict(t["position"], t["rotation"], t["scale"])
		if after["transform"] == e["transform"]:
			continue
		slots.append(_slot(id, e, ZinoFormat.index_of(scene, id), after))
	return {"label": label, "slots": slots}

## Duplicates entities with their descendants. Returns {cmd, newIds} (new root ids).
static func duplicate_entities(scene: Dictionary, ids: Array, offset: Vector3 = Vector3(2, 0, 0)) -> Dictionary:
	var slots: Array = []
	var new_ids: Array = []
	var id_set := {}
	for id in ids:
		id_set[id] = true
	var roots: Array = ids.filter(func(id):
		if ZinoFormat.find_entity(scene, id).is_empty():
			return false
		for other in ids:
			if other != id and ZinoFormat.is_descendant_of(scene, id, other):
				return false
		return true)
	var used := {}
	for e in scene["entities"]:
		used[e["name"]] = true
	for root_id in roots:
		var family := ZinoFormat.with_descendants(scene, root_id)
		var map := {}
		for e in family:
			map[e["id"]] = ZinoFormat.new_id()
		for e in family:
			var copy: Dictionary = e.duplicate(true)
			copy["id"] = map[e["id"]]
			if e["id"] == root_id:
				var p := ZinoFormat.v3(copy["transform"]["position"]) + offset
				copy["transform"]["position"] = ZinoFormat.arr3(p)
				copy["name"] = _next_name(used, e["name"])
				new_ids.append(copy["id"])
			else:
				copy["parentId"] = map[e["parentId"]]
			var cam = copy.get("camera")
			if cam is Dictionary and cam.get("targetId") != null and map.has(cam["targetId"]):
				cam["targetId"] = map[cam["targetId"]]
			slots.append(_slot(copy["id"], null, -1, copy))
	return {"cmd": {"label": "Duplicate", "slots": slots}, "newIds": new_ids}

static func reparent(scene: Dictionary, ids: Array, new_parent_id) -> Dictionary:
	var valid: Array = ids.filter(func(id):
		if id == new_parent_id:
			return false
		return new_parent_id == null or not ZinoFormat.is_descendant_of(scene, new_parent_id, id))
	return modify(scene, valid, func(e): e["parentId"] = new_parent_id, "Reparent")

static func rename(scene: Dictionary, id: String, new_name: String) -> Dictionary:
	return modify(scene, [id], func(e): e["name"] = new_name, "Rename")

static func settings(scene: Dictionary, new_settings: Dictionary, label: String = "Scene Settings") -> Dictionary:
	if new_settings == scene.get("settings", {}):
		return {"label": label, "slots": []}
	return {"label": label, "slots": [], "settingsBefore": scene.get("settings", {}).duplicate(true), "settingsAfter": new_settings.duplicate(true)}

static func _next_name(used: Dictionary, base: String) -> String:
	var stem := base
	var n := 1
	var parts := base.rsplit(" ", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		stem = parts[0]
		n = int(parts[1]) + 1
	var candidate := "%s %d" % [stem, n]
	while used.has(candidate):
		n += 1
		candidate = "%s %d" % [stem, n]
	used[candidate] = true
	return candidate
