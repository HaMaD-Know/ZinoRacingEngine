extends ZinoTest

func _opts(dir: String, template: String = "circuit") -> Dictionary:
	var o := ZinoProjectService.default_options()
	o["name"] = "TestGame"
	o["location"] = dir
	o["template"] = template
	return o

func test_create_project_writes_full_structure() -> void:
	var dir := temp_dir("proj")
	var r := ZinoProjectService.create_project(_opts(dir))
	check(r.ok, "project created: " + r.error)
	var root: String = r.path
	for f in ZinoProjectService.FOLDERS:
		check(DirAccess.dir_exists_absolute(root.path_join(f)), "folder exists: " + f)
	for f in ["project.zino", "project.godot", "Scenes/Main.zscene", "Config/graphics.json", ".gitignore", "icon.svg",
			"addons/zino_runtime/core/zino_scene_builder.gd", "addons/zino_bridge/plugin.cfg",
			"addons/zino_runtime/game/zino_game.tscn"]:
		check(FileAccess.file_exists(root.path_join(f)), "file exists: " + f)
	var m := ZinoFormat.read_json_file(root.path_join("project.zino"))
	check(m.ok, "manifest parses")
	check_eq(m.data["graphics"]["gameOutput"], "ultraMax", "default graphics preset is Ultra Max")
	check_eq(m.data["startScene"], "Scenes/Main.zscene", "start scene recorded")
	check(m.data["engine"]["godotVersion"].begins_with("4."), "Godot version recorded")
	var godot := FileAccess.get_file_as_string(root.path_join("project.godot"))
	check(godot.contains("res://addons/zino_bridge/plugin.cfg"), "bridge plugin enabled in project.godot")
	check(godot.contains("zino_game.tscn"), "game entry scene configured")
	remove_dir_recursive(dir)

func test_all_templates_create_and_open() -> void:
	var dir := temp_dir("tpl")
	for tid in ZinoTemplates.ORDER:
		var o := _opts(dir, tid)
		o["name"] = "Game_" + tid
		var r := ZinoProjectService.create_project(o)
		check(r.ok, "create %s: %s" % [tid, r.error])
		var op := ZinoProjectService.open_project(r.path)
		check(op.ok, "open %s: %s" % [tid, op.error])
		check(op.warnings.is_empty(), "no warnings for %s: %s" % [tid, "; ".join(op.warnings)])
		var sc := ZinoFormat.load_scene_file(r.path.path_join("Scenes/Main.zscene"))
		check(sc.ok, "scene loads for " + tid)
		if tid != "empty":
			var cars: Array = sc.scene["entities"].filter(func(e): return e["type"] == "vehicle")
			check_eq(cars.size(), 1, "one vehicle in " + tid)
			if cars.size() == 1:
				check_eq(cars[0]["vehicle"]["spec"]["profile"], ZinoTemplates.PROJECTS[tid]["profile"], "profile applied for " + tid)
	remove_dir_recursive(dir)

func test_option_validation() -> void:
	var dir := temp_dir("val")
	var o := _opts(dir)
	o["name"] = "bad/name"
	check(not ZinoProjectService.validate_options(o).is_empty(), "slash in name rejected")
	o = _opts(dir)
	o["location"] = dir.path_join("does_not_exist")
	check(not ZinoProjectService.validate_options(o).is_empty(), "missing location rejected")
	o = _opts(dir)
	o["targetPlatforms"] = []
	check(not ZinoProjectService.validate_options(o).is_empty(), "no platform rejected")
	o = _opts(dir)
	check(ZinoProjectService.create_project(o).ok, "first create ok")
	check(not ZinoProjectService.create_project(o).ok, "creating over a non-empty folder is refused")
	remove_dir_recursive(dir)

func test_open_rejects_non_projects_and_future_versions() -> void:
	var dir := temp_dir("bad")
	check(not ZinoProjectService.open_project(dir).ok, "empty folder is not a project")
	var f := FileAccess.open(dir.path_join("project.zino"), FileAccess.WRITE)
	f.store_string('{"format": "zino-project", "formatVersion": 999}')
	f.close()
	var r := ZinoProjectService.open_project(dir)
	check(not r.ok and r.error.contains("newer"), "future format refused with a clear message")
	remove_dir_recursive(dir)

func test_save_autosave_and_recovery() -> void:
	var dir := temp_dir("rec")
	var r := ZinoProjectService.create_project(_opts(dir))
	var root: String = r.path
	var scene: Dictionary = ZinoFormat.load_scene_file(root.path_join("Scenes/Main.zscene")).scene
	check(ZinoProjectService.check_recovery(root, "Scenes/Main.zscene").is_empty(), "no recovery after a clean create")
	scene["entities"].append(ZinoEntities.primitive("cube", "Unsaved Cube"))
	OS.delay_msec(1100)   # file times have 1 s resolution
	check_eq(ZinoProjectService.write_autosave(root, "Scenes/Main.zscene", scene), OK, "autosave written")
	var rec := ZinoProjectService.check_recovery(root, "Scenes/Main.zscene")
	check(not rec.is_empty(), "newer autosave offered for recovery")
	var op := ZinoProjectService.open_project(root)
	check(not op.recovery.is_empty(), "open_project reports the recovery")
	var recovered := ZinoFormat.load_scene_file(rec.autosave)
	check(recovered.ok and recovered.scene["entities"].any(func(e): return e["name"] == "Unsaved Cube"), "autosave holds the unsaved work")
	check_eq(ZinoProjectService.save_scene(root, "Scenes/Main.zscene", scene), OK, "save")
	check(ZinoProjectService.check_recovery(root, "Scenes/Main.zscene").is_empty(), "saving clears the autosave")
	remove_dir_recursive(dir)

func test_repair_addons() -> void:
	var dir := temp_dir("rep")
	var root: String = ZinoProjectService.create_project(_opts(dir)).path
	remove_dir_recursive(root.path_join("addons/zino_bridge"))
	var m: Dictionary = ZinoFormat.read_json_file(root.path_join("project.zino")).data
	check(not ZinoProjectService.validate_project(root, m).is_empty(), "missing add-on detected")
	check_eq(ZinoProjectService.install_addons(root), "", "repair succeeds")
	check(ZinoProjectService.validate_project(root, m).is_empty(), "project valid after repair")
	remove_dir_recursive(dir)
