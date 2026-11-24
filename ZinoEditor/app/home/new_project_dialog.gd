class_name ZinoNewProjectDialog
extends Window
## New Project wizard: name, location, game type/template, graphics preset, default vehicle,
## starting environment and target platforms. Creates real project files on disk.

var app: ZinoApp
var initial_template := "circuit"
var opts := ZinoProjectService.default_options()

var _name_edit: LineEdit
var _loc_edit: LineEdit
var _errors: Label
var _create_btn: Button
var _template_desc: Label
var _path_preview: Label
var _profile_option: OptionButton

func _ready() -> void:
	title = "New Zino Project"
	theme = app.app_theme
	exclusive = true
	transient = true
	unresizable = false
	min_size = Vector2i(700, 560)
	close_requested.connect(queue_free)
	opts["template"] = initial_template
	var loc: String = app.settings.get_value("defaultLocation", "")
	if loc == "" or not DirAccess.dir_exists_absolute(loc):
		loc = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	opts["location"] = loc

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", ZinoTheme.box(ZinoTheme.PANEL, 0))
	add_child(bg)
	var root := ZinoUI.margin(ZinoUI.vbox(12), 24)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var v: VBoxContainer = root.get_child(0)

	v.add_child(ZinoUI.heading("Create a racing game project", 22))
	_name_edit = LineEdit.new()
	_name_edit.text = _unique_name(opts["location"], "MyRacingGame")
	_name_edit.text_changed.connect(func(_t): _validate())
	v.add_child(ZinoUI.row("Project name", _name_edit, 150))

	var loc_row := ZinoUI.hbox(6)
	_loc_edit = LineEdit.new()
	_loc_edit.text = opts["location"]
	_loc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loc_edit.text_changed.connect(func(_t): _validate())
	loc_row.add_child(_loc_edit)
	loc_row.add_child(ZinoUI.button("Browse…", func(): app.pick_folder("Project location", _loc_edit.text, func(p):
		_loc_edit.text = p
		_validate())))
	v.add_child(ZinoUI.row("Location", loc_row, 150))
	_path_preview = ZinoUI.dim("", 12)
	v.add_child(ZinoUI.row("", _path_preview, 150))

	var templates: Array = []
	for tid in ZinoTemplates.ORDER:
		templates.append([tid, ZinoTemplates.PROJECTS[tid]["name"]])
	v.add_child(ZinoUI.row("Game type", ZinoUI.option(templates, opts["template"], func(t):
		opts["template"] = t
		_refresh_profile_label()
		_validate()), 150))
	_template_desc = ZinoUI.dim("", 12)
	_template_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ZinoUI.row("", _template_desc, 150))

	var presets: Array = []
	for p in ZinoGraphics.ORDER:
		presets.append([p, ZinoGraphics.label(p) + ("  (default)" if p == ZinoGraphics.DEFAULT_PRESET else "")])
	v.add_child(ZinoUI.row("Graphics preset", ZinoUI.option(presets, opts["graphicsPreset"], func(p): opts["graphicsPreset"] = p), 150))

	_profile_option = ZinoUI.option([["", "Template default"]], "", func(p): opts["vehicleProfile"] = p)
	for p in ZinoEntities.PROFILES:
		_profile_option.add_item(p.capitalize() + " physics")
		_profile_option.set_item_metadata(_profile_option.item_count - 1, p)
	v.add_child(ZinoUI.row("Default vehicle", _profile_option, 150))

	var envs: Array = []
	for k in ZinoProjectService.ENVIRONMENTS:
		envs.append([k, ZinoProjectService.ENVIRONMENTS[k]])
	v.add_child(ZinoUI.row("Starting environment", ZinoUI.option(envs, "day", func(e): opts["environment"] = e), 150))

	var plat := ZinoUI.hbox(16)
	for p in [["ios", "iOS (primary)"], ["windows", "Windows"], ["android", "Android"]]:
		plat.add_child(ZinoUI.check(p[1], p[0] in opts["targetPlatforms"], func(on):
			var list: Array = opts["targetPlatforms"]
			if on and not p[0] in list:
				list.append(p[0])
			elif not on:
				list.erase(p[0])
			_validate()))
	v.add_child(ZinoUI.row("Target platforms", plat, 150))

	v.add_child(ZinoUI.spacer())
	_errors = ZinoUI.label("", 13, ZinoTheme.ERROR)
	_errors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_errors)
	var buttons := ZinoUI.hbox(10)
	buttons.add_child(ZinoUI.spacer())
	buttons.add_child(ZinoUI.button("  Cancel  ", queue_free))
	_create_btn = ZinoUI.accent_button("  Create Project  ", _create)
	buttons.add_child(_create_btn)
	v.add_child(buttons)
	_refresh_profile_label()
	_validate()
	_name_edit.grab_focus.call_deferred()

func _refresh_profile_label() -> void:
	var t: Dictionary = ZinoTemplates.PROJECTS[opts["template"]]
	_template_desc.text = "%s  Default physics profile: %s." % [t["description"], str(t["profile"]).capitalize()]

func _validate() -> bool:
	opts["name"] = _name_edit.text.strip_edges()
	opts["location"] = _loc_edit.text.strip_edges()
	_path_preview.text = "Will create: " + opts["location"].replace("\\", "/").path_join(opts["name"])
	var errs := ZinoProjectService.validate_options(opts)
	_errors.text = "\n".join(errs)
	_create_btn.disabled = not errs.is_empty()
	return errs.is_empty()

func _create() -> void:
	if not _validate():
		return
	var o := opts.duplicate(true)
	queue_free()
	app.create_project(o)

static func _unique_name(loc: String, base: String) -> String:
	var n := base
	var i := 2
	while DirAccess.dir_exists_absolute(loc.path_join(n)):
		n = "%s%d" % [base, i]
		i += 1
	return n
