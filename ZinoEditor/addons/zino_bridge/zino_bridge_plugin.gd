@tool
extends EditorPlugin
## Zino Bridge — Godot editor side.
##
## When the open Godot project is a Zino project (has project.zino) this plugin looks for the
## session file written by a running Zino Editor (Cache/zino_bridge_session.json), connects to it
## over a loopback WebSocket, authenticates with the session token, and then executes validated
## commands against the Godot editor: building the Zino scene as a real Godot scene, mirroring
## object edits, selection, saving and playtesting. Edits made here (moving nodes, selecting) are
## sent back to the Zino Editor as events.

const Handlers := preload("res://addons/zino_bridge/zino_bridge_handlers.gd")
const RETRY_MS := 1500
const TRANSFORM_POLL_MS := 200

var _ws: WebSocketPeer
var _state := "idle"             # idle, connecting, handshake, connected
var _next_attempt := 0
var _session: Dictionary = {}
var _handlers: RefCounted
var _last_poll := 0
var _status_label: Label
var _was_playing := false

func _enter_tree() -> void:
	if not FileAccess.file_exists("res://project.zino"):
		return
	_handlers = Handlers.new(self)
	_status_label = Label.new()
	_status_label.text = "Zino: waiting"
	_status_label.tooltip_text = "Zino Bridge connection status"
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _status_label)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	_log("Zino Bridge enabled; waiting for the Zino Editor.")

func _exit_tree() -> void:
	if _ws:
		_ws.close(1000, "plugin disabled")
		_ws = null
	if _status_label:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _status_label)
		_status_label.queue_free()
	var sel := EditorInterface.get_selection()
	if sel.selection_changed.is_connected(_on_selection_changed):
		sel.selection_changed.disconnect(_on_selection_changed)

func _process(_delta: float) -> void:
	if _handlers == null:
		return
	match _state:
		"idle":
			if Time.get_ticks_msec() >= _next_attempt:
				_try_connect()
		"connecting", "handshake", "connected":
			_poll()
	if _state == "connected":
		var now := Time.get_ticks_msec()
		if now - _last_poll >= TRANSFORM_POLL_MS:
			_last_poll = now
			var changed: Array = _handlers.collect_transform_changes()
			if not changed.is_empty():
				send_event(ZinoProtocol.EV_TRANSFORM_CHANGED, {"items": changed})
		var playing := EditorInterface.is_playing_scene()
		if playing != _was_playing:
			_was_playing = playing
			send_event(ZinoProtocol.EV_PLAYTEST_STATE, {"playing": playing})

func _try_connect() -> void:
	_next_attempt = Time.get_ticks_msec() + RETRY_MS
	var path := ProjectSettings.globalize_path("res://").path_join(ZinoProtocol.SESSION_FILE)
	if not FileAccess.file_exists(path):
		_set_status("Zino: waiting for Zino Editor")
		return
	var r := ZinoFormat.read_json_file(path)
	if not r.ok or not (r.data is Dictionary):
		return
	var s: Dictionary = r.data
	if int(s.get("protocol", 0)) != ZinoProtocol.VERSION or str(s.get("host", "")) != "127.0.0.1":
		_set_status("Zino: incompatible session file")
		return
	var port := int(s.get("port", 0))
	if port <= 0 or port > 65535:
		return
	_session = s
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = ZinoProtocol.MAX_MESSAGE_BYTES
	_ws.outbound_buffer_size = ZinoProtocol.MAX_MESSAGE_BYTES
	_ws.max_queued_packets = 4096
	var err := _ws.connect_to_url("ws://127.0.0.1:%d" % port)
	if err != OK:
		_ws = null
		return
	_state = "connecting"
	_set_status("Zino: connecting")

func _poll() -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_CLOSED:
		if _state == "connected":
			_log("Disconnected from the Zino Editor.")
		_ws = null
		_state = "idle"
		_set_status("Zino: disconnected")
		_next_attempt = Time.get_ticks_msec() + RETRY_MS
		return
	if st != WebSocketPeer.STATE_OPEN:
		return
	if _state == "connecting":
		var info := {"name": "Godot Editor", "godotVersion": Engine.get_version_info().string,
			"projectPath": ProjectSettings.globalize_path("res://")}
		_ws.send_text(ZinoProtocol.encode({"type": "hello", "protocol": ZinoProtocol.VERSION,
			"token": str(_session.get("token", "")), "client": info}))
		_state = "handshake"
	while _ws != null and _ws.get_available_packet_count() > 0:
		var msg := ZinoProtocol.decode(_ws.get_packet().get_string_from_utf8())
		match msg.get("type"):
			"welcome":
				_state = "connected"
				_set_status("Zino: connected")
				_log("Connected to the Zino Editor.")
			"reject":
				_log("Zino Editor rejected the connection: " + str(msg.get("reason", "")))
				_ws.close()
			"request":
				if _state != "connected":
					continue
				_handle_request(msg)
			_:
				pass

func _handle_request(msg: Dictionary) -> void:
	var id := int(msg.get("id", -1))
	var cmd = msg.get("cmd")
	var payload = msg.get("payload", {})
	var problem := ZinoProtocol.validate_request(cmd, payload)
	if problem != "":
		var code := ZinoProtocol.ERR_UNKNOWN_COMMAND if not (cmd is String and cmd in ZinoProtocol.COMMANDS) else ZinoProtocol.ERR_INVALID_PAYLOAD
		_send(ZinoProtocol.response_error(id, code, problem))
		return
	var result: Dictionary = _handlers.handle(cmd, payload)
	if result.get("ok", false):
		_send(ZinoProtocol.response_ok(id, result.get("payload", {})))
	else:
		_send(ZinoProtocol.response_error(id, result.get("code", ZinoProtocol.ERR_FAILED), result.get("message", "failed")))

func send_event(name: String, payload: Dictionary) -> void:
	if _state == "connected":
		_send(ZinoProtocol.event(name, payload))

func _send(msg: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(ZinoProtocol.encode(msg))

func _on_selection_changed() -> void:
	if _state != "connected" or _handlers.is_applying():
		return
	var ids: Array = []
	for n in EditorInterface.get_selection().get_selected_nodes():
		var id := ZinoSceneBuilder.entity_id_of(n)
		if id != "" and not id in ids:
			ids.append(id)
	var expected: Array = _handlers.last_zino_selection
	if expected != null and _same_ids(ids, expected):
		return
	_handlers.last_zino_selection = []
	send_event(ZinoProtocol.EV_SELECTION_CHANGED, {"ids": ids})

static func _same_ids(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		if not x in b:
			return false
	return true

func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text

func _log(text: String) -> void:
	print("[Zino Bridge] ", text)
