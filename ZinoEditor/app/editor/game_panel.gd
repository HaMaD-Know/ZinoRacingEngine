class_name ZinoGamePanel
extends ScrollContainer
## The "Game" tab: the settings people change most, in plain language and big controls.
## Every change is a normal undoable edit of the scene, so Advanced mode sees exactly the same data.

var session: ZinoEditorSession
var on_play: Callable
var _box: VBoxContainer
var _pending := false

func setup(s: ZinoEditorSession, play: Callable) -> void:
	session = s
	on_play = play
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = ZinoUI.vbox(10)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(ZinoUI.margin(_box, 12))
	get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session.scene_changed.connect(func(_c): _queue())
	session.state_changed.connect(_queue)
	rebuild()

func _queue() -> void:
	if _pending:
		return
	_pending = true
	(func():
		_pending = false
		rebuild()).call_deferred()

func _settings() -> Dictionary:
	return session.scene().settings

func _set_settings(mutate: Callable, label: String) -> void:
	var st: Dictionary = _settings().duplicate(true)
	mutate.call(st)
	session.execute(ZinoSceneEdits.settings(session.scene(), st, label))

func _player() -> Dictionary:
	for e in session.scene().entities:
		if e.type == ZinoEntities.TYPE_VEHICLE and e.vehicle.get("playerControlled", true):
			return e
	return {}

func _camera() -> Dictionary:
	for e in session.scene().entities:
		if e.type == ZinoEntities.TYPE_CAMERA and e.camera.get("mode") == "chase":
			return e
	return {}

func _choice_row(items: Array, current, on_pick: Callable) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	for it in items:
		var b := ZinoUI.toggle(str(it[1]), it[0] == current, func(_on): on_pick.call(it[0]))
		b.custom_minimum_size = Vector2(0, 34)
		f.add_child(b)
	return f

func rebuild() -> void:
	if _box == null:
		return
	for c in _box.get_children():
		c.queue_free()
	var playing := session.mode != "edit"
	var play := ZinoUI.accent_button("  ▶  Play your game  " if not playing else "  Playing… (press Esc or Stop)  ", func(): on_play.call())
	play.custom_minimum_size.y = 48
	play.disabled = playing
	_box.add_child(play)
	_box.add_child(ZinoUI.dim("Drive with W/A/S/D or the arrow keys · Space handbrake · N nitro · C camera · R reset", 11))
	if playing:
		return
	var st := _settings()
	var race: Dictionary = st.get("race", {})

	if race.get("enabled", true):
		var rs := ZinoUI.section("Race")
		rs.add_child(_choice_row([["circuit", "Circuit"], ["timeTrial", "Time trial"], ["elimination", "Elimination"], ["sprint", "Sprint"]], race.get("mode", "auto"), func(v): _set_settings(func(x): x.race.mode = v, "Race Type")))
		rs.add_child(ZinoUI.row("Laps", ZinoUI.spin(1, 50, 1, float(race.get("laps", 3)), func(v): _set_settings(func(x): x.race.laps = int(v), "Laps")), 110))
		rs.add_child(ZinoUI.row("Opponents", ZinoUI.spin(0, 11, 1, float(race.get("aiOpponents", 3)), func(v): _set_settings(func(x): x.race.aiOpponents = int(v), "Opponents")), 110))
		var diff := 0.7
		diff = float(race.get("aiDifficulty", 0.7))
		var cur := "easy" if diff < 0.55 else ("normal" if diff < 0.8 else ("hard" if diff < 0.95 else "pro"))
		rs.add_child(ZinoUI.label("Opponent skill", 13, ZinoTheme.TEXT_DIM))
		rs.add_child(_choice_row([["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"], ["pro", "Pro"]], cur, func(v): _set_settings(func(x): x.race.aiDifficulty = ZinoQuickGame.DIFFICULTY[v], "Difficulty")))
		_box.add_child(rs)

	var car := _player()
	if not car.is_empty():
		var cs := ZinoUI.section("Your car")
		var cid: String = car.id
		var colors := HFlowContainer.new()
		colors.add_theme_constant_override("h_separation", 6)
		var cur_col := ZinoFormat.col(car.vehicle.spec.get("bodyColor")).to_html(false)
		for hex in ZinoQuickGame.COLORS:
			var b := Button.new()
			b.custom_minimum_size = Vector2(34, 34)
			b.focus_mode = Control.FOCUS_NONE
			var sel: bool = Color.html(hex).to_html(false) == cur_col
			b.add_theme_stylebox_override("normal", ZinoTheme.box(Color.html(hex), 17, ZinoTheme.ACCENT if sel else ZinoTheme.BORDER, 3 if sel else 1, 0))
			b.add_theme_stylebox_override("hover", ZinoTheme.box(Color.html(hex), 17, ZinoTheme.ACCENT, 2, 0))
			b.pressed.connect(func(): session.execute(ZinoSceneEdits.modify(session.scene(), [cid], func(x): x.vehicle.spec.bodyColor = ZinoFormat.arr_col(Color.html(hex)), "Car Colour")))
			colors.add_child(b)
		colors.add_child(ZinoUI.color_button(ZinoFormat.col(car.vehicle.spec.get("bodyColor")), func(c): session.execute(ZinoSceneEdits.modify(session.scene(), [cid], func(x): x.vehicle.spec.bodyColor = ZinoFormat.arr_col(c), "Car Colour"))))
		cs.add_child(colors)
		cs.add_child(ZinoUI.label("Handling", 13, ZinoTheme.TEXT_DIM))
		cs.add_child(_choice_row(ZinoQuickGame.CARS.map(func(c): return [c.profile, c.name]), car.vehicle.spec.get("profile", "arcade"), func(p):
			session.execute(ZinoSceneEdits.modify(session.scene(), [cid], func(x):
				var keep := {"bodyColor": x.vehicle.spec.get("bodyColor"), "model": x.vehicle.spec.get("model")}
				var ns := ZinoEntities.default_vehicle_spec(p)
				for k in keep:
					if keep[k] != null:
						ns[k] = keep[k]
				x.vehicle.spec = ns, "Car Handling"))))
		var cam := _camera()
		if not cam.is_empty():
			var camid: String = cam.id
			cs.add_child(ZinoUI.label("Camera", 13, ZinoTheme.TEXT_DIM))
			cs.add_child(_choice_row([["chase", "Chase"], ["closeChase", "Close"], ["hood", "Hood"], ["cockpit", "Cockpit"], ["bumper", "Bumper"]], cam.camera.get("startMode", "chase"), func(m):
				session.execute(ZinoSceneEdits.modify(session.scene(), [camid], func(x): x.camera["startMode"] = m, "Camera View"))))
		cs.add_child(ZinoUI.dim("Want your own 3D car? Open the Car tab and press Import Car Model.", 11))
		_box.add_child(cs)

	var ws := ZinoUI.section("World")
	var hours := float(st.get("timeOfDay", 14.0))
	var tcur := "morning" if hours < 11.0 else ("day" if hours < 17.5 else ("sunset" if hours < 21.0 else "night"))
	ws.add_child(ZinoUI.label("Time of day", 13, ZinoTheme.TEXT_DIM))
	ws.add_child(_choice_row([["morning", "Morning"], ["day", "Day"], ["sunset", "Sunset"], ["night", "Night"]], tcur, func(v):
		_set_settings(func(x): x.timeOfDay = {"morning": 8.5, "day": 13.0, "sunset": 19.3, "night": 23.0}[v], "Time of Day")))
	ws.add_child(ZinoUI.label("Weather", 13, ZinoTheme.TEXT_DIM))
	ws.add_child(_choice_row([["clear", "Clear"], ["cloudy", "Cloudy"], ["rain", "Rain"], ["storm", "Storm"], ["fog", "Fog"]], st.get("weather", "clear"), func(v): _set_settings(func(x): x.weather = v, "Weather")))
	var traffic: Dictionary = st.get("traffic", {})
	if not race.get("enabled", true) or traffic.get("count", 0) > 0:
		ws.add_child(ZinoUI.row("Traffic cars", ZinoUI.spin(0, 24, 1, float(traffic.get("count", 0)), func(v): _set_settings(func(x):
			var t: Dictionary = x.get("traffic", {"speedKmh": 55.0})
			t["count"] = int(v)
			x["traffic"] = t, "Traffic")), 110))
	_box.add_child(ws)

	var more := ZinoUI.section("Do more")
	for tip in [["Add game rules with ready-made recipes", "Logic"], ["Reshape or generate a new track", "Track"], ["Get free textures and skies", "Store"], ["Export for iPhone or Windows", "Publish"]]:
		more.add_child(ZinoUI.dim("• %s → %s tab" % [tip[0], tip[1]], 12))
	_box.add_child(more)
