class_name ZinoHomeScreen
extends HBoxContainer
## Launcher: Home, Projects, Templates, Documentation and Settings pages.

var app: ZinoApp
var _content: MarginContainer
var _nav_buttons := {}
var _page := "home"

const PAGES := [["home", "Home"], ["projects", "Projects"], ["templates", "Templates"], ["store", "Asset Store"], ["docs", "Documentation"], ["settings", "Settings"]]

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	add_child(_build_sidebar())
	_content = MarginContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		_content.add_theme_constant_override("margin_" + side, 40)
	_content.add_theme_constant_override("margin_top", 32)
	_content.add_theme_constant_override("margin_bottom", 24)
	add_child(_content)
	show_page("home")

func refresh() -> void:
	if _content:
		show_page(_page)

func show_page(page: String) -> void:
	_page = page
	for k in _nav_buttons:
		_nav_buttons[k].button_pressed = k == page
	for c in _content.get_children():
		c.queue_free()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body: Control
	match page:
		"projects": body = _projects_page()
		"templates": body = _templates_page()
		"docs": body = _docs_page()
		"store":
			for c in _content.get_children():
				c.queue_free()
			var st := ZinoAssetStore.new()
			st.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_content.add_child(st)
			st.setup(null)
			scroll.free()
			return
		"settings": body = _settings_page()
		_: body = _home_page()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_content.add_child(scroll)

# --- Sidebar ---------------------------------------------------------------------------

func _build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 240
	panel.add_theme_stylebox_override("panel", ZinoTheme.box(ZinoTheme.BG_2, 0, Color.TRANSPARENT, 0, 18))
	var v := ZinoUI.vbox(6)
	panel.add_child(v)
	var logo := ZinoUI.hbox(10)
	var mark := TextureRect.new()
	mark.texture = load("res://icon.svg")
	mark.custom_minimum_size = Vector2(40, 40)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.add_child(mark)
	var names := ZinoUI.vbox(0)
	names.add_child(ZinoUI.label("Zino", 22, ZinoTheme.TEXT))
	names.add_child(ZinoUI.label("Racing Engine", 12, ZinoTheme.TEXT_DIM))
	logo.add_child(names)
	v.add_child(logo)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	v.add_child(gap)
	for p in PAGES:
		var b := Button.new()
		b.text = "   " + p[1]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 40
		b.add_theme_stylebox_override("normal", ZinoTheme.box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 10))
		b.add_theme_stylebox_override("hover", ZinoTheme.box(ZinoTheme.PANEL_2, 6, Color.TRANSPARENT, 0, 10))
		b.add_theme_stylebox_override("pressed", ZinoTheme.box(Color(ZinoTheme.TEXT, 0.1), 6, Color.TRANSPARENT, 0, 10))
		b.add_theme_color_override("font_pressed_color", ZinoTheme.TEXT)
		b.add_theme_color_override("font_hover_pressed_color", ZinoTheme.TEXT)
		b.pressed.connect(show_page.bind(p[0]))
		_nav_buttons[p[0]] = b
		v.add_child(b)
	v.add_child(ZinoUI.spacer())
	var ver := Engine.get_version_info()
	v.add_child(ZinoUI.dim("Zino %s" % ZinoFormat.ENGINE_VERSION, 12))
	v.add_child(ZinoUI.dim("Godot %d.%d.%d · %s" % [ver.major, ver.minor, ver.patch, RenderingServer.get_video_adapter_name()], 11))
	return panel

# --- Pages ------------------------------------------------------------------------------

func _home_page() -> Control:
	var v := ZinoUI.vbox(22)
	var hero := ZinoUI.card(ZinoTheme.PANEL, 14, 28)
	var hv := ZinoUI.vbox(10)
	hv.add_child(ZinoUI.label("Make a racing game in minutes.", 34, ZinoTheme.TEXT))
	hv.add_child(ZinoUI.dim("Start simple with Make a Game, then go as far as you want: every professional tool is one click away in Advanced Mode.", 15))
	var hb := ZinoUI.hbox(12)
	var make := ZinoUI.accent_button("  ✨ Make a Game  ", open_make_game)
	make.tooltip_text = "Answer 5 quick questions and get a complete, playable racing game."
	hb.add_child(make)
	hb.add_child(ZinoUI.button("  New Project (advanced)…  ", func(): open_wizard("circuit")))
	hb.add_child(ZinoUI.button("  Open Project…  ", _open_existing))
	hv.add_child(hb)
	hero.add_child(hv)
	v.add_child(hero)

	v.add_child(ZinoUI.heading("Recent Projects", 18))
	v.add_child(_recent_list(5))

	v.add_child(ZinoUI.heading("Start from a template", 18))
	v.add_child(_template_grid(4))

	v.add_child(ZinoUI.heading("Learn", 18))
	var learn := ZinoUI.hbox(12)
	for doc in [["Getting Started", "GETTING_STARTED.md"], ["Architecture", "ARCHITECTURE.md"], ["Roadmap", "ROADMAP.md"]]:
		learn.add_child(ZinoUI.button("  %s  " % doc[0], func(): _open_doc(doc[1])))
	v.add_child(learn)
	return v

func _projects_page() -> Control:
	var v := ZinoUI.vbox(16)
	var top := ZinoUI.hbox(12)
	top.add_child(ZinoUI.heading("Projects", 26))
	top.add_child(ZinoUI.spacer())
	top.add_child(ZinoUI.button("  Open Project…  ", _open_existing))
	top.add_child(ZinoUI.accent_button("  New Project  ", func(): open_wizard("circuit")))
	v.add_child(top)
	v.add_child(_recent_list(ZinoAppSettings.MAX_RECENT))
	return v

func _templates_page() -> Control:
	var v := ZinoUI.vbox(16)
	v.add_child(ZinoUI.heading("Racing Game Templates", 26))
	v.add_child(ZinoUI.dim("Every template uses the same vehicle, track and race framework with a different starting scene and physics profile.", 14))
	v.add_child(_template_grid(4))
	return v

func _docs_page() -> Control:
	var v := ZinoUI.vbox(14)
	v.add_child(ZinoUI.heading("Documentation", 26))
	var files := _doc_files()
	if files.is_empty():
		v.add_child(ZinoUI.dim("No documentation found next to the engine."))
		return v
	var h := ZinoUI.hbox(16)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(240, 560)
	for f in files:
		list.add_item(f.get_file().get_basename().replace("_", " ").capitalize())
		list.set_item_metadata(list.item_count - 1, f)
	h.add_child(list)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(500, 560)
	text.selection_enabled = true
	text.add_theme_stylebox_override("normal", ZinoTheme.box(ZinoTheme.BG_2, 8, ZinoTheme.BORDER, 1, 16))
	h.add_child(text)
	list.item_selected.connect(func(i):
		text.text = ZinoMarkdown.to_bbcode(FileAccess.get_file_as_string(list.get_item_metadata(i))))
	var want := get_meta("open_doc", "") as String
	var idx := 0
	for i in files.size():
		if files[i].get_file() == want:
			idx = i
	list.select(idx)
	list.item_selected.emit(idx)
	v.add_child(h)
	return v

func _settings_page() -> Control:
	var s := app.settings
	var v := ZinoUI.vbox(14)
	v.add_child(ZinoUI.heading("Settings", 26))
	var c := ZinoUI.card()
	var cv := ZinoUI.vbox(10)
	c.add_child(cv)
	cv.add_child(ZinoUI.section("Appearance"))
	cv.add_child(ZinoUI.row("Appearance", ZinoUI.option([["system", "Use system setting"], ["light", "Light"], ["dark", "Dark"]], s.get_value("appearance", "system"), func(v):
		s.set_value("appearance", v)
		app.reapply_appearance.call_deferred()), 200))
	cv.add_child(ZinoUI.section("Editor"))
	cv.add_child(ZinoUI.row("Autosave every", ZinoUI.spin(10, 3600, 5, float(s.get_value("autosaveSeconds", 60)), func(x): s.set_value("autosaveSeconds", int(x)), " s"), 200))
	cv.add_child(ZinoUI.row("Lightweight mode", ZinoUI.check("Render the viewport at half resolution while editing (saves GPU on laptops)", s.get_value("lightweightMode", false), func(b): s.set_value("lightweightMode", b)), 200))
	cv.add_child(ZinoUI.row("Move snap", ZinoUI.spin(0.01, 100, 0.01, float(s.get_value("translateSnap", 0.5)), func(x): s.set_value("translateSnap", x), " m"), 200))
	cv.add_child(ZinoUI.row("Rotate snap", ZinoUI.spin(1, 90, 1, float(s.get_value("rotateSnap", 15.0)), func(x): s.set_value("rotateSnap", x), "°"), 200))
	cv.add_child(ZinoUI.row("Scale snap", ZinoUI.spin(0.01, 10, 0.01, float(s.get_value("scaleSnap", 0.1)), func(x): s.set_value("scaleSnap", x)), 200))
	cv.add_child(ZinoUI.section("Godot integration"))
	var path_edit := LineEdit.new()
	path_edit.placeholder_text = OS.get_executable_path() + "  (default: the Godot running Zino)"
	path_edit.text = s.get_value("godotEditorPath", "")
	path_edit.text_submitted.connect(func(t): s.set_value("godotEditorPath", t.strip_edges()))
	path_edit.focus_exited.connect(func(): s.set_value("godotEditorPath", path_edit.text.strip_edges()))
	cv.add_child(ZinoUI.row("Godot editor executable", path_edit, 200))
	cv.add_child(ZinoUI.row("On project open", ZinoUI.check("Launch the Godot editor and connect the Zino Bridge automatically", s.get_value("autoLaunchGodot", false), func(b): s.set_value("autoLaunchGodot", b)), 200))
	cv.add_child(ZinoUI.section("Storage"))
	cv.add_child(ZinoUI.row("Settings & logs", ZinoUI.dim(ProjectSettings.globalize_path("user://")), 200))
	cv.add_child(ZinoUI.button("Open logs folder", func(): OS.shell_open(ProjectSettings.globalize_path("user://logs"))))
	v.add_child(c)
	return v

# --- Pieces -------------------------------------------------------------------------------

func _recent_list(limit: int) -> Control:
	var v := ZinoUI.vbox(8)
	var recents: Array = app.settings.recent_projects()
	if recents.is_empty():
		v.add_child(ZinoUI.dim("No recent projects yet. Create one from a template below."))
		return v
	for r in recents.slice(0, limit):
		var path: String = r.get("path", "")
		var exists := FileAccess.file_exists(ZinoProjectService.manifest_path(path))
		var card := ZinoUI.card(ZinoTheme.PANEL, 8, 12)
		var h := ZinoUI.hbox(12)
		var info := ZinoUI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(ZinoUI.label(str(r.get("name", path.get_file())), 16, ZinoTheme.TEXT if exists else ZinoTheme.TEXT_DIM))
		info.add_child(ZinoUI.dim(path + ("" if exists else "   (missing)"), 12))
		h.add_child(info)
		h.add_child(ZinoUI.dim(str(r.get("lastOpened", "")), 12))
		if exists:
			h.add_child(ZinoUI.button("Show folder", func(): OS.shell_show_in_file_manager(path)))
			h.add_child(ZinoUI.accent_button("Open", func(): app.open_project(path)))
		h.add_child(ZinoUI.button("Remove", func():
			app.settings.remove_recent(path)
			refresh(), "Remove from this list (files are not deleted)"))
		card.add_child(h)
		v.add_child(card)
	return v

func _template_grid(columns: int) -> Control:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 14)
	var accents := ["green", "blue", "orange", "teal", "purple", "red", "pink", "gray"].map(func(n): return ZinoTheme.tint(n))
	for i in ZinoTemplates.ORDER.size():
		var tid: String = ZinoTemplates.ORDER[i]
		var t: Dictionary = ZinoTemplates.PROJECTS[tid]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(230, 120)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", ZinoTheme.box(ZinoTheme.PANEL, 10, ZinoTheme.BORDER, 1, 14))
		b.add_theme_stylebox_override("hover", ZinoTheme.box(ZinoTheme.PANEL_2, 10, accents[i], 1, 14))
		b.add_theme_stylebox_override("pressed", ZinoTheme.box(ZinoTheme.PANEL_2, 10, accents[i], 2, 14))
		var inner := ZinoUI.vbox(6)
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 16
		inner.offset_top = 14
		inner.offset_right = -16
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var stripe := ColorRect.new()
		stripe.color = accents[i]
		stripe.custom_minimum_size = Vector2(36, 4)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stripe.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		inner.add_child(stripe)
		var title := ZinoUI.label(t["name"], 16, ZinoTheme.TEXT)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(title)
		var desc := ZinoUI.dim(t["description"], 12)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(desc)
		b.add_child(inner)
		b.pressed.connect(func(): open_wizard(tid))
		g.add_child(b)
	return g

func open_make_game() -> void:
	var w := ZinoMakeGameWizard.new()
	w.app = app
	add_child(w)
	w.popup_centered(Vector2i(1000, 700))

func open_wizard(template_id: String) -> void:
	var w := ZinoNewProjectDialog.new()
	w.app = app
	w.initial_template = template_id
	add_child(w)
	w.popup_centered(Vector2i(760, 640))

func _open_existing() -> void:
	app.pick_project_file(func(p): app.open_project(p))

func _open_doc(file: String) -> void:
	set_meta("open_doc", file)
	show_page("docs")

## Markdown docs shipped with the engine: the repository root (status docs) and docs/.
static func _doc_files() -> Array:
	var roots: Array = []
	var repo := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	if FileAccess.file_exists(repo.path_join("ARCHITECTURE.md")):
		roots = [repo, repo.path_join("docs")]
	else:
		var inst := OS.get_executable_path().get_base_dir().path_join("docs")
		roots = [inst]
	var out: Array = []
	for r in roots:
		var d := DirAccess.open(r)
		if d == null:
			continue
		var names: Array = Array(d.get_files()).filter(func(f): return f.ends_with(".md"))
		names.sort()
		for f in names:
			out.append(r.path_join(f))
	return out
