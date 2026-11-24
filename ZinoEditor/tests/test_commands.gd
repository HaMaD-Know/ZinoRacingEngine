extends ZinoTest

func _stack() -> ZinoCommandStack:
	return ZinoCommandStack.new(ZinoTemplates.racing_test_scene())

func test_create_undo_redo() -> void:
	var s := _stack()
	var n0: int = s.scene["entities"].size()
	var cube := ZinoEntities.primitive("cube")
	var ch := s.execute(ZinoSceneEdits.create(s.scene, [cube]))
	check_eq(ch["added"], [cube["id"]], "change set reports the added id")
	check_eq(s.scene["entities"].size(), n0 + 1, "entity added")
	check(s.is_dirty(), "dirty after edit")
	s.undo()
	check_eq(s.scene["entities"].size(), n0, "undo removes it")
	check(not s.is_dirty(), "clean after undoing back to saved state")
	s.redo()
	check(not ZinoFormat.find_entity(s.scene, cube["id"]).is_empty(), "redo restores it")

func test_delete_restores_original_order_and_children() -> void:
	var s := _stack()
	var parent := ZinoEntities.empty("Parent")
	var child := ZinoEntities.primitive("sphere")
	child["parentId"] = parent["id"]
	s.execute(ZinoSceneEdits.create(s.scene, [parent, child]))
	s.mark_saved()
	var order_before: Array = s.scene["entities"].map(func(e): return e["id"])
	var road_id: String = s.scene["entities"][2]["id"]
	var ch := s.execute(ZinoSceneEdits.delete(s.scene, [parent["id"], road_id]))
	check_eq(ch["removed"].size(), 3, "deleting a parent deletes its child")
	check(ZinoFormat.find_entity(s.scene, child["id"]).is_empty(), "child gone")
	s.undo()
	var order_after: Array = s.scene["entities"].map(func(e): return e["id"])
	check_eq(order_after, order_before, "undo restores the exact original order")
	check(ZinoFormat.validate_scene(s.scene).is_empty(), "scene valid after undo")

func test_modify_and_transform() -> void:
	var s := _stack()
	var id: String = s.scene["entities"][0]["id"]
	s.execute(ZinoSceneEdits.rename(s.scene, id, "Renamed"))
	check_eq(ZinoFormat.find_entity(s.scene, id)["name"], "Renamed", "rename applied")
	var t := {id: {"position": Vector3(1, 2, 3), "rotation": Vector3(0, 45, 0), "scale": Vector3(2, 2, 2)}}
	var ch := s.execute(ZinoSceneEdits.set_transforms(s.scene, t))
	check_eq(ch["modified"], [id], "transform reported as modification")
	check(ZinoFormat.v3(ZinoFormat.find_entity(s.scene, id)["transform"]["position"]).is_equal_approx(Vector3(1, 2, 3)), "position stored")
	s.undo()
	s.undo()
	check_eq(ZinoFormat.find_entity(s.scene, id)["name"], "Ground", "both edits undone")
	var noop := ZinoSceneEdits.modify(s.scene, [id], func(e): pass)
	check_eq(noop["slots"].size(), 0, "no-op edit records nothing")
	check_eq(s.execute(noop)["modified"].size(), 0, "no-op execute changes nothing")

func test_duplicate_remaps_ids_and_camera_target() -> void:
	var s := ZinoCommandStack.new(ZinoFormat.new_scene())
	var group := ZinoEntities.empty("Rig")
	var car := ZinoEntities.vehicle()
	car["parentId"] = group["id"]
	var cam := ZinoEntities.camera("Cam", "chase", car["id"])
	cam["parentId"] = group["id"]
	s.execute(ZinoSceneEdits.create(s.scene, [group, car, cam]))
	var d := ZinoSceneEdits.duplicate_entities(s.scene, [group["id"], car["id"]])
	s.execute(d.cmd)
	check_eq(d.newIds.size(), 1, "child selected with its parent is not duplicated twice")
	check_eq(s.scene["entities"].size(), 6, "three new entities")
	var new_group := ZinoFormat.find_entity(s.scene, d.newIds[0])
	check_eq(new_group["name"], "Rig 1", "duplicate gets a new name")
	var kids := ZinoFormat.children_of(s.scene, new_group["id"])
	check_eq(kids.size(), 2, "children duplicated under the new parent")
	var new_cam: Dictionary = kids.filter(func(e): return e["type"] == "camera")[0]
	var new_car: Dictionary = kids.filter(func(e): return e["type"] == "vehicle")[0]
	check_eq(new_cam["camera"]["targetId"], new_car["id"], "copied camera follows the copied car")
	check(ZinoFormat.validate_scene(s.scene).is_empty(), "scene valid")

func test_reparent_rejects_cycles() -> void:
	var s := ZinoCommandStack.new(ZinoFormat.new_scene())
	var a := ZinoEntities.empty("A")
	var b := ZinoEntities.empty("B")
	b["parentId"] = a["id"]
	s.execute(ZinoSceneEdits.create(s.scene, [a, b]))
	var cmd := ZinoSceneEdits.reparent(s.scene, [a["id"]], b["id"])
	check_eq(cmd["slots"].size(), 0, "cannot parent an entity under its own child")
	s.execute(ZinoSceneEdits.reparent(s.scene, [b["id"]], null))
	check(ZinoFormat.find_entity(s.scene, b["id"])["parentId"] == null, "unparent works")

func test_settings_command_and_history_limit() -> void:
	var s := _stack()
	var new_settings: Dictionary = s.scene["settings"].duplicate(true)
	new_settings["fogEnabled"] = false
	var ch := s.execute(ZinoSceneEdits.settings(s.scene, new_settings))
	check(ch["settingsChanged"], "settings change reported")
	check_eq(s.scene["settings"]["fogEnabled"], false, "settings applied")
	s.undo()
	check_eq(s.scene["settings"]["fogEnabled"], true, "settings undone")
	s.max_depth = 5
	for i in 12:
		s.execute(ZinoSceneEdits.create(s.scene, [ZinoEntities.empty()]))
	check_eq(s.undo_count(), 5, "history capped at max_depth")
