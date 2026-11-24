extends ZinoTest
## End-to-end: a real Zino project, a real (headless) Godot editor process running the Zino Bridge
## plugin, and the real ZinoBridgeServer in this process. Nothing is mocked.

var _editor_pid := -1

func _cmd(server: ZinoBridgeServer, cmd: String, payload: Dictionary = {}) -> Dictionary:
	var box := {"done": false, "ok": false, "payload": {}, "error": {}}
	server.send_command(cmd, payload, func(ok, pl, er):
		box.done = true
		box.ok = ok
		box.payload = pl
		box.error = er)
	var t0 := Time.get_ticks_msec()
	while not box.done and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return box

func _wait_until(cond: Callable, timeout_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()

func test_editor_bridge_round_trip() -> void:
	var dir := temp_dir("e2e")
	var o := ZinoProjectService.default_options()
	o["name"] = "BridgeGame"
	o["location"] = dir
	var created := ZinoProjectService.create_project(o)
	check(created.ok, "project created")
	var root: String = created.path
	var exe := OS.get_executable_path()

	# First import builds Godot's class cache so the plugin's scripts compile.
	var out: Array = []
	var code := OS.execute(exe, ["--headless", "--path", root, "--import"], out, true)
	check_eq(code, 0, "headless import of the new project succeeds")

	var server := ZinoBridgeServer.new()
	tree.root.add_child(server)
	check_eq(server.start(root), OK, "bridge server started")
	check(FileAccess.file_exists(root.path_join(ZinoProtocol.SESSION_FILE)), "session file written")

	_editor_pid = OS.create_process(exe, ["--headless", "--editor", "--path", root])
	check(_editor_pid > 0, "Godot editor launched (pid %d)" % _editor_pid)
	var connected := await _wait_until(func(): return server.is_connected_to_editor(), 90000)
	check(connected, "Godot editor plugin connected and authenticated")
	if not connected:
		_cleanup(server, dir)
		return
	print("    connected: ", server.client_info)

	var r := await _cmd(server, ZinoProtocol.PING)
	check(r.ok and r.payload.get("pong") == true, "PING answered")

	var scene: Dictionary = ZinoFormat.load_scene_file(root.path_join("Scenes/Main.zscene")).scene
	r = await _cmd(server, ZinoProtocol.LOAD_SCENE, {"scene": scene, "sceneName": "Main"})
	check(r.ok, "LOAD_SCENE ok: %s" % str(r.error))
	check_eq(int(r.payload.get("entityCount", 0)), scene["entities"].size(), "all entities built in the Godot editor")

	r = await _cmd(server, ZinoProtocol.GET_INFO)
	check(r.ok and r.payload.get("editedScene") == "res://Worlds/Main.tscn", "Godot editor has the Zino scene open (%s)" % str(r.payload.get("editedScene")))

	var cube := ZinoEntities.primitive("cube", "Bridge Cube", Color(0.1, 0.4, 0.9))
	r = await _cmd(server, ZinoProtocol.CREATE_OBJECT, {"entity": cube})
	check(r.ok, "CREATE_OBJECT ok: %s" % str(r.error))
	r = await _cmd(server, ZinoProtocol.MOVE_OBJECT, {"id": cube["id"], "position": [5.0, 1.0, -3.0]})
	check(r.ok, "MOVE_OBJECT ok")
	r = await _cmd(server, ZinoProtocol.ROTATE_OBJECT, {"id": cube["id"], "rotation": [0.0, 30.0, 0.0]})
	check(r.ok, "ROTATE_OBJECT ok")
	r = await _cmd(server, ZinoProtocol.SCALE_OBJECT, {"id": cube["id"], "scale": [2.0, 1.0, 2.0]})
	check(r.ok, "SCALE_OBJECT ok")
	r = await _cmd(server, ZinoProtocol.ASSIGN_MATERIAL, {"id": cube["id"], "material": {"preset": "metal", "color": [0.9, 0.8, 0.2, 1.0]}})
	check(r.ok, "ASSIGN_MATERIAL ok")
	r = await _cmd(server, ZinoProtocol.SELECT_OBJECT, {"ids": [cube["id"]]})
	check(r.ok and int(r.payload.get("selected", 0)) == 1, "SELECT_OBJECT selected the node")
	var renamed := cube.duplicate(true)
	renamed["name"] = "Renamed Cube"
	renamed["transform"]["position"] = [5.0, 1.0, -3.0]
	r = await _cmd(server, ZinoProtocol.UPDATE_OBJECT, {"entity": renamed})
	check(r.ok, "UPDATE_OBJECT ok")
	var temp := ZinoEntities.primitive("sphere", "Temp Sphere")
	await _cmd(server, ZinoProtocol.CREATE_OBJECT, {"entity": temp})
	r = await _cmd(server, ZinoProtocol.DELETE_OBJECT, {"ids": [temp["id"]]})
	check(r.ok and r.payload.get("deleted", []).has(temp["id"]), "DELETE_OBJECT ok")

	# Security: the plugin must refuse unknown commands and malformed payloads.
	r = await _cmd(server, "RUN_SHELL", {"cmd": "calc.exe"})
	check(not r.ok and r.error.get("code") == ZinoProtocol.ERR_UNKNOWN_COMMAND, "unknown command refused by the plugin")
	r = await _cmd(server, ZinoProtocol.MOVE_OBJECT, {"id": "../x", "position": [0, 0, 0]})
	check(not r.ok and r.error.get("code") == ZinoProtocol.ERR_INVALID_PAYLOAD, "invalid payload refused by the plugin")
	r = await _cmd(server, ZinoProtocol.IMPORT_ASSET, {"path": "../../secret.txt"})
	check(not r.ok, "path traversal refused")

	r = await _cmd(server, ZinoProtocol.SAVE_SCENE, {})
	check(r.ok, "SAVE_SCENE ok: %s" % str(r.error))
	var tscn_path := root.path_join("Worlds/Main.tscn")
	check(FileAccess.file_exists(tscn_path), "Godot scene file written")
	var tscn := FileAccess.get_file_as_string(tscn_path)
	check(tscn.contains("Renamed Cube"), "saved Godot scene contains the created + renamed object")
	check(not tscn.contains("Temp Sphere"), "deleted object is not in the saved scene")
	check(tscn.contains("Player Car") and tscn.contains("Circuit Road"), "saved scene contains the racing test scene")
	check(tscn.contains("zino_vehicle.gd"), "vehicle keeps its Zino script")

	# Godot -> Zino: an event arrives when selection changes in the Godot editor (triggered via the plugin).
	var events: Array = []
	server.event_received.connect(func(n, p): events.append([n, p]))
	await _cmd(server, ZinoProtocol.SELECT_OBJECT, {"ids": []})
	await _wait_until(func(): return false, 600)
	# SELECT_OBJECT from Zino is not echoed back (would cause feedback loops).
	check(not events.any(func(ev): return ev[0] == ZinoProtocol.EV_SELECTION_CHANGED), "commands from Zino are not echoed back as events")

	_cleanup(server, dir)

func test_bad_token_is_rejected() -> void:
	var dir := temp_dir("tok")
	var server := ZinoBridgeServer.new()
	tree.root.add_child(server)
	DirAccess.make_dir_recursive_absolute(dir.path_join("Cache"))
	check_eq(server.start(dir), OK, "server started")
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % server.port)
	var sent := false
	var closed := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not sent:
			ws.send_text(ZinoProtocol.encode({"type": "hello", "protocol": 1, "token": "0".repeat(64), "client": {}}))
			sent = true
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			closed = true
			break
		await tree.process_frame
	check(sent, "client reached the server")
	check(closed, "server closed the connection with a wrong token")
	check(not server.is_connected_to_editor(), "server did not accept the client")
	# A client that never says hello is dropped after the timeout.
	var idle := WebSocketPeer.new()
	idle.connect_to_url("ws://127.0.0.1:%d" % server.port)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000 and idle.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		idle.poll()
		await tree.process_frame
	check_eq(idle.get_ready_state(), WebSocketPeer.STATE_CLOSED, "silent client dropped after the hello timeout")
	server.stop()
	check(not FileAccess.file_exists(dir.path_join(ZinoProtocol.SESSION_FILE)), "session file removed on stop")
	server.queue_free()
	remove_dir_recursive(dir)

func _cleanup(server: ZinoBridgeServer, dir: String) -> void:
	server.stop()
	server.queue_free()
	if _editor_pid > 0:
		OS.kill(_editor_pid)
		_editor_pid = -1
	OS.delay_msec(500)
	remove_dir_recursive(dir)
