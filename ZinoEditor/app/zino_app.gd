class_name ZinoApp
extends Control
## Root of the Zino Editor application: owns settings, theme, the home screen and the editor screen.

const EditorScreenScript := preload("res://app/editor/editor_screen.gd")

var settings := ZinoAppSettings.new()
var app_theme: Theme
var home: ZinoHomeScreen
var editor_screen: Control = null
var _selftest_dir := ""

func _ready() -> void:
	settings.load_settings()
	ZinoTheme.apply_appearance(str(settings.get_value("appearance", "system")))
	ZinoBuildService.godot_override = settings.godot_editor_path()
	app_theme = ZinoTheme.build()
	theme = app_theme
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = ZinoTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	get_tree().set_auto_accept_quit(false)
	get_window().title = "Zino Racing Engine"
	if OS.has_feature("mobile"):
		# Retina screens: draw the UI at the device scale so text and buttons are touch-sized.
		get_window().content_scale_factor = maxf(1.0, DisplayServer.screen_get_scale())
	else:
		get_window().min_size = Vector2i(1100, 680)
	ZinoAppLog.info("App", "Zino Racing Engine %s on Godot %s, renderer %s, GPU %s" % [
		ZinoFormat.ENGINE_VERSION, Engine.get_version_info().string,
		ProjectSettings.get_setting("rendering/renderer/rendering_method"), RenderingServer.get_video_adapter_name()])
	show_home()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zino-selftest="):
			_selftest_dir = a.substr(16)
		elif a.begins_with("--zino-open="):
			open_project.call_deferred(a.substr(12))
	if _selftest_dir != "":
		var st := preload("res://app/zino_selftest.gd").new()
		add_child(st)
		st.run(self, _selftest_dir)

## Re-applies Light/Dark/System appearance and rebuilds the visible UI.
func reapply_appearance() -> void:
	ZinoTheme.apply_appearance(str(settings.get_value("appearance", "system")))
	app_theme = ZinoTheme.build()
	theme = app_theme
	(get_node("Background") as ColorRect).color = ZinoTheme.BG
	if home:
		var page := home._page
		home.queue_free()
		home = null
		show_home()
		home.show_page(page)

func show_home() -> void:
	if editor_screen:
		editor_screen.queue_free()
		editor_screen = null
	if home == null:
		home = ZinoHomeScreen.new()
		home.app = self
		home.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(home)
	home.visible = true
	home.refresh()
	get_window().title = "Zino Racing Engine"

## Opens a project in the editor. Returns true on success.
func open_project(path: String) -> bool:
	var r := ZinoProjectService.open_project(path)
	if not r.ok:
		ZinoAppLog.error("Project", r.error)
		show_message("Cannot open project", r.error)
		return false
	if editor_screen != null:
		editor_screen.queue_free()
		editor_screen = null
	var manifest: Dictionary = r.manifest
	settings.add_recent(r.path, manifest.get("project", {}).get("name", r.path.get_file()))
	for w in r.warnings:
		ZinoAppLog.warn("Project", w)
	home.visible = false
	editor_screen = EditorScreenScript.new()
	editor_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(editor_screen)
	var ok: bool = editor_screen.open(self, r.path, manifest, r.recovery)
	if not ok:
		show_home()
		return false
	if not r.warnings.is_empty():
		show_message("Project opened with warnings", "\n".join(r.warnings))
	return true

func create_project(options: Dictionary) -> void:
	var r := ZinoProjectService.create_project(options)
	if not r.ok:
		ZinoAppLog.error("Project", r.error)
		show_message("Could not create project", r.error)
		return
	ZinoAppLog.info("Project", "Created %s" % r.path)
	settings.set_value("defaultLocation", options.get("location", ""))
	open_project(r.path)

func close_project() -> void:
	if editor_screen and editor_screen.has_method("confirm_close"):
		editor_screen.confirm_close(func(): show_home())
	else:
		show_home()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		ZinoAppLog.info("App", "Window close requested")
		if editor_screen and editor_screen.has_method("confirm_close"):
			editor_screen.confirm_close(func(): get_tree().quit())
		else:
			get_tree().quit()

# --- Dialog helpers ----------------------------------------------------------------------

func show_message(title: String, text: String) -> void:
	var d := AcceptDialog.new()
	d.title = title
	d.dialog_text = text
	d.theme = app_theme
	d.dialog_autowrap = true
	d.min_size = Vector2i(460, 0)
	add_child(d)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.popup_centered()

## Shows a dialog with custom buttons. `on_choice` receives the chosen button text, or "" on cancel.
func ask(title: String, text: String, buttons: Array, on_choice: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	d.dialog_text = text
	d.theme = app_theme
	d.dialog_autowrap = true
	d.min_size = Vector2i(480, 0)
	d.ok_button_text = buttons[0]
	d.cancel_button_text = "Cancel"
	for i in range(1, buttons.size()):
		d.add_button(buttons[i], true, buttons[i])
	add_child(d)
	var done := {"v": false}
	d.confirmed.connect(func():
		done.v = true
		d.queue_free()
		on_choice.call(buttons[0]))
	d.custom_action.connect(func(action):
		done.v = true
		d.hide()
		d.queue_free()
		on_choice.call(str(action)))
	d.canceled.connect(func():
		if not done.v:
			d.queue_free()
			on_choice.call(""))
	d.popup_centered()

## Native folder picker. on_selected receives the absolute folder path.
func pick_folder(title: String, start_dir: String, on_selected: Callable) -> void:
	var fd := FileDialog.new()
	fd.title = title
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.use_native_dialog = true
	if start_dir != "" and DirAccess.dir_exists_absolute(start_dir):
		fd.current_dir = start_dir
	add_child(fd)
	fd.dir_selected.connect(func(p):
		fd.queue_free()
		on_selected.call(p))
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered_ratio(0.6)

func pick_project_file(on_selected: Callable) -> void:
	var fd := FileDialog.new()
	fd.title = "Open Zino Project"
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = PackedStringArray(["project.zino ; Zino Project"])
	fd.use_native_dialog = true
	var start: String = settings.get_value("defaultLocation", "")
	if start != "" and DirAccess.dir_exists_absolute(start):
		fd.current_dir = start
	add_child(fd)
	fd.file_selected.connect(func(p):
		fd.queue_free()
		on_selected.call(p))
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered_ratio(0.6)
