class_name ZinoBuildCenter
extends HSplitContainer
## Build Center: iOS and Windows export. Validate → generate export presets → export with Godot's
## official exporter (runs on a background thread) → artifacts. iOS produces the Xcode project on
## Windows; a generated GitHub Actions workflow (or a Mac with Xcode) compiles and signs the IPA.

var session: ZinoEditorSession
var platform := "ios"
var _checks: ItemList
var _log: TextEdit
var _artifacts: ItemList
var _status: Label
var _export_btn: Button
var _thread: Thread
var _form: VBoxContainer

func setup(s: ZinoEditorSession) -> void:
	session = s
	var left := ZinoUI.vbox(8)
	left.custom_minimum_size.x = 380
	var seg := ZinoUI.hbox(0)
	for p in [["ios", "iOS (primary)"], ["windows", "Windows"]]:
		var b := ZinoUI.toggle(p[1], p[0] == platform, func(_on): set_platform(p[0]))
		b.set_meta("p", p[0])
		seg.add_child(b)
	set_meta("seg", seg)
	left.add_child(seg)
	_form = ZinoUI.vbox(6)
	left.add_child(_form)
	var actions := ZinoUI.hbox(6)
	actions.add_child(ZinoUI.button("Validate", func(): validate()))
	_export_btn = ZinoUI.accent_button("  Export  ", func(): start_export())
	actions.add_child(_export_btn)
	actions.add_child(ZinoUI.button("Open Builds", func(): OS.shell_open(session.project_dir.path_join("Builds"))))
	left.add_child(actions)
	left.add_child(ZinoUI.button("Create GitHub Actions iOS workflow", func():
		var err := ZinoBuildService.write_ci_workflow(session.project_dir, session.manifest)
		ZinoAppLog.write("info" if err == OK else "error", "Build", "Wrote .github/workflows/zino-ios.yml — push the project to GitHub, then Actions › iOS build › Run workflow (unsigned .ipa without secrets, signed with the Apple secrets)" if err == OK else "Could not write the workflow (%d)" % err)))
	var note := ZinoUI.dim("Signing certificates and profiles are never stored in the project: use Xcode on a Mac, or repository secrets for the workflow.", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(note)
	left.add_child(ZinoUI.section("Checks"))
	_checks = ItemList.new()
	_checks.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_checks)
	add_child(left)
	var right := ZinoUI.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status = ZinoUI.dim("", 13)
	right.add_child(_status)
	right.add_child(ZinoUI.section("Build log"))
	_log = TextEdit.new()
	_log.editable = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("font_size", 12)
	right.add_child(_log)
	right.add_child(ZinoUI.section("Artifacts (Builds/)"))
	_artifacts = ItemList.new()
	_artifacts.custom_minimum_size.y = 120
	_artifacts.item_activated.connect(func(i): OS.shell_show_in_file_manager(_artifacts.get_item_metadata(i)))
	right.add_child(_artifacts)
	add_child(right)
	visibility_changed.connect(func(): if visible: refresh())
	refresh()

func set_platform(p: String) -> void:
	platform = p
	for b in (get_meta("seg") as HBoxContainer).get_children():
		b.set_pressed_no_signal(b.get_meta("p") == p)
	refresh()

func refresh() -> void:
	_build_form()
	validate()
	_list_artifacts()

func _build_form() -> void:
	for c in _form.get_children():
		c.queue_free()
	var m := session.manifest
	var proj: Dictionary = m.get("project", {})
	var save := func(): ZinoProjectService.save_manifest(session.project_dir, m)
	var field := func(label: String, value: String, setter: Callable) -> LineEdit:
		var e := LineEdit.new()
		e.text = value
		e.text_submitted.connect(func(t): setter.call(t.strip_edges()); save.call(); validate())
		e.focus_exited.connect(func(): setter.call(e.text.strip_edges()); save.call())
		_form.add_child(ZinoUI.row(label, e, 130))
		return e
	field.call("App name", str(proj.get("name", "")), func(t): proj["name"] = t)
	field.call("Version", str(proj.get("version", "0.1.0")), func(t): proj["version"] = t)
	if platform == "ios":
		var ios: Dictionary = m.get("ios", {})
		m["ios"] = ios
		field.call("Bundle identifier", str(proj.get("bundleIdentifier", "")), func(t): proj["bundleIdentifier"] = t)
		field.call("Apple Team ID", str(ios.get("teamId", "")), func(t): ios["teamId"] = t.to_upper())
		_form.add_child(ZinoUI.row("Devices", ZinoUI.option([["both", "iPhone + iPad"], ["iphone", "iPhone"], ["ipad", "iPad"]], ios.get("devices", "both"), func(v):
			ios["devices"] = v
			save.call()), 130))

func validate() -> Array:
	var res := ZinoBuildService.validate(session.project_dir, session.manifest, platform)
	_checks.clear()
	for r in res:
		var icon: String = {"error": "⛔ ", "warning": "⚠ ", "ok": "✓ "}[r.level]
		_checks.add_item(icon + r.message)
		_checks.set_item_custom_fg_color(_checks.item_count - 1, {"error": ZinoTheme.ERROR, "warning": ZinoTheme.WARN, "ok": ZinoTheme.OK}[r.level])
		_checks.set_item_tooltip(_checks.item_count - 1, r.message)
	var errors := res.filter(func(r): return r.level == "error").size()
	_export_btn.disabled = errors > 0 or _thread != null
	_status.text = "%s: %s" % [ZinoBuildService.PLATFORMS[platform], "ready" if errors == 0 else "%d problem(s) to fix" % errors]
	return res

func start_export() -> void:
	if _thread != null:
		return
	if OS.has_feature("mobile"):
		session.app.show_message("Export needs a computer", "Apple doesn't allow building apps on iPhone/iPad. Press \"Create GitHub Actions iOS workflow\", put this project on GitHub, then run Actions › iOS build — or open the project in Zino on Windows/Mac.")
		return
	if not validate().filter(func(r): return r.level == "error").is_empty():
		return
	if session.is_dirty():
		session.save()
	var err := ZinoBuildService.write_export_presets(session.project_dir, session.manifest)
	if err != OK:
		ZinoAppLog.error("Build", "Could not write export_presets.cfg (%d)" % err)
		return
	_log.text = "Exporting %s… (Godot runs in the background; this can take a few minutes)\n" % ZinoBuildService.PLATFORMS[platform]
	_status.text = "Exporting…"
	_export_btn.disabled = true
	_thread = Thread.new()
	_thread.start(func(): return ZinoBuildService.export(session.project_dir, session.manifest, platform))
	ZinoAppLog.info("Build", "Export started for " + ZinoBuildService.PLATFORMS[platform])

func is_exporting() -> bool:
	return _thread != null

func _process(_delta: float) -> void:
	if _thread == null or _thread.is_alive():
		return
	var r: Dictionary = _thread.wait_to_finish()
	_thread = null
	_log.text += r.log + "\n"
	_log.scroll_vertical = 1e9
	if r.ok:
		_status.text = "✓ Export finished: " + str(r.output)
		ZinoAppLog.info("Build", "Export finished: %s%s" % [r.output, " (Xcode project — build and sign on macOS)" if platform == "ios" else ""])
	else:
		_status.text = "Export failed (exit %d) — see the log" % r.code
		ZinoAppLog.error("Build", "Export failed (exit %d)" % r.code)
	_export_btn.disabled = false
	_list_artifacts()
	set_meta("last_result", r)

func _list_artifacts() -> void:
	_artifacts.clear()
	for sub in ["iOS", "Windows"]:
		var d := DirAccess.open(session.project_dir.path_join("Builds").path_join(sub))
		if d == null:
			continue
		for f in d.get_files():
			if f.get_extension() in ["exe", "pck"]:
				_artifacts.add_item("%s/%s  (%.1f MB)" % [sub, f, FileAccess.get_size(d.get_current_dir().path_join(f)) / 1048576.0])
				_artifacts.set_item_metadata(_artifacts.item_count - 1, d.get_current_dir().path_join(f))
		for dd in d.get_directories():
			if dd.ends_with(".xcodeproj"):
				_artifacts.add_item("%s/%s  (Xcode project)" % [sub, dd])
				_artifacts.set_item_metadata(_artifacts.item_count - 1, d.get_current_dir().path_join(dd))
