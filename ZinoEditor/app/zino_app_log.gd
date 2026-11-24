class_name ZinoAppLog
extends RefCounted
## Application log shared by every editor panel. Also mirrored to user://logs/zino_editor.log.

static var entries: Array = []             # [{time, level, channel, message}]
static var _listeners: Array[Callable] = []
static var _file: FileAccess
const MAX_ENTRIES := 5000

static func listen(cb: Callable) -> void:
	_listeners.append(cb)

static func unlisten(cb: Callable) -> void:
	_listeners.erase(cb)

static func info(channel: String, message: String) -> void: write("info", channel, message)
static func warn(channel: String, message: String) -> void: write("warning", channel, message)
static func error(channel: String, message: String) -> void: write("error", channel, message)

static func write(level: String, channel: String, message: String) -> void:
	var e := {"time": Time.get_time_string_from_system(), "level": level, "channel": channel, "message": message}
	entries.append(e)
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)
	if _file == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
		_file = FileAccess.open("user://logs/zino_editor.log", FileAccess.WRITE)
	if _file:
		_file.store_line("[%s] %-7s %s: %s" % [e.time, level, channel, message])
		_file.flush()
	if level == "error":
		printerr("[Zino] %s: %s" % [channel, message])
	else:
		print("[Zino] %s: %s" % [channel, message])
	for cb in _listeners.duplicate():
		if cb.is_valid():
			cb.call(e)
