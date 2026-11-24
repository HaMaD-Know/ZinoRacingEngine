class_name ZinoHierarchyPanel
extends VBoxContainer
## Scene hierarchy: nested entity tree with multi-select, rename, filter, context menu and
## drag-and-drop reparenting.

const TYPE_TAGS := {
	"empty": "◇", "primitive": "■", "light": "☀", "camera": "◉", "vehicle": "🏎", "road": "≡",
	"checkpoint": "⚑", "startFinish": "🏁", "spawnPoint": "➤",
}
const TYPE_TINTS := {
	"vehicle": "orange", "road": "gray", "light": "yellow", "camera": "blue",
	"checkpoint": "green", "startFinish": "red", "spawnPoint": "teal",
}

var session: ZinoEditorSession
var viewport_panel: ZinoViewportPanel
var tree: Tree
var _filter: LineEdit
var _items := {}           # id -> TreeItem
var _syncing := false
var _menu: PopupMenu
var _collapsed := {}

func setup(s: ZinoEditorSession, vp: ZinoViewportPanel) -> void:
	session = s
	viewport_panel = vp
	add_theme_constant_override("separation", 6)
	var top := ZinoUI.hbox(4)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter objects…"
	_filter.clear_button_enabled = true
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_t): rebuild())
	top.add_child(_filter)
	add_child(top)
	tree = Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.allow_rmb_select = true
	tree.allow_reselect = true
	tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN
	tree.multi_selected.connect(func(_i, _c, _s): _on_tree_selection.call_deferred())
	tree.item_activated.connect(func(): viewport_panel.frame_selection())
	tree.item_edited.connect(_on_item_edited)
	tree.item_collapsed.connect(func(item): _collapsed[item.get_metadata(0)] = item.collapsed)
	tree.item_mouse_selected.connect(func(_pos, button):
		if button == MOUSE_BUTTON_RIGHT:
			_show_menu())
	tree.empty_clicked.connect(func(_pos, button):
		if button == MOUSE_BUTTON_LEFT:
			session.select([]))
	tree.set_drag_forwarding(_get_drag_data, _can_drop_data, _drop_data)
	add_child(tree)
	_menu = PopupMenu.new()
	for item in [["Rename", 0], ["Duplicate", 1], ["Delete", 2], ["Frame in Viewport", 3], ["Unparent", 4]]:
		_menu.add_item(item[0], item[1])
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	session.scene_changed.connect(func(_c): rebuild())
	session.selection_changed.connect(func(_ids): _sync_selection())
	rebuild()

func rebuild() -> void:
	_syncing = true
	tree.clear()
	_items.clear()
	var root := tree.create_item()
	var scene := session.scene()
	var filter := _filter.text.strip_edges().to_lower()
	if filter != "":
		for e in scene["entities"]:
			if str(e["name"]).to_lower().contains(filter) or str(e["type"]).to_lower().contains(filter):
				_make_item(root, e)
	else:
		_add_children(root, scene, null)
	_syncing = false
	_sync_selection()

func _add_children(parent_item: TreeItem, scene: Dictionary, parent_id) -> void:
	for e in ZinoFormat.children_of(scene, parent_id):
		var it := _make_item(parent_item, e)
		_add_children(it, scene, e["id"])

func _make_item(parent_item: TreeItem, e: Dictionary) -> TreeItem:
	var it := tree.create_item(parent_item)
	var type: String = e.get("type", "empty")
	it.set_text(0, "%s  %s" % [TYPE_TAGS.get(type, "•"), e["name"]])
	it.set_metadata(0, e["id"])
	it.set_tooltip_text(0, "%s  (%s)\nid: %s" % [e["name"], type, e["id"]])
	var c: Color = ZinoTheme.tint(TYPE_TINTS[type]) if TYPE_TINTS.has(type) else ZinoTheme.TEXT
	it.set_custom_color(0, c if e.get("active", true) else Color(ZinoTheme.TEXT_DIM, 0.6))
	it.collapsed = _collapsed.get(e["id"], false)
	_items[e["id"]] = it
	return it

func _sync_selection() -> void:
	_syncing = true
	tree.deselect_all()
	var first: TreeItem = null
	for id in session.selection:
		var it: TreeItem = _items.get(id)
		if it:
			var p := it.get_parent()
			while p:
				p.collapsed = false
				p = p.get_parent()
			it.select(0)
			if first == null:
				first = it
	if first:
		tree.scroll_to_item(first)
	_syncing = false

func _on_tree_selection() -> void:
	if _syncing:
		return
	var ids: Array = []
	var it := tree.get_next_selected(null)
	while it:
		ids.append(it.get_metadata(0))
		it = tree.get_next_selected(it)
	session.select(ids)

func _on_item_edited() -> void:
	var it := tree.get_edited()
	if it == null:
		return
	var id: String = it.get_metadata(0)
	var new_name := it.get_text(0).strip_edges()
	it.set_editable(0, false)
	# Strip the type tag if the user kept it.
	var parts := new_name.split("  ", false, 1)
	if parts.size() == 2 and parts[0].length() <= 2:
		new_name = parts[1]
	if new_name != "" and new_name != ZinoFormat.find_entity(session.scene(), id).get("name"):
		session.execute(ZinoSceneEdits.rename(session.scene(), id, new_name))
	else:
		rebuild()

func begin_rename() -> void:
	if session.selection.size() != 1:
		return
	var it: TreeItem = _items.get(session.selection[0])
	if it == null:
		return
	it.set_text(0, ZinoFormat.find_entity(session.scene(), session.selection[0])["name"])
	it.set_editable(0, true)
	tree.set_selected(it, 0)
	tree.edit_selected(true)

func _show_menu() -> void:
	_menu.position = Vector2i(get_global_mouse_position()) + get_window().position
	_menu.reset_size()
	_menu.popup()

func _on_menu(id: int) -> void:
	match id:
		0: begin_rename()
		1: session.duplicate_selection()
		2: session.delete_selection()
		3: viewport_panel.frame_selection()
		4: session.execute(ZinoSceneEdits.reparent(session.scene(), session.selection, null))

# --- Drag and drop reparenting --------------------------------------------------------------

func _get_drag_data(_at: Vector2):
	if session.selection.is_empty() or session.mode != "edit":
		return null
	var l := ZinoUI.label("Move %d object(s)" % session.selection.size(), 13)
	tree.set_drag_preview(l)
	return {"zino_ids": session.selection.duplicate()}

func _can_drop_data(_at: Vector2, data) -> bool:
	return data is Dictionary and data.has("zino_ids")

func _drop_data(at: Vector2, data) -> void:
	var target := tree.get_item_at_position(at)
	var section := tree.get_drop_section_at_position(at)
	var new_parent = null
	if target != null:
		var target_id: String = target.get_metadata(0)
		if section == 0:
			new_parent = target_id
		else:
			new_parent = ZinoFormat.find_entity(session.scene(), target_id).get("parentId")
	var cmd := ZinoSceneEdits.reparent(session.scene(), data["zino_ids"], new_parent)
	if cmd["slots"].is_empty():
		ZinoAppLog.warn("Hierarchy", "Cannot parent an object under itself or its children.")
		return
	session.execute(cmd)
