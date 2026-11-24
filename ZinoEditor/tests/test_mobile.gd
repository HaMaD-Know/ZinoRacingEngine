extends ZinoTest
## iPhone/iPad build support: the engine add-ons travel inside the app as a zip and unpack correctly.

func test_engine_addons_zip_round_trip() -> void:
	var dir := temp_dir("mobile")
	var zip := dir.path_join("engine_addons.zip")
	check_eq(ZinoProjectService.pack_engine_addons(zip), OK, "add-ons packed")
	var dst := dir.path_join("engine/1.0")
	check_eq(ZinoProjectService.extract_addons(zip, dst), OK, "add-ons unpacked")
	for f in ["addons/zino_runtime/game/zino_game_context.gd", "addons/zino_bridge/plugin.cfg"]:
		var a := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path("res://").path_join(f))
		var b := FileAccess.get_file_as_bytes(dst.path_join(f))
		check(a.size() > 0 and a == b, "%s unpacked byte-for-byte" % f)
	check(not DirAccess.dir_exists_absolute(dst + ".part"), "no half-finished folder left behind")
	# Unpacking again replaces the old copy cleanly.
	check_eq(ZinoProjectService.extract_addons(zip, dst), OK, "re-unpack works")
	remove_dir_recursive(dir)

func test_ios_presets_for_the_editor() -> void:
	var cfg := ConfigFile.new()
	check_eq(cfg.load("res://export_presets.cfg"), OK, "editor export presets load")
	var ios := ""
	for s in cfg.get_sections():
		if cfg.get_value(s, "platform", "") == "iOS":
			ios = s
	check(ios != "", "editor has an iOS preset")
	if ios == "":
		return
	check(str(cfg.get_value(ios, "include_filter", "")).contains("engine_addons.zip"), "iOS build bundles the add-ons")
	check_eq(str(cfg.get_value(ios + ".options", "application/app_store_team_id", "x")), "", "no Team ID committed (the workflow fills it in)")
	check(cfg.get_value(ios + ".options", "application/export_project_only", false), "exports an Xcode project")
	check(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false), "mobile texture compression on")
