class_name ZinoMakeGameWizard
extends Window
## "Make a Game": five friendly steps with big cards. Produces a complete, playable racing game and
## opens it in Simple mode with the Coach. Everything it creates stays fully editable in Advanced mode.

var app: ZinoApp
var choices := ZinoQuickGame.default_choices()
var _step := 0
var _body: VBoxContainer
var _title: Label
var _dots: HBoxContainer
var _back: Button
var _next: Button

const STEPS := ["What kind of game?", "Pick your car", "Choose a track", "Set the scene", "Final touches"]

func _ready() -> void:
	title = "Make a Game"
	theme = app.app_theme
	exclusive = true
	transient = true
	min_size = Vector2i(980, 680)
	close_requested.connect(queue_free)
	var loc: String = app.settings.get_value("defaultLocation", "")
	if loc == "" or not DirAccess.dir_exists_absolute(loc):
		loc = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	choices.location = loc
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", ZinoTheme.box(ZinoTheme.PANEL, 0))
	add_child(bg)
	var m := ZinoUI.margin(ZinoUI.vbox(14), 28)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var v: VBoxContainer = m.get_child(0)
	_dots = ZinoUI.hbox(6)
	v.add_child(_dots)
	_title = ZinoUI.heading("", 26)
	v.add_child(_title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = ZinoUI.vbox(12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	v.add_child(sc)
	var nav := ZinoUI.hbox(10)
	_back = ZinoUI.button("  ‹ Back  ", func(): _go(_step - 1))
	nav.add_child(_back)
	nav.add_child(ZinoUI.spacer())
	nav.add_child(ZinoUI.button("  Cancel  ", queue_free))
	_next = ZinoUI.accent_button("  Next ›  ", func(): _go(_step + 1))
	nav.add_child(_next)
	v.add_child(nav)
	_show()

func _steps() -> Array:
	# The track step is skipped for games without a circuit.
	return [0, 1, 2, 3, 4] if ZinoQuickGame.uses_track(choices.gameType) else [0, 1, 3, 4]

func _go(to: int) -> void:
	var steps := _steps()
	var i := steps.find(_step)
	var target := to
	if to > _step:
		target = steps[mini(i + 1, steps.size() - 1)] if i + 1 < steps.size() else -1
	elif to < _step:
		target = steps[maxi(i - 1, 0)]
	if target == -1:
		_create()
		return
	_step = target
	_show()

func _show() -> void:
	for c in _body.get_children():
		c.queue_free()
	for c in _dots.get_children():
		c.queue_free()
	var steps := _steps()
	for s in steps:
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(36, 5)
		d.color = ZinoTheme.ACCENT if s <= _step else ZinoTheme.BORDER
		_dots.add_child(d)
	_title.text = STEPS[_step]
	_back.disabled = _step == 0
	_next.text = "  Create & Play ▶  " if _step == steps.back() else "  Next ›  "
	match _step:
		0: _cards(ZinoQuickGame.GAME_TYPES, "gameType", 4)
		1:
			_cards(ZinoQuickGame.CARS.map(func(c): return {"id": c.id, "name": c.name, "desc": c.desc, "icon": "🚗" if c.id != "kart" else "🏎"}), "car", 3)
			_body.add_child(ZinoUI.label("Paint colour", 15, ZinoTheme.TEXT))
			var row := ZinoUI.hbox(10)
			for hex in ZinoQuickGame.COLORS:
				var b := Button.new()
				b.custom_minimum_size = Vector2(54, 54)
				b.focus_mode = Control.FOCUS_NONE
				var sel: bool = hex == choices.color
				b.add_theme_stylebox_override("normal", ZinoTheme.box(Color.html(hex), 27, ZinoTheme.ACCENT if sel else ZinoTheme.BORDER, 4 if sel else 1, 0))
				b.add_theme_stylebox_override("hover", ZinoTheme.box(Color.html(hex).lightened(0.1), 27, ZinoTheme.ACCENT, 3, 0))
				b.pressed.connect(func():
					choices.color = hex
					_show())
				row.add_child(b)
			_body.add_child(row)
		2: _cards(ZinoQuickGame.TRACKS.map(func(t): return {"id": t.id, "name": t.name, "desc": t.desc, "icon": "🛣"}), "track", 3)
		3: _cards(ZinoQuickGame.WORLDS.map(func(w): return {"id": w.id, "name": w.name, "desc": "%02d:00 · %s" % [int(w.hours), w.weather], "icon": {"day": "☀️", "sunset": "🌇", "night": "🌙", "rain": "🌧", "storm": "⛈", "fog": "🌫"}.get(w.id, "☀️")}), "world", 3)
		4: _details()

func _cards(items: Array, key: String, columns: int) -> void:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	for it in items:
		var sel: bool = choices[key] == it.id
		var b := Button.new()
		b.custom_minimum_size = Vector2(210, 130)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", ZinoTheme.box(Color(ZinoTheme.ACCENT, 0.14) if sel else ZinoTheme.PANEL_2, 14, ZinoTheme.ACCENT if sel else ZinoTheme.BORDER, 2 if sel else 1, 14))
		b.add_theme_stylebox_override("hover", ZinoTheme.box(Color(ZinoTheme.ACCENT, 0.1), 14, ZinoTheme.ACCENT, 2, 14))
		var v := ZinoUI.vbox(4)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 16; v.offset_top = 12; v.offset_right = -16
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for lab in [ZinoUI.label(str(it.get("icon", "")), 30, ZinoTheme.TEXT), ZinoUI.label(str(it.name), 17, ZinoTheme.TEXT), ZinoUI.dim(str(it.desc), 12)]:
			lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(lab)
		b.add_child(v)
		b.pressed.connect(func():
			choices[key] = it.id
			_show())
		g.add_child(b)
	_body.add_child(g)

func _details() -> void:
	var name_e := LineEdit.new()
	name_e.placeholder_text = "My %s" % ZinoQuickGame.find(ZinoQuickGame.GAME_TYPES, choices.gameType).name
	name_e.text = choices.name
	name_e.text_changed.connect(func(t): choices.name = t)
	_body.add_child(ZinoUI.row("Game name", name_e, 160))
	var loc := ZinoUI.hbox(6)
	var loc_e := LineEdit.new()
	loc_e.text = choices.location
	loc_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loc_e.text_changed.connect(func(t): choices.location = t)
	loc.add_child(loc_e)
	loc.add_child(ZinoUI.button("Browse…", func(): app.pick_folder("Where to save your game", choices.location, func(p):
		choices.location = p
		loc_e.text = p)))
	_body.add_child(ZinoUI.row("Save in", loc, 160))
	if choices.gameType in ["circuit", "elimination", "drift", "kart", "timeTrial"]:
		_body.add_child(ZinoUI.row("Laps", ZinoUI.spin(1, 20, 1, float(choices.laps), func(x): choices.laps = int(x)), 160))
	if choices.gameType in ["circuit", "elimination", "drift", "kart", "drag"]:
		_body.add_child(ZinoUI.row("Opponents", ZinoUI.spin(0, 11, 1, float(choices.opponents), func(x): choices.opponents = int(x)), 160))
		_body.add_child(ZinoUI.row("Difficulty", ZinoUI.option([["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"], ["pro", "Pro"]], choices.difficulty, func(x): choices.difficulty = x), 160))
	var summary := ZinoUI.dim("You'll get a complete game: %s, %s, %s. Press Play to drive it right away — then change anything you like." % [
		ZinoQuickGame.find(ZinoQuickGame.GAME_TYPES, choices.gameType).name, ZinoQuickGame.find(ZinoQuickGame.CARS, choices.car).name,
		ZinoQuickGame.find(ZinoQuickGame.WORLDS, choices.world).name], 13)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(summary)

func _create() -> void:
	var c := choices.duplicate()
	if str(c.name).strip_edges() == "":
		c.name = "My %s" % str(ZinoQuickGame.find(ZinoQuickGame.GAME_TYPES, c.gameType).name)
	var base: String = str(c.name).strip_edges()
	var n := 2
	while DirAccess.dir_exists_absolute(str(c.location).path_join(c.name)):
		c.name = "%s %d" % [base, n]
		n += 1
	var r := ZinoQuickGame.create(c)
	if not r.ok:
		app.show_message("Could not make the game", r.error)
		return
	app.settings.set_value("defaultLocation", c.location)
	queue_free()
	app.open_project(r.path)
