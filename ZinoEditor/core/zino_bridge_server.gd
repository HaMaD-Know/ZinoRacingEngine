class_name ZinoBridgeServer
extends Node
## Zino side of the Zino Bridge: a WebSocket server on 127.0.0.1 that the Godot editor plugin
## connects to. Security:
##  - binds to the loopback interface only, on a random free port;
##  - a fresh 256-bit token per session, written to <project>/Cache/zino_bridge_session.json;
##  - the client must send a valid `hello` with that token within 5 s or it is dropped
##    (a web page cannot read the session file, so it cannot obtain the token);
##  - one editor client at a time; message size is capped; every command is validated by the
##    receiving plugin against ZinoProtocol's whitelist before it runs.

signal status_changed(status: String)          # "stopped", "listening", "connected"
signal event_received(name: String, payload: Dictionary)
signal log_message(level: String, message: String)

var status := "stopped"
var port := 0
var token := ""
var project_dir := ""
var client_info: Dictionary = {}

var _tcp: TCPServer
var _pending: Array = []          # [{ws, since}]
var _client: WebSocketPeer = null
var _next_id := 1
var _waiting := {}                # id -> {callback, deadline, cmd}

func start(project_directory: String) -> Error:
	stop()
	project_dir = project_directory
	_tcp = TCPServer.new()
	var err := _tcp.listen(0, "127.0.0.1")
	if err != OK:
		_log("error", "Bridge could not listen on 127.0.0.1 (error %d)" % err)
		return err
	port = _tcp.get_local_port()
	token = ZinoProtocol.new_token()
	err = _write_session_file()
	if err != OK:
		_log("error", "Bridge could not write its session file (error %d)" % err)
		stop()
		return err
	_set_status("listening")
	_log("info", "Bridge listening on 127.0.0.1:%d" % port)
	return OK

func stop() -> void:
	_fail_all_waiting(ZinoProtocol.ERR_DISCONNECTED, "bridge stopped")
	if _client:
		_client.close(1001, "Zino Editor closing")
		_client = null
	for p in _pending:
		p.ws.close()
	_pending.clear()
	if _tcp:
		_tcp.stop()
		_tcp = null
	if project_dir != "":
		var f := project_dir.path_join(ZinoProtocol.SESSION_FILE)
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	port = 0
	client_info = {}
	_set_status("stopped")

func is_connected_to_editor() -> bool:
	return status == "connected"

## Sends a command. `callback(ok: bool, payload: Dictionary, error: Dictionary)` is called on the main thread.
func send_command(cmd: String, payload: Dictionary = {}, callback: Callable = Callable()) -> int:
	if not is_connected_to_editor():
		if callback.is_valid():
			callback.call(false, {}, {"code": ZinoProtocol.ERR_DISCONNECTED, "message": "Godot editor is not connected"})
		return -1
	var id := _next_id
	_next_id += 1
	_client.send_text(ZinoProtocol.encode(ZinoProtocol.request(id, cmd, payload)))
	_waiting[id] = {"callback": callback, "deadline": Time.get_ticks_msec() + ZinoProtocol.REQUEST_TIMEOUT_MS, "cmd": cmd}
	return id

func _process(_delta: float) -> void:
	if _tcp == null:
		return
	while _tcp.is_connection_available():
		var tcp := _tcp.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = ZinoProtocol.MAX_MESSAGE_BYTES
		ws.outbound_buffer_size = ZinoProtocol.MAX_MESSAGE_BYTES
		ws.max_queued_packets = 4096
		if ws.accept_stream(tcp) == OK:
			_pending.append({"ws": ws, "since": Time.get_ticks_msec()})
	_poll_pending()
	_poll_client()
	_check_timeouts()

func _poll_pending() -> void:
	var keep: Array = []
	for p in _pending:
		var ws: WebSocketPeer = p.ws
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			continue
		if Time.get_ticks_msec() - int(p.since) > ZinoProtocol.HELLO_TIMEOUT_MS:
			_log("warning", "Bridge: dropped a connection that did not authenticate in time")
			ws.close(4001, "hello timeout")
			continue
		if state == WebSocketPeer.STATE_OPEN:
			if ws.get_available_packet_count() > 0:
				var msg := ZinoProtocol.decode(ws.get_packet().get_string_from_utf8())
				if msg.get("type") == "hello" and int(msg.get("protocol", 0)) == ZinoProtocol.VERSION \
						and ZinoProtocol.tokens_equal(str(msg.get("token", "")), token):
					if _client != null:
						ws.send_text(ZinoProtocol.encode({"type": "reject", "reason": "another editor is already connected"}))
						ws.close(4009, "busy")
						continue
					_client = ws
					client_info = msg.get("client", {}) if msg.get("client") is Dictionary else {}
					ws.send_text(ZinoProtocol.encode({"type": "welcome", "protocol": ZinoProtocol.VERSION,
						"server": {"name": "Zino Editor", "version": ZinoFormat.ENGINE_VERSION}}))
					_set_status("connected")
					_log("info", "Godot editor connected (%s)" % str(client_info.get("godotVersion", "?")))
					continue
				_log("warning", "Bridge: rejected a connection with a bad handshake")
				ws.send_text(ZinoProtocol.encode({"type": "reject", "reason": "bad handshake"}))
				ws.close(4001, "bad handshake")
				continue
		keep.append(p)
	_pending = keep

func _poll_client() -> void:
	if _client == null:
		return
	_client.poll()
	var state := _client.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_log("warning", "Godot editor disconnected (code %d)" % _client.get_close_code())
		_client = null
		client_info = {}
		_fail_all_waiting(ZinoProtocol.ERR_DISCONNECTED, "Godot editor disconnected")
		_set_status("listening" if _tcp != null else "stopped")
		return
	while _client != null and _client.get_available_packet_count() > 0:
		var msg := ZinoProtocol.decode(_client.get_packet().get_string_from_utf8())
		match msg.get("type"):
			"response":
				var id := int(msg.get("id", -1))
				if _waiting.has(id):
					var w: Dictionary = _waiting[id]
					_waiting.erase(id)
					if w.callback.is_valid():
						w.callback.call(msg.get("ok", false) == true, msg.get("payload", {}) if msg.get("payload") is Dictionary else {}, msg.get("error", {}) if msg.get("error") is Dictionary else {})
			"event":
				var name := str(msg.get("name", ""))
				if name in ZinoProtocol.EVENTS and msg.get("payload", {}) is Dictionary:
					event_received.emit(name, msg.get("payload", {}))
				else:
					_log("warning", "Bridge: ignored unknown event '%s'" % name)
			_:
				_log("warning", "Bridge: ignored malformed message")

func _check_timeouts() -> void:
	var now := Time.get_ticks_msec()
	for id in _waiting.keys():
		var w: Dictionary = _waiting[id]
		if now > int(w.deadline):
			_waiting.erase(id)
			_log("error", "Bridge: %s timed out" % w.cmd)
			if w.callback.is_valid():
				w.callback.call(false, {}, {"code": ZinoProtocol.ERR_TIMEOUT, "message": w.cmd + " timed out"})

func _fail_all_waiting(code: String, message: String) -> void:
	var items := _waiting.duplicate()
	_waiting.clear()
	for id in items:
		var w: Dictionary = items[id]
		if w.callback.is_valid():
			w.callback.call(false, {}, {"code": code, "message": message})

func _write_session_file() -> Error:
	var path := project_dir.path_join(ZinoProtocol.SESSION_FILE)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var data := {"protocol": ZinoProtocol.VERSION, "host": "127.0.0.1", "port": port, "token": token,
		"pid": OS.get_process_id(), "created": Time.get_datetime_string_from_system(true) + "Z"}
	return ZinoFormat.write_text_atomic(path, ZinoFormat.to_json(data), false)

func _set_status(s: String) -> void:
	if status != s:
		status = s
		status_changed.emit(s)

func _log(level: String, message: String) -> void:
	log_message.emit(level, message)

func _exit_tree() -> void:
	stop()
