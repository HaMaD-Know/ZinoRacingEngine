class_name ZinoContentPanel
extends VBoxContainer
## Content browser: the project's folders and files (source assets stay untouched).

signal scene_open_requested(rel: String)

const SKIP := [".godot", ".git", "addons"]
const MAX_ENTRIES := 3000

var session: ZinoEditorSession
var _tree: Tree
var _count := 0

func setup(s: ZinoEditorSession) -> void:
	session = s
	add_theme_constant_override("separation", 4)
	var bar := ZinoUI.hbox(6)
	bar.add_child(ZinoUI.button("Refresh", refresh))
	bar.add_child(ZinoUI.button("Show in Explorer", func():
		var p := _selected_path()
		OS.shell_show_in_file_manager(p if p != "" else session.project_dir)))
	bar.add_child(ZinoUI.button("Open Assets Folder", func(): OS.shell_open(session.project_dir.path_join("Assets"))))
	bar.add_child(ZinoUI.spacer())
	bar.add_child(ZinoUI.dim("Drop files into Assets/ in Explorer, then Refresh. Originals are never modified.", 12))
	add_child(bar)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.columns = 2
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 110)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_activated.connect(_on_activated)
	add_child(_tree)
	refresh()

func refresh() -> void:
	_tree.clear()
	_count = 0
	var root := _tree.create_item()
	_scan(root, session.project_dir, 0)
	if _count >= MAX_ENTRIES:
		var more := _tree.create_item(root)
		more.set_text(0, "… more files not shown")

func _scan(parent: TreeItem, dir: String, depth: int) -> void:
	var d := DirAccess.open(dir)
	if d == null or depth > 6:
		return
	var dirs := Array(d.get_directories())
	dirs.sort()
	for sub in dirs:
		if sub in SKIP or _count >= MAX_ENTRIES:
			continue
		var it := _tree.create_item(parent)
		it.set_text(0, "▸ " + sub)
		it.set_metadata(0, dir.path_join(sub))
		it.set_custom_color(0, ZinoTheme.TEXT)
		it.collapsed = depth > 0
		_count += 1
		_scan(it, dir.path_join(sub), depth + 1)
	var files := Array(d.get_files())
	files.sort()
	for f in files:
		if f.ends_with(".import") or f.ends_with(".uid") or f.ends_with(".tmp") or f == ".gitkeep" or _count >= MAX_ENTRIES:
			continue
		var it := _tree.create_item(parent)
		it.set_text(0, "   " + f)
		it.set_metadata(0, dir.path_join(f))
		it.set_text(1, _size(FileAccess.get_size(dir.path_join(f))))
		it.set_custom_color(0, ZinoTheme.ACCENT.lightened(0.3) if f.ends_with(".zscene") else ZinoTheme.TEXT_DIM.lightened(0.2))
		_count += 1

func _selected_path() -> String:
	var it := _tree.get_selected()
	return it.get_metadata(0) if it else ""

func _on_activated() -> void:
	var p := _selected_path()
	if p == "" or DirAccess.dir_exists_absolute(p):
		return
	if p.ends_with(".zscene"):
		scene_open_requested.emit("Scenes/" + p.get_file())
		return
	OS.shell_open(p)

static func _size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%.1f MB" % (bytes / 1048576.0)
