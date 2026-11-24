class_name ZinoConsolePanel
extends VBoxContainer
## Log viewer. With `channel_filter` set it shows only that channel (used for the Bridge tab).

var channel_filter := ""
var _text: RichTextLabel
var _search: LineEdit
var _show := {"info": true, "warning": true, "error": true}
var _listener: Callable

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var bar := ZinoUI.hbox(6)
	for lv in [["info", "Info"], ["warning", "Warnings"], ["error", "Errors"]]:
		bar.add_child(ZinoUI.toggle(lv[1], true, func(on):
			_show[lv[0]] = on
			_rebuild()))
	_search = LineEdit.new()
	_search.placeholder_text = "Search log…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _rebuild())
	bar.add_child(_search)
	bar.add_child(ZinoUI.button("Clear", func():
		ZinoAppLog.entries.clear()
		_rebuild()))
	bar.add_child(ZinoUI.button("Copy", func(): DisplayServer.clipboard_set(_plain())))
	add_child(bar)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.selection_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.add_theme_stylebox_override("normal", ZinoTheme.box(ZinoTheme.BG_2, 4, ZinoTheme.BORDER, 1, 8))
	add_child(_text)
	_listener = func(e): if _accept(e): _text.append_text(_format(e) + "\n")
	ZinoAppLog.listen(_listener)
	_rebuild()

func _exit_tree() -> void:
	ZinoAppLog.unlisten(_listener)

func _accept(e: Dictionary) -> bool:
	if channel_filter != "" and e.channel != channel_filter:
		return false
	if not _show.get(e.level, true):
		return false
	var q := _search.text.strip_edges().to_lower() if _search else ""
	return q == "" or str(e.message).to_lower().contains(q) or str(e.channel).to_lower().contains(q)

func _format(e: Dictionary) -> String:
	var c: Color = {"warning": ZinoTheme.WARN, "error": ZinoTheme.ERROR}.get(e.level, ZinoTheme.TEXT)
	return "[color=#8e8e93]%s[/color]  [color=#%s]%s[/color]  [color=#%s]%s[/color]" % [
		e.time, ZinoTheme.INFO.to_html(false), str(e.channel).rpad(9), c.to_html(false), str(e.message).replace("[", "[lb]")]

func _rebuild() -> void:
	if _text == null:
		return
	_text.clear()
	for e in ZinoAppLog.entries:
		if _accept(e):
			_text.append_text(_format(e) + "\n")

func _plain() -> String:
	var lines := PackedStringArray()
	for e in ZinoAppLog.entries:
		if _accept(e):
			lines.append("%s %s %s: %s" % [e.time, e.level, e.channel, e.message])
	return "\n".join(lines)
