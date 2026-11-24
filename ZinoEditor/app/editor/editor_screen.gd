extends VBoxContainer
## The main editor window: menu bar, toolbar, hierarchy / viewport / inspector, bottom panel and
## status bar. Every menu entry and button here is wired to a working action.

var app: ZinoApp
var session: ZinoEditorSession
var viewport_panel: ZinoViewportPanel
var hierarchy: ZinoHierarchyPanel
var inspector: ZinoInspectorPanel
var content: ZinoContentPanel

var _left: Control
var _right: Control
var _bottom: Control
var _tool_buttons := {}
var _undo_btn: Button
var _redo_btn: Button
var _save_btn: Button
var _play_btn: Button
var _pause_btn: Button
var _stop_btn: Button
var _status_left: Label
var _status_bridge: Label
var _bridge_pill: PanelContainer
var _menus := {}
var _ws_area: VBoxContainer
var _workspaces := {}
var _ws_buttons := {}
var block_studio: ZinoBlockStudio
var vehicle_studio: ZinoVehicleStudio
var track_studio: ZinoTrackStudio
var world_studio: ZinoWorldStudio
var store: ZinoAssetStore
var ui_studio: ZinoUIStudio
var audio_studio: ZinoAudioStudio
var build_center: ZinoBuildCenter
var _right_tabs: TabContainer
var game_panel: ZinoGamePanel
var simple := true
var coach: ZinoCoach

## Simple mode shows fewer, friendlier tools; Advanced mode shows everything. Same project data.
const SIMPLE_WORKSPACES := [["Scene", "Build"], ["Track", "Track"], ["Vehicle", "Car"], ["Blocks", "Logic"], ["Store", "Store"], ["Build", "Publish"]]
const ADVANCED_WORKSPACES := [["Scene", "Scene"], ["Track", "Track"], ["World", "World"], ["Blocks", "Blocks"], ["Vehicle", "Vehicle"], ["UI", "UI"], ["Audio", "Audio"], ["Store", "Store"], ["Build", "Build"]]

# Menu item ids
enum { M_NEW, M_OPEN, M_SAVE, M_CLOSE, M_QUIT,
	M_UNDO, M_REDO, M_DUP, M_DEL, M_SELALL, M_DESEL, M_RENAME,
	M_PERSP, M_TOP, M_FRONT, M_SIDE, M_FRAME, M_GRID,
	M_PSETTINGS, M_VALIDATE, M_REPAIR, M_FOLDER,
	M_PLAY, M_PAUSE, M_STOP, M_PLAY_GODOT, M_STOP_GODOT,
	M_GODOT, M_SYNC, M_SAVE_GODOT, M_RESTART_BRIDGE,
	M_WIN_LEFT, M_WIN_RIGHT, M_WIN_BOTTOM, M_WIN_RESET,
	M_DOCS, M_ABOUT, M_LOGS,
	M_NEW_SCENE, M_OPEN_SCENE, M_SAVE_AS, M_START_SCENE, M_STATS, M_BENCH, M_ADVANCED, M_COACH,
	M_ADD = 100, M_RACE = 200 }

func open(zino_app: ZinoApp, dir: String, manifest: Dictionary, recovery: Dictionary) -> bool:
	app = zino_app
	session = ZinoEditorSession.new()
	session.app = app
	add_child(session)
	if not recovery.is_empty():
		app.ask("Recover unsaved work?",
			"Zino found autosaved changes newer than %s (the editor may have closed unexpectedly).\nRecover them?" % recovery.get("scene", "the scene"),
			["Recover", "Discard Autosave"], func(choice):
				if choice == "Discard Autosave":
					ZinoProjectService.clear_autosave(dir, recovery.get("scene", ""))
				_finish_open(dir, manifest, choice == "Recover"))
		return true
	return _finish_open(dir, manifest, false)

func _finish_open(dir: String, manifest: Dictionary, use_autosave: bool) -> bool:
	var err := session.load_project(dir, manifest, use_autosave)
	if err != "":
		ZinoAppLog.error("Project", err)
		app.show_message("Cannot open scene", err)
		app.show_home.call_deferred()
		return false
	_build()
	get_window().title = "%s — Zino Racing Engine" % session.project_name()
	if app.settings.get_value("autoLaunchGodot", false):
		session.launch_godot_editor()
	return true

func _build() -> void:
	simple = app.settings.get_value("simpleMode", true)
	add_theme_constant_override("separation", 0)
	add_child(_build_menu_bar())
	add_child(_build_toolbar())

	var vsplit := VSplitContainer.new()
	vsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vsplit)
	_ws_area = VBoxContainer.new()
	_ws_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vsplit.add_child(_ws_area)
	var hsplit := HSplitContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ws_area.add_child(hsplit)
	_workspaces["Scene"] = hsplit

	viewport_panel = ZinoViewportPanel.new()
	viewport_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_panel.custom_minimum_size = Vector2(400, 300)

	# Left: hierarchy + add palette
	var left_tabs := TabContainer.new()
	left_tabs.custom_minimum_size.x = 280
	hierarchy = ZinoHierarchyPanel.new()
	hierarchy.name = "Scene"
	left_tabs.add_child(hierarchy)
	left_tabs.add_child(_build_add_palette())
	_left = left_tabs
	hsplit.add_child(left_tabs)

	var center_right := HSplitContainer.new()
	center_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(center_right)
	center_right.add_child(viewport_panel)
	var right_tabs := TabContainer.new()
	right_tabs.custom_minimum_size.x = 340
	game_panel = ZinoGamePanel.new()
	game_panel.name = "Game"
	right_tabs.add_child(game_panel)
	inspector = ZinoInspectorPanel.new()
	inspector.name = "Inspector"
	right_tabs.add_child(inspector)
	track_studio = ZinoTrackStudio.new()
	track_studio.name = "Track"
	right_tabs.add_child(track_studio)
	world_studio = ZinoWorldStudio.new()
	world_studio.name = "World"
	right_tabs.add_child(world_studio)
	_right_tabs = right_tabs
	_right = right_tabs
	center_right.add_child(right_tabs)

	var bottom_tabs := TabContainer.new()
	bottom_tabs.custom_minimum_size.y = 190
	var console := ZinoConsolePanel.new()
	console.name = "Console"
	bottom_tabs.add_child(console)
	var bridge_log := ZinoConsolePanel.new()
	bridge_log.name = "Bridge Log"
	bridge_log.channel_filter = "Bridge"
	bottom_tabs.add_child(bridge_log)
	content = ZinoContentPanel.new()
	content.name = "Content Browser"
	bottom_tabs.add_child(content)
	_bottom = bottom_tabs
	vsplit.add_child(bottom_tabs)
	vsplit.split_offset = 0

	add_child(_build_status_bar())

	viewport_panel.setup(session)
	hierarchy.setup(session, viewport_panel)
	inspector.setup(session)
	game_panel.setup(session, _play)
	track_studio.setup(session, viewport_panel)
	world_studio.setup(session, viewport_panel)
	content.setup(session)
	content.scene_open_requested.connect(open_scene_confirmed)
	block_studio = ZinoBlockStudio.new()
	block_studio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	block_studio.visible = false
	_ws_area.add_child(block_studio)
	block_studio.setup(session)
	_workspaces["Blocks"] = block_studio
	vehicle_studio = ZinoVehicleStudio.new()
	vehicle_studio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vehicle_studio.visible = false
	_ws_area.add_child(vehicle_studio)
	vehicle_studio.setup(session)
	_workspaces["Vehicle"] = vehicle_studio
	ui_studio = ZinoUIStudio.new()
	ui_studio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui_studio.visible = false
	_ws_area.add_child(ui_studio)
	ui_studio.setup(session)
	_workspaces["UI"] = ui_studio
	audio_studio = ZinoAudioStudio.new()
	audio_studio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	audio_studio.visible = false
	_ws_area.add_child(audio_studio)
	audio_studio.setup(session)
	_workspaces["Audio"] = audio_studio
	store = ZinoAssetStore.new()
	store.size_flags_vertical = Control.SIZE_EXPAND_FILL
	store.visible = false
	_ws_area.add_child(store)
	store.setup(session)
	_workspaces["Store"] = store
	build_center = ZinoBuildCenter.new()
	build_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_center.visible = false
	_ws_area.add_child(build_center)
	build_center.setup(session)
	_workspaces["Build"] = build_center
	viewport_panel.block_traced.connect(func(id): block_studio.trace(id))
	viewport_panel.block_error.connect(func(id, msg): block_studio.runtime_error(id, msg))
	viewport_panel.stop_requested.connect(_stop)
	viewport_panel.tool_changed.connect(_on_tool_changed)
	if simple:
		_bottom.visible = false
		_right_tabs.current_tab = 0
	coach = ZinoCoach.new()
	coach.setup(self)
	viewport_panel.add_child(coach)
	session.state_changed.connect(_refresh_state)
	session.selection_changed.connect(func(_ids): _refresh_state())
	session.bridge_status_changed.connect(_on_bridge_status)
	_on_bridge_status(session.bridge.status)
	viewport_panel.set_tool("translate")
	_refresh_state()

# --- Menu bar --------------------------------------------------------------------------------

func _build_menu_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", ZinoTheme.box(ZinoTheme.BG_2, 0, Color.TRANSPARENT, 0, 4))
	var h := ZinoUI.hbox(10)
	bar.add_child(h)
	var logo := TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.custom_minimum_size = Vector2(22, 22)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(logo)
	var mb := MenuBar.new()
	h.add_child(mb)
	_menu(mb, "File", [["New Project…", M_NEW], ["Open Project…", M_OPEN], [], ["New Scene…", M_NEW_SCENE, KEY_MASK_CTRL | KEY_N], ["Open Scene…", M_OPEN_SCENE, KEY_MASK_CTRL | KEY_O], ["Save Scene", M_SAVE, KEY_MASK_CTRL | KEY_S], ["Save Scene As…", M_SAVE_AS, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S], ["Set as Start Scene", M_START_SCENE], [], ["Close Project", M_CLOSE], ["Quit", M_QUIT, KEY_MASK_CTRL | KEY_Q]])
	_menu(mb, "Edit", [["Undo", M_UNDO, KEY_MASK_CTRL | KEY_Z], ["Redo", M_REDO, KEY_MASK_CTRL | KEY_Y], [], ["Duplicate", M_DUP, KEY_MASK_CTRL | KEY_D], ["Delete", M_DEL, KEY_DELETE], ["Rename", M_RENAME, KEY_F2], [], ["Select All", M_SELALL, KEY_MASK_CTRL | KEY_A], ["Deselect All", M_DESEL, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_A]])
	_menu(mb, "View", [["Perspective", M_PERSP, KEY_KP_5], ["Top", M_TOP, KEY_KP_7], ["Front", M_FRONT, KEY_KP_1], ["Side", M_SIDE, KEY_KP_3], [], ["Frame Selected", M_FRAME, KEY_F], ["Toggle Grid", M_GRID, KEY_G], [], ["Performance Stats", M_STATS], ["Benchmark Presets", M_BENCH], [], ["Advanced Mode (all tools)", M_ADVANCED], ["Show Coach", M_COACH]])
	_menu(mb, "Project", [["Project Settings…", M_PSETTINGS], ["Validate Project", M_VALIDATE], ["Repair Add-ons", M_REPAIR], [], ["Show Project Folder", M_FOLDER]])
	var scene_items: Array = []
	for k in ["empty", "cube", "sphere", "cylinder", "capsule", "plane", "directionalLight", "pointLight", "spotLight", "camera"]:
		scene_items.append(["Add " + ZinoEntities.CREATABLE[k], M_ADD + ZinoEntities.CREATABLE.keys().find(k)])
	_menu(mb, "Scene", scene_items)
	_menu(mb, "Game", [["Play", M_PLAY, KEY_F5], ["Pause / Resume", M_PAUSE, KEY_F6], ["Stop", M_STOP, KEY_F8], [], ["Play in Godot Editor", M_PLAY_GODOT], ["Stop Godot Playtest", M_STOP_GODOT]])
	var race_items: Array = []
	for k in ["vehicle", "road", "checkpoint", "startFinish", "spawnPoint"]:
		race_items.append(["Add " + ZinoEntities.CREATABLE[k], M_RACE + ZinoEntities.CREATABLE.keys().find(k)])
	_menu(mb, "Racing", race_items)
	_menu(mb, "Tools", [["Open in Godot Editor", M_GODOT], ["Sync Scene to Godot", M_SYNC], ["Save Godot Scene (.tscn)", M_SAVE_GODOT], [], ["Restart Bridge", M_RESTART_BRIDGE]])
	_menu(mb, "Window", [["Toggle Hierarchy", M_WIN_LEFT], ["Toggle Inspector", M_WIN_RIGHT], ["Toggle Bottom Panel", M_WIN_BOTTOM], [], ["Reset Layout", M_WIN_RESET]])
	_menu(mb, "Help", [["Documentation", M_DOCS], ["Open Log Folder", M_LOGS], [], ["About Zino", M_ABOUT]])
	h.add_child(ZinoUI.spacer())
	h.add_child(ZinoUI.label(session.project_name(), 13, ZinoTheme.TEXT))
	_bridge_pill = ZinoUI.pill("Godot: offline", ZinoTheme.TEXT_DIM)
	_bridge_pill.visible = not OS.has_feature("mobile")
	h.add_child(_bridge_pill)
	return bar

func _menu(mb: MenuBar, title: String, items: Array) -> void:
	var p := PopupMenu.new()
	p.name = title
	for it in items:
		if it.is_empty():
			p.add_separator()
			continue
		p.add_item(it[0], it[1])
		if it.size() > 2:
			p.set_item_accelerator(p.get_item_index(it[1]), it[2])
	p.id_pressed.connect(_on_menu)
	mb.add_child(p)
	_menus[title] = p

func _on_menu(id: int) -> void:
	if id >= M_RACE:
		_add(ZinoEntities.CREATABLE.keys()[id - M_RACE])
		return
	if id >= M_ADD:
		_add(ZinoEntities.CREATABLE.keys()[id - M_ADD])
		return
	match id:
		M_NEW: confirm_close(func(): app.show_home(); app.home.open_wizard("circuit"))
		M_OPEN: confirm_close(func(): app.pick_project_file(func(p): app.open_project(p)))
		M_SAVE:
			session.save()
			if block_studio and block_studio.dirty:
				block_studio.save()
		M_NEW_SCENE: _new_scene_dialog()
		M_OPEN_SCENE: _open_scene_dialog()
		M_SAVE_AS: _save_as_dialog()
		M_START_SCENE: session.set_start_scene()
		M_CLOSE: confirm_close(func(): app.show_home())
		M_QUIT: confirm_close(func(): get_tree().quit())
		M_UNDO: session.undo()
		M_REDO: session.redo()
		M_DUP: session.duplicate_selection()
		M_DEL: session.delete_selection()
		M_RENAME: hierarchy.begin_rename()
		M_SELALL: session.select_all()
		M_DESEL: session.select([])
		M_PERSP: viewport_panel.set_view("Perspective")
		M_TOP: viewport_panel.set_view("Top")
		M_FRONT: viewport_panel.set_view("Front")
		M_SIDE: viewport_panel.set_view("Side")
		M_FRAME: viewport_panel.frame_selection()
		M_GRID:
			var on := not viewport_panel.overlays.grid.visible
			viewport_panel.overlays.set_grid_visible(on)
			app.settings.set_value("showGrid", on)
		M_STATS: viewport_panel.show_stats = not viewport_panel.show_stats
		M_ADVANCED: set_advanced(simple)
		M_COACH: coach.show_coach()
		M_BENCH: _benchmark()
		M_PSETTINGS: _project_settings_dialog()
		M_VALIDATE: _validate_project()
		M_REPAIR:
			var e := ZinoProjectService.install_addons(session.project_dir)
			if e == "":
				ZinoAppLog.info("Project", "Zino add-ons reinstalled into addons/.")
			else:
				ZinoAppLog.error("Project", e)
		M_FOLDER: OS.shell_open(session.project_dir)
		M_PLAY: _play()
		M_PAUSE: viewport_panel.set_paused(session.mode == "play")
		M_STOP: _stop()
		M_PLAY_GODOT: session.send_bridge_command(ZinoProtocol.START_PLAYTEST)
		M_STOP_GODOT: session.send_bridge_command(ZinoProtocol.STOP_PLAYTEST)
		M_GODOT: session.launch_godot_editor()
		M_SYNC:
			if session.bridge.is_connected_to_editor():
				session.sync_scene_to_godot()
			else:
				ZinoAppLog.warn("Bridge", "The Godot editor is not connected. Use Tools > Open in Godot Editor first.")
		M_SAVE_GODOT: session.send_bridge_command(ZinoProtocol.SAVE_SCENE)
		M_RESTART_BRIDGE:
			session.bridge.start(session.project_dir)
		M_WIN_LEFT: _left.visible = not _left.visible
		M_WIN_RIGHT: _right.visible = not _right.visible
		M_WIN_BOTTOM: _bottom.visible = not _bottom.visible
		M_WIN_RESET:
			_left.visible = true
			_right.visible = true
			_bottom.visible = true
		M_DOCS: confirm_close(func(): app.show_home(); app.home.show_page("docs"))
		M_LOGS: OS.shell_open(ProjectSettings.globalize_path("user://logs"))
		M_ABOUT: app.show_message("About Zino Racing Engine", "Zino Racing Engine %s\nA racing game development environment built on Godot %s.\n\nRenderer: %s\nGPU: %s" % [
			ZinoFormat.ENGINE_VERSION, Engine.get_version_info().string, ProjectSettings.get_setting("rendering/renderer/rendering_method"), RenderingServer.get_video_adapter_name()])

func _add(kind: String) -> void:
	session.add_entity(kind)

# --- Toolbar ---------------------------------------------------------------------------------

func _build_toolbar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", ZinoTheme.box(ZinoTheme.PANEL, 0, Color.TRANSPARENT, 0, 6))
	var h := ZinoUI.hbox(4)
	bar.add_child(h)
	for t in [["select", "Select", "Q"], ["translate", "Move", "W"], ["rotate", "Rotate", "E"], ["scale", "Scale", "R"]]:
		var b := ZinoUI.toggle(t[1], false, func(on):
			if on: viewport_panel.set_tool(t[0]), "%s tool (%s)" % [t[1], t[2]])
		_tool_buttons[t[0]] = b
		h.add_child(b)
	if not simple:
		h.add_child(VSeparator.new())
		h.add_child(ZinoUI.toggle("Local", false, func(on):
			viewport_panel.gizmo.local_space = on, "Gizmo in local (on) or world (off) space"))
		h.add_child(ZinoUI.toggle("Snap", app.settings.get_value("snapEnabled", false), func(on):
			viewport_panel.snap = on
			app.settings.set_value("snapEnabled", on), "Snap moves/rotations/scales (hold Ctrl to invert). Steps are in Settings."))
	h.add_child(VSeparator.new())
	_undo_btn = ZinoUI.button("Undo", session.undo, "Undo (Ctrl+Z)")
	_redo_btn = ZinoUI.button("Redo", session.redo, "Redo (Ctrl+Y)")
	_save_btn = ZinoUI.button("Save", session.save, "Save scene (Ctrl+S)")
	h.add_child(_undo_btn)
	h.add_child(_redo_btn)
	h.add_child(_save_btn)
	h.add_child(VSeparator.new())
	var seg := ZinoUI.hbox(0)
	for item in (SIMPLE_WORKSPACES if simple else ADVANCED_WORKSPACES):
		var ws: String = item[0]
		var b := ZinoUI.toggle(item[1], ws == "Scene", func(_on): show_workspace(ws), "%s workspace" % item[1])
		_ws_buttons[ws] = b
		seg.add_child(b)
	h.add_child(seg)
	h.add_child(ZinoUI.spacer())
	_play_btn = ZinoUI.accent_button("▶  Play", _play)
	_play_btn.tooltip_text = "Playtest in the viewport with real vehicle physics (F5)"
	_pause_btn = ZinoUI.button("❚❚ Pause", func(): viewport_panel.set_paused(session.mode == "play"), "Pause / resume (F6)")
	_stop_btn = ZinoUI.button("■ Stop", _stop, "Stop playtest (F8)")
	h.add_child(_play_btn)
	h.add_child(_pause_btn)
	h.add_child(_stop_btn)
	h.add_child(ZinoUI.spacer())
	h.add_child(ZinoUI.dim("Preview", 12))
	var presets: Array = ZinoGraphics.ORDER.map(func(p): return [p, ZinoGraphics.label(p)])
	var q := ZinoUI.option(presets, session.preview_preset(), func(p):
		session.set_preview_preset(p)
		viewport_panel.set_preview_preset(p))
	q.size_flags_horizontal = Control.SIZE_SHRINK_END
	q.custom_minimum_size.x = 130
	q.tooltip_text = "Editor preview quality only. Game output quality is set in Project Settings and is never changed automatically."
	h.add_child(q)
	var adv := ZinoUI.toggle("Advanced", not simple, func(on): set_advanced(on), "Advanced Mode: every professional tool (World, UI, Audio studios, gizmo options, console…). Your game stays the same.")
	h.add_child(adv)
	return bar

func _build_add_palette() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Add"
	var v := ZinoUI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ZinoUI.margin(v, 8))
	scroll.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var groups := [
		["Vehicles", ["vehicle"]],
		["Track Components", ["road", "startFinish", "checkpoint", "spawnPoint"]],
		["World Objects", ["cube", "sphere", "cylinder", "capsule", "plane", "empty"]],
		["Environment", ["directionalLight", "pointLight", "spotLight", "camera"]],
		["Open World", ["terrain", "vegetation", "water", "building"]],
	]
	for g in groups:
		v.add_child(ZinoUI.section(g[0]))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		for k in g[1]:
			var b := ZinoUI.button(ZinoEntities.CREATABLE[k], func(): _add(k), "Add to the scene at the viewport's focus point")
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(b)
		v.add_child(grid)
	return scroll

func _build_status_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", ZinoTheme.box(ZinoTheme.BG_2, 0, Color.TRANSPARENT, 0, 4))
	var h := ZinoUI.hbox(16)
	bar.add_child(h)
	_status_left = ZinoUI.dim("", 12)
	h.add_child(_status_left)
	h.add_child(ZinoUI.spacer())
	_status_bridge = ZinoUI.dim("", 12)
	h.add_child(_status_bridge)
	h.add_child(ZinoUI.dim("Game output: " + ZinoGraphics.label(session.game_preset()), 12))
	return bar

# --- State ------------------------------------------------------------------------------------

func _refresh_state() -> void:
	if _undo_btn == null:
		return
	var editing := session.mode == "edit"
	_undo_btn.disabled = not (editing and session.stack.can_undo())
	_redo_btn.disabled = not (editing and session.stack.can_redo())
	_undo_btn.tooltip_text = "Undo %s (Ctrl+Z)" % session.stack.undo_label()
	_redo_btn.tooltip_text = "Redo %s (Ctrl+Y)" % session.stack.redo_label()
	_save_btn.text = "Save*" if session.is_dirty() else "Save"
	_save_btn.disabled = not editing
	_play_btn.disabled = not editing
	_pause_btn.disabled = editing
	_pause_btn.text = "▶ Resume" if session.mode == "paused" else "❚❚ Pause"
	_stop_btn.disabled = editing
	_status_left.text = "%s%s  ·  %d objects  ·  %d selected  ·  %s" % [
		session.scene_rel, " (unsaved)" if session.is_dirty() else "", session.scene()["entities"].size(),
		session.selection.size(), {"edit": "Editing", "play": "Playing", "paused": "Paused"}[session.mode]]
	get_window().title = "%s%s — Zino Racing Engine" % ["• " if session.is_dirty() else "", session.project_name()]

func _on_tool_changed(t: String) -> void:
	for k in _tool_buttons:
		_tool_buttons[k].set_pressed_no_signal(k == t)

func _on_bridge_status(status: String) -> void:
	var text: String = {"connected": "Godot: connected", "listening": "Godot: waiting", "stopped": "Godot: offline"}.get(status, status)
	var color: Color = {"connected": ZinoTheme.OK, "listening": ZinoTheme.WARN}.get(status, ZinoTheme.TEXT_DIM)
	if _bridge_pill:
		var l: Label = _bridge_pill.get_child(0)
		l.text = text
		l.add_theme_color_override("font_color", color.lightened(0.3))
		_bridge_pill.add_theme_stylebox_override("panel", ZinoTheme.box(color.darkened(0.7), 10, color.darkened(0.2), 1, 8))
	if _status_bridge:
		_status_bridge.text = "Bridge 127.0.0.1:%d — %s" % [session.bridge.port, status] if session.bridge.port > 0 else "Bridge offline"

## Switches between Simple and Advanced mode (reopens the editor on the same project).
func set_advanced(on: bool) -> void:
	if on == not simple:
		return
	app.settings.set_value("simpleMode", not on)
	var dir := session.project_dir
	confirm_close(func(): app.open_project(dir))

## Shows one workspace (Scene, Blocks, ...) in the central area.
func show_workspace(ws_name: String) -> void:
	if vehicle_studio and ws_name != "Vehicle" and vehicle_studio._driving:
		vehicle_studio.stop_drive()
	var area := "Scene" if ws_name in ["Track", "World"] else ws_name
	for k in _workspaces:
		_workspaces[k].visible = k == area
	for k in _ws_buttons:
		_ws_buttons[k].set_pressed_no_signal(k == ws_name)
	if ws_name in ["Scene", "Track", "World"]:
		_right.visible = true
		# Simple mode opens on the friendly Game tab; Advanced on the Inspector.
		_right_tabs.current_tab = {"Scene": 0 if simple else 1, "Track": 2, "World": 3}[ws_name]

func _play() -> void:
	if block_studio and block_studio.dirty:
		block_studio.save()
	if viewport_panel.start_play():
		_refresh_state()

func _stop() -> void:
	viewport_panel.stop_play()
	_refresh_state()

# --- Shortcuts ----------------------------------------------------------------------------------

func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or session == null:
		return
	var k := event as InputEventKey
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is TextEdit or (focus != null and focus.get_parent() is SpinBox)
	if typing:
		return
	if session.mode != "edit":
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_F8:
			_stop()
			get_viewport().set_input_as_handled()
		return
	if k.ctrl_pressed or k.alt_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return   # Ctrl shortcuts are handled by menu accelerators; RMB+WASD flies the camera
	var tools := {KEY_Q: "select", KEY_W: "translate", KEY_E: "rotate", KEY_R: "scale"}
	if tools.has(k.keycode):
		viewport_panel.set_tool(tools[k.keycode])
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ESCAPE:
		session.select([])
		get_viewport().set_input_as_handled()

# --- Dialogs ------------------------------------------------------------------------------------

## Runs `then` after making sure unsaved work is saved or deliberately discarded.
func confirm_close(then: Callable) -> void:
	if session == null or session.stack == null:
		then.call()
		return
	if session.mode != "edit":
		_stop()
	if block_studio and block_studio.dirty:
		block_studio.save()
	if not session.is_dirty():
		session.shutdown()
		then.call()
		return
	app.ask("Unsaved changes", "Save changes to %s before closing?" % session.scene_rel, ["Save", "Don't Save"], func(choice):
		if choice == "Save":
			if session.save():
				session.shutdown()
				then.call()
		elif choice == "Don't Save":
			ZinoProjectService.clear_autosave(session.project_dir, session.scene_rel)
			session.shutdown()
			then.call())

## Opens another scene after resolving unsaved changes in the current one.
func open_scene_confirmed(rel: String) -> void:
	if rel == session.scene_rel:
		return
	var go := func():
		var err := session.open_scene(rel)
		if err != "":
			app.show_message("Cannot open scene", err)
		else:
			viewport_panel.frame_all()
			_refresh_state()
	if session.is_dirty():
		app.ask("Unsaved changes", "Save changes to %s before opening %s?" % [session.scene_rel, rel], ["Save", "Don't Save"], func(choice):
			if choice == "Save" and session.save():
				go.call()
			elif choice == "Don't Save":
				ZinoProjectService.clear_autosave(session.project_dir, session.scene_rel)
				go.call())
	else:
		go.call()

func _name_dialog(title: String, extra: Control, on_ok: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	d.theme = app.app_theme
	d.min_size = Vector2i(460, 0)
	var v := ZinoUI.vbox(10)
	var e := LineEdit.new()
	e.placeholder_text = "Scene name"
	v.add_child(ZinoUI.row("Name", e, 90))
	if extra:
		v.add_child(extra)
	d.add_child(v)
	d.confirmed.connect(func():
		var err: String = on_ok.call(e.text.strip_edges())
		if err != "":
			app.show_message(title, err)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	e.grab_focus.call_deferred()

func _new_scene_dialog() -> void:
	var choice := {"t": "empty"}
	var items: Array = [["empty", "Empty (ground, sun, camera)"]]
	for tid in ZinoTemplates.ORDER:
		if tid != "empty":
			items.append([tid, ZinoTemplates.PROJECTS[tid]["name"]])
	var opt := ZinoUI.option(items, "empty", func(t): choice.t = t)
	_name_dialog("New Scene", ZinoUI.row("Start from", opt, 90), func(n):
		var go := func() -> String:
			var err := session.new_scene(n, choice.t)
			if err == "":
				viewport_panel.frame_all()
				_refresh_state()
			return err
		if session.is_dirty() and not session.save():
			return "Save the current scene first."
		return go.call())

func _save_as_dialog() -> void:
	_name_dialog("Save Scene As", null, func(n): return session.save_scene_as(n))

func _open_scene_dialog() -> void:
	var d := AcceptDialog.new()
	d.title = "Open Scene"
	d.theme = app.app_theme
	d.min_size = Vector2i(420, 360)
	d.ok_button_text = "Open"
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(380, 260)
	for rel in session.list_scenes():
		var label: String = rel.get_file()
		if rel == session.manifest.get("startScene"):
			label += "   (start scene)"
		if rel == session.scene_rel:
			label += "   (open)"
		list.add_item(label)
		list.set_item_metadata(list.item_count - 1, rel)
	d.add_child(list)
	var pick := func():
		var sel := list.get_selected_items()
		if not sel.is_empty():
			var rel: String = list.get_item_metadata(sel[0])
			d.queue_free()
			open_scene_confirmed(rel)
	d.confirmed.connect(pick)
	list.item_activated.connect(func(_i): pick.call())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()

## Measures the current scene's FPS at every graphics preset in the editor viewport (2 s each).
func _benchmark() -> void:
	if session.mode != "edit":
		return
	var original := viewport_panel.preview_preset
	var results := []
	ZinoAppLog.info("Graphics", "Benchmark started — the viewport cycles through every preset.")
	for p in ZinoGraphics.ORDER:
		viewport_panel.set_preview_preset(p)
		for i in 10:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		var frames := 0
		while Time.get_ticks_usec() - t0 < 2000000:
			await get_tree().process_frame
			frames += 1
		var fps := frames / ((Time.get_ticks_usec() - t0) / 1000000.0)
		results.append("%s %.1f FPS" % [ZinoGraphics.label(p), fps])
	viewport_panel.set_preview_preset(original)
	ZinoAppLog.info("Graphics", "Benchmark (%s, %dx%d): %s" % [RenderingServer.get_video_adapter_name(), viewport_panel.viewport.size.x, viewport_panel.viewport.size.y, " · ".join(results)])
	app.show_message("Benchmark results", "\n".join(results))

func _validate_project() -> void:
	var w := ZinoProjectService.validate_project(session.project_dir, session.manifest)
	var problems := ZinoFormat.validate_scene(session.scene())
	w.append_array(problems)
	if w.is_empty():
		ZinoAppLog.info("Project", "Validation passed: manifest, scene, add-ons and folders are OK.")
		app.show_message("Project is valid", "Manifest, scene, add-ons and folders are OK.")
	else:
		for x in w:
			ZinoAppLog.warn("Project", x)
		app.show_message("Validation found %d issue(s)" % w.size(), "\n".join(w))

func _project_settings_dialog() -> void:
	var m := session.manifest
	var d := ConfirmationDialog.new()
	d.title = "Project Settings"
	d.theme = app.app_theme
	d.min_size = Vector2i(560, 420)
	d.ok_button_text = "Save"
	var v := ZinoUI.vbox(10)
	var name_e := LineEdit.new()
	name_e.text = m["project"].get("name", "")
	var ver_e := LineEdit.new()
	ver_e.text = m["project"].get("version", "0.1.0")
	var bundle_e := LineEdit.new()
	bundle_e.text = m["project"].get("bundleIdentifier", "")
	v.add_child(ZinoUI.row("Display name", name_e, 150))
	v.add_child(ZinoUI.row("Version", ver_e, 150))
	v.add_child(ZinoUI.row("iOS bundle id", bundle_e, 150))
	var out := {"preset": session.game_preset(), "platforms": m.get("targetPlatforms", []).duplicate()}
	var presets: Array = ZinoGraphics.ORDER.map(func(p): return [p, ZinoGraphics.label(p)])
	v.add_child(ZinoUI.row("Game output quality", ZinoUI.option(presets, out.preset, func(p): out.preset = p), 150))
	var plat := ZinoUI.hbox(12)
	for p in [["ios", "iOS"], ["windows", "Windows"], ["android", "Android"]]:
		plat.add_child(ZinoUI.check(p[1], p[0] in out.platforms, func(on):
			if on and not p[0] in out.platforms: out.platforms.append(p[0])
			elif not on: out.platforms.erase(p[0])))
	v.add_child(ZinoUI.row("Target platforms", plat, 150))
	v.add_child(ZinoUI.dim("Template: %s · Physics profile: %s · Zino %s on Godot %s" % [m.get("template"), m.get("physicsProfile"), m["engine"].get("version"), m["engine"].get("godotVersion")], 12))
	d.add_child(v)
	d.confirmed.connect(func():
		var n := name_e.text.strip_edges()
		if not ZinoFormat.is_safe_name(n):
			ZinoAppLog.error("Project", "Invalid project name; settings not saved.")
			return
		m["project"]["name"] = n
		m["project"]["version"] = ver_e.text.strip_edges()
		m["project"]["bundleIdentifier"] = bundle_e.text.strip_edges()
		m["graphics"]["gameOutput"] = out.preset
		if not out.platforms.is_empty():
			m["targetPlatforms"] = out.platforms
		ZinoProjectService.save_manifest(session.project_dir, m)
		ZinoAppLog.info("Project", "Project settings saved (game output %s)." % ZinoGraphics.label(out.preset))
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
