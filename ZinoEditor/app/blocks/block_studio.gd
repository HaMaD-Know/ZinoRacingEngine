class_name ZinoBlockStudio
extends HSplitContainer
## Block Studio: visual programming for racing game logic.
## Programs live in Blocks/*.zblocks and run in every playtest and exported game.

var session: ZinoEditorSession
var program: Dictionary = {}
var program_path := ""                 # relative to the project
var dirty := false

var _graph: GraphEdit
var _programs: ItemList
var _palette: Tree
var _search: LineEdit
var _problems: ItemList
var _code: TextEdit
var _vars_box: VBoxContainer
var _trace: ItemList
var _status: Label
var _undo: Array = []
var _redo: Array = []
var _clipboard: Dictionary = {}
var _ports := {}                       # node id -> {ins: [names], outs: [names]}
var _validate_pending := false
var _last_errors := {}                 # node id -> message

func setup(s: ZinoEditorSession) -> void:
	session = s
	split_offset = 0
	add_child(_build_left())
	var center := HSplitContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(center)
	var mid := ZinoUI.vbox(0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(_build_toolbar())
	_graph = GraphEdit.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.minimap_enabled = true
	_graph.minimap_size = Vector2(220, 150)
	_graph.right_disconnects = true
	_graph.snapping_enabled = true
	_graph.snapping_distance = 20
	_graph.show_grid = true
	_graph.zoom_min = 0.2
	_graph.zoom_max = 2.0
	_graph.connection_lines_curvature = 0.5
	_graph.connection_lines_thickness = 3.0
	for i in ZinoBlockLibrary.TYPES.size():
		_graph.add_valid_connection_type(i, i)
	var any := ZinoBlockLibrary.TYPES.find("any")
	var text := ZinoBlockLibrary.TYPES.find("text")
	for i in range(1, ZinoBlockLibrary.TYPES.size()):
		_graph.add_valid_connection_type(i, any)
		_graph.add_valid_connection_type(any, i)
	_graph.add_valid_connection_type(ZinoBlockLibrary.TYPES.find("number"), text)
	_graph.add_valid_connection_type(ZinoBlockLibrary.TYPES.find("bool"), text)
	_graph.connection_request.connect(_on_connect)
	_graph.disconnection_request.connect(_on_disconnect)
	_graph.delete_nodes_request.connect(func(names): delete_nodes(names.map(func(n): return str(n))))
	_graph.copy_nodes_request.connect(_copy)
	_graph.paste_nodes_request.connect(_paste)
	_graph.duplicate_nodes_request.connect(func(): _copy(); _paste())
	_graph.end_node_move.connect(_on_moved)
	_graph.set_drag_forwarding(Callable(), _graph_can_drop, _graph_drop)
	_graph.node_selected.connect(func(_n): pass)
	mid.add_child(_graph)
	center.add_child(mid)
	center.add_child(_build_right())
	_refresh_program_list()
	var scripts: Array = session.manifest.get("blockScripts", [])
	if not scripts.is_empty():
		open_program(scripts[0])
	else:
		new_program("Game Logic")

# --- Panels -------------------------------------------------------------------------------------

func _build_left() -> Control:
	var v := ZinoUI.vbox(6)
	v.custom_minimum_size.x = 270
	v.add_child(ZinoUI.section("Programs"))
	_programs = ItemList.new()
	_programs.custom_minimum_size.y = 110
	_programs.item_selected.connect(func(i): _switch_program(_programs.get_item_metadata(i)))
	v.add_child(_programs)
	var pb := ZinoUI.hbox(4)
	pb.add_child(ZinoUI.button("New", func(): _ask_name("New Program", "", func(n): return new_program(n))))
	pb.add_child(ZinoUI.button("Rename", func(): _ask_name("Rename Program", program.get("name", ""), func(n): return rename_program(n))))
	pb.add_child(ZinoUI.button("Delete", _confirm_delete))
	v.add_child(pb)
	v.add_child(ZinoUI.section("Blocks"))
	_search = LineEdit.new()
	_search.placeholder_text = "Search blocks…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _fill_palette())
	v.add_child(_search)
	_palette = Tree.new()
	_palette.hide_root = true
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.item_activated.connect(func():
		var it := _palette.get_selected()
		if it and it.get_metadata(0) != null:
			add_block(str(it.get_metadata(0))))
	_palette.set_drag_forwarding(_palette_drag, Callable(), Callable())
	v.add_child(_palette)
	v.add_child(ZinoUI.dim("Double-click or drag a block into the canvas.", 11))
	_fill_palette()
	return v

func _build_toolbar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", ZinoTheme.box(ZinoTheme.BG_2, 0, Color.TRANSPARENT, 0, 6))
	var h := ZinoUI.hbox(6)
	bar.add_child(h)
	var rec := ZinoUI.accent_button("✨ Recipes…", open_recipes)
	rec.tooltip_text = "Add a ready-made game rule (boost, final lap, timers, weather, scoring…)"
	h.add_child(rec)
	h.add_child(ZinoUI.button("Save", save, "Save program (Ctrl+S in the studio)"))
	h.add_child(ZinoUI.button("Undo", undo))
	h.add_child(ZinoUI.button("Redo", redo))
	h.add_child(VSeparator.new())
	h.add_child(ZinoUI.button("Duplicate", func(): _copy(); _paste()))
	h.add_child(ZinoUI.button("Delete", func(): delete_nodes(_selected_ids())))
	h.add_child(ZinoUI.button("Tidy Up", func(): _graph.arrange_nodes(); _sync_positions(); _changed(false)))
	h.add_child(ZinoUI.button("Validate", func(): validate(true)))
	h.add_child(ZinoUI.spacer())
	_status = ZinoUI.dim("", 12)
	h.add_child(_status)
	return bar

func _build_right() -> Control:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.x = 330
	var probs := ZinoUI.vbox(4)
	probs.name = "Problems"
	_problems = ItemList.new()
	_problems.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_problems.item_selected.connect(func(i):
		var nid = _problems.get_item_metadata(i)
		if nid != null and nid != "":
			focus_node(str(nid)))
	probs.add_child(_problems)
	tabs.add_child(probs)
	_code = TextEdit.new()
	_code.name = "Code"
	_code.editable = false
	_code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code.add_theme_font_override("font", SystemFont.new())
	_code.add_theme_font_size_override("font_size", 12)
	tabs.add_child(_code)
	var vars := ScrollContainer.new()
	vars.name = "Variables"
	_vars_box = ZinoUI.vbox(6)
	_vars_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vars.add_child(_vars_box)
	tabs.add_child(vars)
	var tr := ZinoUI.vbox(4)
	tr.name = "Trace"
	tr.add_child(ZinoUI.dim("Blocks executed during the playtest (newest first).", 11))
	_trace = ItemList.new()
	_trace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trace.item_selected.connect(func(i): focus_node(str(_trace.get_item_metadata(i))))
	tr.add_child(_trace)
	tr.add_child(ZinoUI.button("Clear", func(): _trace.clear()))
	tabs.add_child(tr)
	return tabs

func _fill_palette() -> void:
	_palette.clear()
	var root := _palette.create_item()
	var q := _search.text.strip_edges()
	var matches := ZinoBlockLibrary.search(q)
	for c in ZinoBlockLibrary.CATEGORIES:
		var ids: Array = ZinoBlockLibrary.blocks_in(c[0]).filter(func(id): return id in matches)
		if ids.is_empty():
			continue
		var cat := _palette.create_item(root)
		cat.set_text(0, "●  %s  (%d)" % [c[0], ids.size()])
		cat.set_custom_color(0, Color(c[1]))
		cat.set_selectable(0, false)
		cat.collapsed = q == "" and c[0] != "Events"
		for id in ids:
			var it := _palette.create_item(cat)
			var d := ZinoBlockLibrary.get_def(id)
			it.set_text(0, _plain_label(d.label))
			it.set_metadata(0, id)
			it.set_tooltip_text(0, "%s block · %s" % [d.kind, id])

static func _plain_label(label: String) -> String:
	var r := RegEx.new()
	r.compile("\\{([a-zA-Z0-9]+)\\}")
	return r.sub(label, "[$1]", true)

# --- Programs -------------------------------------------------------------------------------------

func _refresh_program_list() -> void:
	_programs.clear()
	var scripts: Array = session.manifest.get("blockScripts", [])
	var d := DirAccess.open(session.project_dir.path_join("Blocks"))
	if d:
		for f in d.get_files():
			if f.ends_with(".zblocks") and not ("Blocks/" + f) in scripts:
				scripts.append("Blocks/" + f)
	session.manifest["blockScripts"] = scripts
	for rel in scripts:
		_programs.add_item(rel.get_file().get_basename())
		_programs.set_item_metadata(_programs.item_count - 1, rel)
		if rel == program_path:
			_programs.select(_programs.item_count - 1)

func _switch_program(rel: String) -> void:
	if rel == program_path:
		return
	if dirty:
		save()
	open_program(rel)

func open_program(rel: String) -> bool:
	var r := ZinoFormat.read_json_file(session.project_dir.path_join(rel))
	if not r.ok or not (r.data is Dictionary) or r.data.get("format") != ZinoBlockCompiler.FORMAT:
		ZinoAppLog.error("Blocks", "Cannot open %s: %s" % [rel, r.error if not r.ok else "not a block program"])
		return false
	program = r.data
	program_path = rel
	_undo.clear()
	_redo.clear()
	dirty = false
	_rebuild_graph()
	_refresh_program_list()
	validate()
	return true

func new_program(prog_name: String) -> String:
	if not ZinoFormat.is_safe_name(prog_name) or not prog_name.is_valid_filename():
		return "Invalid program name."
	var rel := "Blocks/%s.zblocks" % prog_name
	if FileAccess.file_exists(session.project_dir.path_join(rel)):
		return "A program with that name exists."
	if dirty:
		save()
	program = ZinoBlockCompiler.new_program(prog_name)
	program.nodes.append(ZinoBlockCompiler.node("ev_game_start", Vector2(40, 40)))
	program_path = rel
	var scripts: Array = session.manifest.get("blockScripts", [])
	scripts.append(rel)
	session.manifest["blockScripts"] = scripts
	ZinoProjectService.save_manifest(session.project_dir, session.manifest)
	save()
	_undo.clear()
	_redo.clear()
	_rebuild_graph()
	_refresh_program_list()
	validate()
	return ""

func rename_program(new_name: String) -> String:
	if not ZinoFormat.is_safe_name(new_name) or not new_name.is_valid_filename():
		return "Invalid program name."
	var rel := "Blocks/%s.zblocks" % new_name
	if FileAccess.file_exists(session.project_dir.path_join(rel)):
		return "A program with that name exists."
	var err := DirAccess.rename_absolute(session.project_dir.path_join(program_path), session.project_dir.path_join(rel))
	if err != OK:
		return "Rename failed (%d)" % err
	var scripts: Array = session.manifest.get("blockScripts", [])
	scripts[scripts.find(program_path)] = rel
	program.name = new_name
	program_path = rel
	ZinoProjectService.save_manifest(session.project_dir, session.manifest)
	save()
	_refresh_program_list()
	return ""

func _confirm_delete() -> void:
	if program_path == "":
		return
	session.app.ask("Delete program?", "Delete %s? The file will be removed from the project and cannot be recovered from Zino." % program_path, ["Delete"], func(choice):
		if choice != "Delete":
			return
		DirAccess.remove_absolute(session.project_dir.path_join(program_path))
		var scripts: Array = session.manifest.get("blockScripts", [])
		scripts.erase(program_path)
		ZinoProjectService.save_manifest(session.project_dir, session.manifest)
		ZinoAppLog.info("Blocks", "Deleted " + program_path)
		program_path = ""
		program = {}
		_graph.clear_connections()
		for c in _graph.get_children():
			if c is GraphNode:
				c.free()
		_refresh_program_list()
		if not scripts.is_empty():
			open_program(scripts[0]))

func save() -> bool:
	if program_path == "" or program.is_empty():
		return false
	_sync_positions()
	var err := ZinoFormat.write_text_atomic(session.project_dir.path_join(program_path), ZinoFormat.to_json(program))
	if err != OK:
		ZinoAppLog.error("Blocks", "Could not save %s (%d)" % [program_path, err])
		return false
	dirty = false
	_status.text = "Saved " + program_path.get_file()
	ZinoAppLog.info("Blocks", "Saved " + program_path)
	return true

func _ask_name(title: String, initial: String, on_ok: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	d.theme = session.app.app_theme
	var e := LineEdit.new()
	e.text = initial
	e.custom_minimum_size.x = 320
	d.add_child(e)
	d.confirmed.connect(func():
		var err: String = on_ok.call(e.text.strip_edges())
		if err != "":
			session.app.show_message(title, err)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	e.grab_focus.call_deferred()

# --- Editing --------------------------------------------------------------------------------------

func _snapshot() -> void:
	_undo.append(program.duplicate(true))
	if _undo.size() > 100:
		_undo.pop_front()
	_redo.clear()

func _changed(snapshot: bool = true) -> void:
	dirty = true
	_status.text = program_path.get_file() + " (unsaved)"
	if not _validate_pending:
		_validate_pending = true
		validate.call_deferred()

func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(program.duplicate(true))
	program = _undo.pop_back()
	_rebuild_graph()
	_changed()

func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(program.duplicate(true))
	program = _redo.pop_back()
	_rebuild_graph()
	_changed()

func add_block(block_id: String, at = null) -> String:
	if program.is_empty():
		return ""
	_snapshot()
	var pos: Vector2 = at if at is Vector2 else (_graph.scroll_offset + _graph.size * 0.5) / _graph.zoom - Vector2(120, 40)
	var n := ZinoBlockCompiler.node(block_id, pos.snapped(Vector2(20, 20)))
	program.nodes.append(n)
	_add_graph_node(n)
	_changed()
	return n.id

## Inserts a recipe (pre-wired blocks) below the existing blocks. One undo step. Returns the new ids.
func insert_recipe(recipe_id: String) -> Array:
	if program.is_empty():
		return []
	var bottom := -200.0
	for n in program.nodes:
		bottom = maxf(bottom, float(n.pos[1]))
	var built := ZinoBlockRecipes.build(recipe_id, Vector2(700, bottom + 320))
	if built.is_empty():
		return []
	_snapshot()
	program.nodes.append_array(built.nodes)
	program.links.append_array(built.links)
	_rebuild_graph()
	_changed()
	var ids: Array = built.nodes.map(func(n): return n.id)
	focus_node(ids[0])
	ZinoAppLog.info("Blocks", "Added recipe: " + ZinoBlockRecipes.find(recipe_id).name)
	return ids

## The recipe picker: big cards, one click inserts.
func open_recipes() -> void:
	var w := AcceptDialog.new()
	w.title = "Add a game rule"
	w.ok_button_text = "Close"
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(760, 470)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := ZinoUI.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(ZinoUI.dim("Each recipe adds normal blocks to your program — change any value afterwards, or delete it with Undo.", 12))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in ZinoBlockRecipes.RECIPES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(360, 74)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "  %s   %s\n        %s" % [r.icon, r.name, r.desc]
		b.add_theme_stylebox_override("normal", ZinoTheme.box(ZinoTheme.PANEL_2, 12, ZinoTheme.BORDER, 1, 10))
		b.add_theme_stylebox_override("hover", ZinoTheme.box(Color(ZinoTheme.ACCENT, 0.12), 12, ZinoTheme.ACCENT, 2, 10))
		var rid: String = r.id
		b.pressed.connect(func():
			insert_recipe(rid)
			w.queue_free())
		g.add_child(b)
	v.add_child(g)
	w.add_child(sc)
	w.confirmed.connect(w.queue_free)
	w.canceled.connect(w.queue_free)
	add_child(w)
	w.popup_centered()

func delete_nodes(ids: Array) -> void:
	if ids.is_empty():
		return
	_snapshot()
	program.nodes = program.nodes.filter(func(n): return not n.id in ids)
	program.links = program.links.filter(func(l): return not l.from in ids and not l.to in ids)
	_rebuild_graph()
	_changed()

func _on_connect(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var f := str(from_node)
	var t := str(to_node)
	var out_name: String = _ports[f].outs[from_port]
	var in_name: String = _ports[t].ins[to_port]
	if f == t:
		return
	_snapshot()
	# An output (exec) or an input (value) accepts one connection: replace the old one.
	program.links = program.links.filter(func(l):
		if in_name == "exec":
			return not (l.from == f and l.out == out_name)
		return not (l.to == t and l["in"] == in_name))
	program.links.append(ZinoBlockCompiler.link(f, out_name, t, in_name))
	_rebuild_connections()
	_changed()

func _on_disconnect(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var f := str(from_node)
	var t := str(to_node)
	var out_name: String = _ports[f].outs[from_port]
	var in_name: String = _ports[t].ins[to_port]
	_snapshot()
	program.links = program.links.filter(func(l): return not (l.from == f and l.out == out_name and l.to == t and l["in"] == in_name))
	_rebuild_connections()
	_changed()

func _on_moved() -> void:
	_sync_positions()
	dirty = true

func _sync_positions() -> void:
	for n in program.get("nodes", []):
		var gn := _graph.get_node_or_null(NodePath(n.id)) as GraphNode
		if gn:
			n.pos = [gn.position_offset.x, gn.position_offset.y]

func _selected_ids() -> Array:
	var out: Array = []
	for c in _graph.get_children():
		if c is GraphNode and c.selected:
			out.append(str(c.name))
	return out

func _copy() -> void:
	var ids := _selected_ids()
	_clipboard = {"nodes": program.nodes.filter(func(n): return n.id in ids).map(func(n): return n.duplicate(true)),
		"links": program.links.filter(func(l): return l.from in ids and l.to in ids).map(func(l): return l.duplicate(true))}

func _paste() -> void:
	if _clipboard.is_empty() or _clipboard.nodes.is_empty():
		return
	_snapshot()
	var map := {}
	for n in _clipboard.nodes:
		var c: Dictionary = n.duplicate(true)
		c.id = "n_" + ZinoFormat.new_id().substr(2)
		c.pos = [float(c.pos[0]) + 40.0, float(c.pos[1]) + 40.0]
		map[n.id] = c.id
		program.nodes.append(c)
	for l in _clipboard.links:
		program.links.append(ZinoBlockCompiler.link(map[l.from], l.out, map[l.to], l["in"]))
	_rebuild_graph()
	for id in map.values():
		var gn := _graph.get_node_or_null(NodePath(id)) as GraphNode
		if gn:
			gn.selected = true
	_changed()

func _palette_drag(_at: Vector2):
	var it := _palette.get_selected()
	if it == null or it.get_metadata(0) == null:
		return null
	_palette.set_drag_preview(ZinoUI.label(_plain_label(ZinoBlockLibrary.get_def(it.get_metadata(0)).label), 13))
	return {"zino_block": it.get_metadata(0)}

func _graph_can_drop(_at: Vector2, data) -> bool:
	return data is Dictionary and data.has("zino_block")

func _graph_drop(at: Vector2, data) -> void:
	add_block(data.zino_block, (_graph.scroll_offset + at) / _graph.zoom)

# --- Graph building -------------------------------------------------------------------------------

func _rebuild_graph() -> void:
	_graph.clear_connections()
	for c in _graph.get_children():
		if c is GraphNode:
			_graph.remove_child(c)
			c.queue_free()
	_ports.clear()
	for n in program.get("nodes", []):
		_add_graph_node(n)
	_rebuild_connections()
	_rebuild_vars()

func _rebuild_connections() -> void:
	_graph.clear_connections()
	for l in program.get("links", []):
		if not (_ports.has(l.from) and _ports.has(l.to)):
			continue
		var fp: int = _ports[l.from].outs.find(l.out)
		var tp: int = _ports[l.to].ins.find(l["in"])
		if fp >= 0 and tp >= 0:
			_graph.connect_node(StringName(l.from), fp, StringName(l.to), tp)

func _add_graph_node(n: Dictionary) -> void:
	var d := ZinoBlockLibrary.get_def(n.block)
	if d.is_empty():
		return
	var gn := GraphNode.new()
	gn.name = n.id
	gn.title = _plain_label(d.label)
	gn.position_offset = Vector2(float(n.pos[0]), float(n.pos[1]))
	gn.resizable = false
	var col := ZinoBlockLibrary.category_color(d.category)
	var tb := ZinoTheme.box(col, 10, Color.TRANSPARENT, 0, 10)
	tb.corner_radius_bottom_left = 0
	tb.corner_radius_bottom_right = 0
	gn.add_theme_stylebox_override("titlebar", tb)
	gn.add_theme_stylebox_override("titlebar_selected", tb)
	var title_label := gn.get_titlebar_hbox().get_child(0) as Label
	if title_label:
		title_label.add_theme_color_override("font_color", Color.WHITE if col.get_luminance() < 0.6 else Color(0.1, 0.1, 0.1))
	var ins: Array = []
	var outs: Array = []
	var exec_c: Color = ZinoBlockLibrary.TYPE_COLORS[0]
	# Row 0: flow in/out or value out.
	var row0 := ZinoUI.hbox(6)
	var l0 := ZinoUI.dim({"event": "starts here", "function": "function body", "value": "value", "control": "", "stmt": ""}[d.kind], 11)
	l0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row0.add_child(l0)
	if d.kind == "value":
		var out_label := ZinoUI.dim(d.output, 11)
		out_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row0.add_child(out_label)
	gn.add_child(row0)
	var has_in := ZinoBlockLibrary.has_exec_input(n.block)
	var out_type := ZinoBlockLibrary.type_index(d.output) if d.kind == "value" else 0
	gn.set_slot(0, has_in, 0, exec_c, true, out_type, ZinoBlockLibrary.TYPE_COLORS[out_type] if d.kind == "value" else exec_c)
	if has_in:
		ins.append("exec")
	outs.append("value" if d.kind == "value" else "next")
	var row := 1
	for inp in d.inputs:
		var h := ZinoUI.hbox(6)
		var lab := ZinoUI.label(inp[0], 12, ZinoTheme.TEXT_DIM)
		lab.custom_minimum_size.x = 62
		h.add_child(lab)
		h.add_child(_literal_editor(n, inp))
		gn.add_child(h)
		var ti := ZinoBlockLibrary.type_index(inp[1])
		gn.set_slot(row, true, ti, ZinoBlockLibrary.TYPE_COLORS[ti], false, 0, Color.WHITE)
		ins.append(inp[0])
		row += 1
	for extra in d.exec_outs:
		var el := ZinoUI.label(extra + "  ▸", 12, ZinoTheme.TEXT)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gn.add_child(el)
		gn.set_slot(row, false, 0, Color.WHITE, true, 0, exec_c)
		outs.append(extra)
		row += 1
	# Port order: row 0 output first, then extra exec outputs in row order.
	_ports[n.id] = {"ins": ins, "outs": outs}
	_graph.add_child(gn)

func _literal_editor(n: Dictionary, inp: Array) -> Control:
	var key: String = inp[0]
	var t: String = inp[1]
	var v = n.values.get(key, inp[2])
	var set_v := func(x):
		_snapshot()
		n.values[key] = x
		_changed()
	if t == "number":
		var s := SpinBox.new()
		s.step = 0.001
		s.allow_greater = true
		s.allow_lesser = true
		s.min_value = -1e9
		s.max_value = 1e9
		s.value = float(v) if (v is float or v is int) else 0.0
		s.custom_minimum_size.x = 110
		s.select_all_on_focus = true
		s.value_changed.connect(func(x): set_v.call(x))
		return s
	if t == "bool":
		var c := CheckBox.new()
		c.button_pressed = bool(v)
		c.text = "yes"
		c.toggled.connect(func(x): set_v.call(x))
		return c
	if t == "vector":
		var h := ZinoUI.hbox(2)
		var arr: Array = v if v is Array and v.size() == 3 else [0, 0, 0]
		var boxes: Array = []
		for i in 3:
			var s := SpinBox.new()
			s.step = 0.01
			s.allow_greater = true
			s.allow_lesser = true
			s.min_value = -1e9
			s.max_value = 1e9
			s.value = float(arr[i])
			s.custom_minimum_size.x = 70
			boxes.append(s)
			h.add_child(s)
		for s in boxes:
			s.value_changed.connect(func(_x): set_v.call([boxes[0].value, boxes[1].value, boxes[2].value]))
		return h
	if t == "color":
		var cp := ColorPickerButton.new()
		cp.color = Color.html(str(v)) if Color.html_is_valid(str(v)) else Color.RED
		cp.custom_minimum_size = Vector2(80, 24)
		cp.popup_closed.connect(func(): set_v.call("#" + cp.color.to_html(false)))
		return cp
	if t.begins_with("enum:"):
		var o := OptionButton.new()
		var opts := t.substr(5).split("|")
		for i in opts.size():
			o.add_item(opts[i])
			if opts[i] == str(v):
				o.select(i)
		o.item_selected.connect(func(i): set_v.call(opts[i]))
		return o
	var e := LineEdit.new()
	e.text = str(v)
	e.custom_minimum_size.x = 130
	e.placeholder_text = {"vehicle": "player or vehicle name", "var": "variable name"}.get(t, "")
	var commit := func(_x = null):
		var x = e.text
		if t == "any":
			if x.is_valid_float():
				x = float(x)
			elif x == "true" or x == "false":
				x = x == "true"
		if n.values.get(key) != x:
			set_v.call(x)
	e.text_submitted.connect(commit)
	e.focus_exited.connect(commit)
	return e

func _rebuild_vars() -> void:
	for c in _vars_box.get_children():
		c.queue_free()
	_vars_box.add_child(ZinoUI.dim("Global variables and their starting values.", 11))
	for v in program.get("variables", []):
		var h := ZinoUI.hbox(4)
		var name_e := LineEdit.new()
		name_e.text = str(v.name)
		name_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_e.text_submitted.connect(func(t): _snapshot(); v.name = t.strip_edges(); _changed())
		var val_e := LineEdit.new()
		val_e.text = str(v.value)
		val_e.custom_minimum_size.x = 80
		val_e.text_submitted.connect(func(t): _snapshot(); v.value = float(t) if t.is_valid_float() else t; _changed())
		h.add_child(name_e)
		h.add_child(val_e)
		h.add_child(ZinoUI.button("✕", func():
			_snapshot()
			program.variables.erase(v)
			_rebuild_vars()
			_changed()))
		_vars_box.add_child(h)
	_vars_box.add_child(ZinoUI.button("Add variable", func():
		_snapshot()
		program.variables.append({"name": "var%d" % (program.variables.size() + 1), "value": 0})
		_rebuild_vars()
		_changed()))

# --- Validation, focus, trace -------------------------------------------------------------------

func validate(report: bool = false) -> Dictionary:
	_validate_pending = false
	if program.is_empty():
		return {}
	var r := ZinoBlockCompiler.compile(program)
	_problems.clear()
	_last_errors.clear()
	for e in r.errors:
		_problems.add_item("⛔  " + e.message)
		_problems.set_item_metadata(_problems.item_count - 1, e.node)
		_problems.set_item_custom_fg_color(_problems.item_count - 1, ZinoTheme.ERROR)
		if e.node != "":
			_last_errors[e.node] = e.message
	for w in r.warnings:
		_problems.add_item("⚠  " + w.message)
		_problems.set_item_metadata(_problems.item_count - 1, w.node)
		_problems.set_item_custom_fg_color(_problems.item_count - 1, ZinoTheme.WARN)
	if r.errors.is_empty() and r.warnings.is_empty():
		_problems.add_item("✓  No problems. %d blocks, %d scripts." % [program.nodes.size(), r.ir.scripts.size()])
	for c in _graph.get_children():
		if c is GraphNode:
			var bad := _last_errors.has(str(c.name))
			var base := ZinoTheme.PANEL_2 if ZinoTheme.dark else Color.WHITE
			c.add_theme_stylebox_override("panel", ZinoTheme.box(base, 10, ZinoTheme.ERROR if bad else ZinoTheme.BORDER, 2 if bad else 1, 10))
			c.tooltip_text = _last_errors.get(str(c.name), "")
	_code.text = ZinoBlockCompiler.to_script(program)
	if report:
		ZinoAppLog.write("info" if r.ok else "error", "Blocks", "%s: %d error(s), %d warning(s)" % [program_path, r.errors.size(), r.warnings.size()])
	return r

func focus_node(id: String) -> void:
	var gn := _graph.get_node_or_null(NodePath(id)) as GraphNode
	if gn == null:
		return
	for c in _graph.get_children():
		if c is GraphNode:
			c.selected = c == gn
	_graph.scroll_offset = gn.position_offset * _graph.zoom - _graph.size * 0.5 + gn.size * 0.5

## Called while a playtest runs: flashes the block and records it in the trace.
func trace(node_id: String) -> void:
	var gn := _graph.get_node_or_null(NodePath(node_id)) as GraphNode
	if gn == null:
		return
	_trace.add_item("%s  %s" % [Time.get_time_string_from_system(), gn.title])
	_trace.set_item_metadata(_trace.item_count - 1, node_id)
	_trace.move_item(_trace.item_count - 1, 0)
	if _trace.item_count > 300:
		_trace.remove_item(_trace.item_count - 1)
	gn.modulate = Color(1.4, 1.4, 1.0)
	create_tween().tween_property(gn, "modulate", Color.WHITE, 0.6)

func runtime_error(node_id: String, message: String) -> void:
	_problems.add_item("⛔  Runtime: " + message)
	_problems.set_item_metadata(_problems.item_count - 1, node_id)
	_problems.set_item_custom_fg_color(_problems.item_count - 1, ZinoTheme.ERROR)
