extends ZinoTest
## Build Center end-to-end: validation, export presets, real Windows export (and running the exported
## game), real iOS Xcode-project export, CI workflow. Slow (~2–4 min) because it runs the real exporter.

func test_validation_rules() -> void:
	var dir := temp_dir("buildval")
	var o := ZinoProjectService.default_options()
	o["name"] = "ValGame"
	o["location"] = dir
	var root: String = ZinoProjectService.create_project(o).path
	var m: Dictionary = ZinoFormat.read_json_file(root.path_join("project.zino")).data
	var res := ZinoBuildService.validate(root, m, "ios")
	check(res.any(func(r): return r.level == "error" and r.message.contains("Team ID")), "missing Team ID blocks iOS")
	check(res.any(func(r): return r.level == "warning" and r.message.contains("com.example")), "placeholder bundle id warned")
	m.ios.teamId = "ABCDE12345"
	m.project.bundleIdentifier = "com.zino.valgame"
	res = ZinoBuildService.validate(root, m, "ios")
	check(res.filter(func(r): return r.level == "error").is_empty(), "valid iOS config passes: %s" % str(res.filter(func(r): return r.level == "error")))
	m.project.bundleIdentifier = "not a bundle"
	check(ZinoBuildService.validate(root, m, "ios").any(func(r): return r.level == "error" and r.message.contains("Bundle")), "bad bundle id rejected")
	var scene: Dictionary = ZinoFormat.load_scene_file(root.path_join("Scenes/Main.zscene")).scene
	scene.settings["skyHdri"] = "Assets/Environment/missing.hdr"
	ZinoFormat.save_scene_file(root.path_join("Scenes/Main.zscene"), scene)
	check(ZinoBuildService.missing_references(root, m).has("Assets/Environment/missing.hdr"), "missing asset reference detected")
	remove_dir_recursive(dir)

func test_real_exports() -> void:
	var dir := temp_dir("build")
	var o := ZinoProjectService.default_options()
	o["name"] = "ExportGame"
	o["location"] = dir
	var root: String = ZinoProjectService.create_project(o).path
	var m: Dictionary = ZinoFormat.read_json_file(root.path_join("project.zino")).data
	m.ios.teamId = "ABCDE12345"
	m.project.bundleIdentifier = "com.zino.exportgame"
	ZinoProjectService.save_manifest(root, m)
	check_eq(ZinoBuildService.write_export_presets(root, m), OK, "export presets written")
	var presets := FileAccess.get_file_as_string(root.path_join("export_presets.cfg"))
	check(presets.contains("com.zino.exportgame") and presets.contains("*.zscene"), "presets contain bundle id and Zino data filters")
	check(not presets.to_lower().contains("password") and not presets.contains(".p12"), "no signing secrets in presets")
	check(FileAccess.file_exists(root.path_join("Config/icon_1024.png")), "1024 icon generated")

	var t0 := Time.get_ticks_msec()
	var win := ZinoBuildService.export(root, m, "windows")
	print("    windows export: ok=%s in %.0f s → %s" % [win.ok, (Time.get_ticks_msec() - t0) / 1000.0, win.output])
	check(win.ok and FileAccess.file_exists(win.output), "Windows game exported")
	if win.ok:
		var out: Array = []
		var code := OS.execute(win.output, ["--headless", "--quit-after", "240"], out, true)
		var text := "\n".join(out)
		check(code == 0 and not text.contains("Zino could not start") and not text.contains("Cannot load"), "exported game starts, loads its scene and runs (exit %d)" % code)
		check(not text.contains("Zino blocks:"), "exported game compiled its block programs")

	t0 = Time.get_ticks_msec()
	var ios := ZinoBuildService.export(root, m, "ios")
	print("    iOS export: ok=%s in %.0f s" % [ios.ok, (Time.get_ticks_msec() - t0) / 1000.0])
	check(ios.ok and DirAccess.dir_exists_absolute(root.path_join("Builds/iOS/ExportGame.xcodeproj")), "iOS Xcode project exported on Windows")
	check_eq(ZinoBuildService.write_ci_workflow(root, m), OK, "CI workflow written")
	var yml := FileAccess.get_file_as_string(root.path_join(".github/workflows/zino-ios.yml"))
	check(yml.contains("secrets.IOS_CERTIFICATE_P12_BASE64") and yml.contains("APP: ExportGame") and not yml.contains("%s"), "workflow references secrets, not credentials")
	check(yml.contains("CODE_SIGNING_ALLOWED=NO") and yml.contains("PROVISIONING_PROFILE_SPECIFIER") and yml.contains("app_store_team_id"), "workflow builds unsigned without secrets and signed with them")
	remove_dir_recursive(dir)
