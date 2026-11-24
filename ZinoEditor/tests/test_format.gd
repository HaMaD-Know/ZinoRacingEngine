extends ZinoTest

func test_ids_are_unique_and_valid() -> void:
	var seen := {}
	for i in 2000:
		var id := ZinoFormat.new_id()
		check(ZinoFormat.is_valid_id(id), "generated id valid: " + id)
		check(not seen.has(id), "id unique")
		seen[id] = true
	check(not ZinoFormat.is_valid_id("bad id"), "space rejected")
	check(not ZinoFormat.is_valid_id("../x"), "path rejected")
	check(not ZinoFormat.is_valid_id(""), "empty rejected")

func test_every_template_scene_is_valid_and_round_trips() -> void:
	for tid in ZinoTemplates.ORDER:
		var scene := ZinoTemplates.scene_for_template(tid)
		var problems := ZinoFormat.validate_scene(scene)
		check(problems.is_empty(), "template %s valid: %s" % [tid, "; ".join(problems)])
		var text := ZinoFormat.to_json(scene)
		var parsed := ZinoFormat.parse_json(text)
		check(parsed.ok, "template %s parses" % tid)
		check(ZinoFormat.validate_scene(parsed.data).is_empty(), "template %s valid after round trip" % tid)
		check_eq(parsed.data["entities"].size(), scene["entities"].size(), "entity count preserved for " + tid)

func test_racing_test_scene_contents() -> void:
	var scene := ZinoTemplates.racing_test_scene()
	var counts := {}
	for e in scene["entities"]:
		counts[e["type"]] = counts.get(e["type"], 0) + 1
	check_eq(counts.get("vehicle", 0), 1, "one vehicle")
	check_eq(counts.get("road", 0), 1, "one road")
	check_eq(counts.get("camera", 0), 1, "one camera")
	check_eq(counts.get("light", 0), 1, "one sun")
	check_eq(counts.get("startFinish", 0), 1, "start/finish line")
	check_eq(counts.get("checkpoint", 0), 3, "three checkpoints")
	var car: Dictionary = scene["entities"].filter(func(e): return e["type"] == "vehicle")[0]
	check_eq(car["vehicle"]["spec"]["wheels"].size(), 4, "four wheels")
	var cam: Dictionary = scene["entities"].filter(func(e): return e["type"] == "camera")[0]
	check_eq(cam["camera"]["targetId"], car["id"], "chase camera targets the car")

func test_validation_catches_bad_data() -> void:
	var scene := ZinoTemplates.empty()
	var e: Dictionary = scene["entities"][0]
	e["transform"]["position"] = [0, "x", 0]
	check(not ZinoFormat.validate_scene(scene).is_empty(), "non-numeric position rejected")
	scene = ZinoTemplates.empty()
	scene["entities"].append(scene["entities"][0].duplicate(true))
	check(not ZinoFormat.validate_scene(scene).is_empty(), "duplicate id rejected")
	scene = ZinoTemplates.empty()
	scene["entities"][0]["parentId"] = "e_missing"
	check(not ZinoFormat.validate_scene(scene).is_empty(), "missing parent rejected")
	scene = ZinoTemplates.empty()
	var a: Dictionary = scene["entities"][0]
	var b: Dictionary = scene["entities"][1]
	a["parentId"] = b["id"]
	b["parentId"] = a["id"]
	check(not ZinoFormat.validate_scene(scene).is_empty(), "parent cycle rejected")
	check(not ZinoFormat.validate_scene({"format": "zino-scene", "formatVersion": 99, "entities": []}).is_empty(), "future version rejected")
	check(not ZinoFormat.parse_json("{not json").ok, "broken JSON reported")

func test_atomic_write_keeps_backup() -> void:
	var dir := temp_dir("atomic")
	var path := dir.path_join("a.zscene")
	check_eq(ZinoFormat.save_scene_file(path, ZinoTemplates.empty("First")), OK, "first save")
	check_eq(ZinoFormat.save_scene_file(path, ZinoTemplates.empty("Second")), OK, "second save")
	var cur := ZinoFormat.load_scene_file(path)
	check(cur.ok and cur.scene["name"] == "Second", "current file is the latest")
	var bak := ZinoFormat.load_scene_file(path + ".bak")
	check(bak.ok and bak.scene["name"] == "First", "backup holds the previous version")
	check(not FileAccess.file_exists(path + ".tmp"), "no temp file left behind")
	var bad := ZinoTemplates.empty()
	bad["entities"][0]["id"] = "bad id"
	check_eq(ZinoFormat.save_scene_file(path, bad), ERR_INVALID_DATA, "invalid scene not written")
	remove_dir_recursive(dir)

func test_transform_round_trip() -> void:
	var e := ZinoEntities.primitive("cube")
	ZinoEntities.set_pos(e, Vector3(1, 2, 3))
	ZinoEntities.set_rot(e, Vector3(10, 45, -20))
	ZinoEntities.set_scale(e, Vector3(2, 3, 4))
	var n := Node3D.new()
	n.transform = ZinoFormat.transform_from_entity(e)
	check(n.position.is_equal_approx(Vector3(1, 2, 3)), "position")
	check(n.rotation_degrees.distance_to(Vector3(10, 45, -20)) < 0.01, "rotation " + str(n.rotation_degrees))
	check(n.scale.distance_to(Vector3(2, 3, 4)) < 0.001, "scale " + str(n.scale))
	n.free()
