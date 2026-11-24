class_name ZinoAudioStudio
extends HSplitContainer
## Audio Studio: the project's sound library (import, preview), scene music, mixer volumes and a
## live engine-sound designer driven by an RPM slider (same synthesis as the game).

var session: ZinoEditorSession
var _list: ItemList
var _player: AudioStreamPlayer
var _engine_player: AudioStreamPlayer
var _engine_voice := {}
var _engine_rpm := 900.0
var _engine_load := 0.5
var _engine_on := false
var _right: VBoxContainer

func setup(s: ZinoEditorSession) -> void:
	session = s
	ZinoAudio.ensure_buses()
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX"
	add_child(_player)
	_engine_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = ZinoAudio.MIX_RATE
	gen.buffer_length = 0.12
	_engine_player.stream = gen
	_engine_player.bus = "Engine"
	add_child(_engine_player)
	var left := ZinoUI.vbox(8)
	left.custom_minimum_size.x = 320
	left.add_child(ZinoUI.section("Sound library (Assets/Audio)"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(i): preview(_list.get_item_metadata(i)))
	left.add_child(_list)
	var h := ZinoUI.hbox(6)
	h.add_child(ZinoUI.button("Import…", _import))
	h.add_child(ZinoUI.button("Play", func():
		var sel := _list.get_selected_items()
		if not sel.is_empty():
			preview(_list.get_item_metadata(sel[0]))))
	h.add_child(ZinoUI.button("Stop", func(): _player.stop()))
	h.add_child(ZinoUI.button("Use as music", func():
		var sel := _list.get_selected_items()
		if not sel.is_empty():
			_set_audio("music", _list.get_item_metadata(sel[0]))))
	left.add_child(h)
	add_child(left)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right = ZinoUI.vbox(8)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(ZinoUI.margin(_right, 12))
	sc.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(sc)
	visibility_changed.connect(func():
		if visible:
			refresh()
		else:
			_engine_on = false
			_engine_player.stop()
			_player.stop())
	refresh()

func refresh() -> void:
	_list.clear()
	var dir := session.project_dir.path_join("Assets/Audio")
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			if f.get_extension().to_lower() in ["ogg", "wav", "mp3"]:
				_list.add_item(f)
				_list.set_item_metadata(_list.item_count - 1, "Assets/Audio/" + f)
	_rebuild_right()

func _audio() -> Dictionary:
	return session.scene().settings.get("audio", {})

func _set_audio(key: String, value) -> void:
	var st: Dictionary = session.scene().settings.duplicate(true)
	var a: Dictionary = st.get("audio", {})
	a[key] = value
	st["audio"] = a
	session.execute(ZinoSceneEdits.settings(session.scene(), st, "Audio " + key))
	_rebuild_right()

func preview(rel: String) -> String:
	var a := ZinoAudio.new()
	a.project_root = session.project_dir
	var r := a.load_stream(rel)
	a.free()
	if r.has("error"):
		ZinoAppLog.error("Audio", r.error)
		return r.error
	_player.stream = r.stream
	_player.play()
	return ""

func _import() -> void:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	fd.filters = PackedStringArray(["*.ogg, *.wav, *.mp3 ; Audio"])
	fd.use_native_dialog = true
	add_child(fd)
	fd.files_selected.connect(func(paths):
		fd.queue_free()
		for p in paths:
			var r := ZinoAssetImporter.import_file(session.project_dir, p, "Audio")
			if r.has("error"):
				ZinoAppLog.error("Audio", r.error)
			else:
				ZinoAppLog.info("Audio", "Imported " + r.rel)
		refresh())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered_ratio(0.6)

func _rebuild_right() -> void:
	for c in _right.get_children():
		c.queue_free()
	var a := _audio()
	_right.add_child(ZinoUI.heading("Audio Studio", 18))
	var mus := ZinoUI.section("Scene music")
	mus.add_child(ZinoUI.row("Track", ZinoUI.dim(str(a.get("music", "none — pick a file and press “Use as music”")), 12), 120))
	mus.add_child(ZinoUI.row("Loop", ZinoUI.check("Loop music", a.get("musicLoop", true), func(v): _set_audio("musicLoop", v)), 120))
	if a.get("music", "") != "":
		mus.add_child(ZinoUI.button("Remove music", func(): _set_audio("music", "")))
	_right.add_child(mus)
	var mix := ZinoUI.section("Mixer")
	for v in [["masterVolume", "Master"], ["musicVolume", "Music"], ["sfxVolume", "Effects"], ["engineVolume", "Engines"]]:
		var key: String = v[0]
		mix.add_child(ZinoUI.row(v[1], ZinoUI.spin(0, 200, 1, float(a.get(key, 1.0 if key == "masterVolume" else 0.8)) * 100.0, func(x): _set_audio(key, x / 100.0), " %"), 120))
	_right.add_child(mix)
	var eng := ZinoUI.section("Engine sound designer")
	eng.add_child(ZinoUI.row("Cylinders", ZinoUI.spin(1, 16, 1, float(a.get("engineCylinders", 6)), func(x): _set_audio("engineCylinders", int(x))), 120))
	eng.add_child(ZinoUI.row("Character", ZinoUI.spin(0, 1, 0.05, float(a.get("engineCharacter", 0.5)), func(x): _set_audio("engineCharacter", x)), 120))
	var rpm := HSlider.new()
	rpm.min_value = 700
	rpm.max_value = 9000
	rpm.value = _engine_rpm
	rpm.value_changed.connect(func(x): _engine_rpm = x)
	eng.add_child(ZinoUI.row("Preview RPM", rpm, 120))
	var load := HSlider.new()
	load.min_value = 0
	load.max_value = 1
	load.step = 0.01
	load.value = _engine_load
	load.value_changed.connect(func(x): _engine_load = x)
	eng.add_child(ZinoUI.row("Throttle", load, 120))
	eng.add_child(ZinoUI.toggle("Play engine preview", _engine_on, func(on):
		_engine_on = on
		if on:
			_engine_player.play()
			_engine_voice = {"phase": 0.0, "sub": 0.0, "noise": 0.0, "rpm": _engine_rpm}
		else:
			_engine_player.stop()))
	_right.add_child(eng)
	_right.add_child(ZinoUI.dim("Tyre squeal and engines are synthesised in the game from wheel slip, RPM and throttle.", 11))

func _process(_delta: float) -> void:
	if not _engine_on or not _engine_player.playing:
		return
	var pb := _engine_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var a := _audio()
	var settings := {"engineCylinders": a.get("engineCylinders", 6), "engineCharacter": a.get("engineCharacter", 0.5)}
	pb.push_buffer(ZinoAudio.render(_engine_voice, _engine_rpm, _engine_load, 0.0, settings, pb.get_frames_available(), true))
