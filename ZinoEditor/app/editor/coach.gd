class_name ZinoCoach
extends PanelContainer
## The Coach: a short checklist in the corner of the viewport that teaches the basics by doing.
## Steps tick themselves off when the user actually does them; progress is saved in project.zino.

var editor                      # editor_screen.gd instance
var session: ZinoEditorSession
var _list: VBoxContainer
var _done := {}
var _start := {}
var _timer := 0.0

const STEPS := [
	["play", "Press ▶ Play and drive your car", "W/A/S/D to drive · Esc to stop"],
	["color", "Paint your car a new colour", "Game tab › Your car"],
	["race", "Change the laps or opponents", "Game tab › Race"],
	["recipe", "Add a game rule from a recipe", "Logic › Recipes"],
	["publish", "See how to publish your game", "Publish tab"],
]

func setup(ed) -> void:
	editor = ed
	session = ed.session
	add_theme_stylebox_override("panel", ZinoTheme.box(Color(ZinoTheme.PANEL, 0.96), 14, ZinoTheme.BORDER, 1, 14))
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -14
	offset_bottom = -40
	custom_minimum_size.x = 330
	mouse_filter = Control.MOUSE_FILTER_STOP
	var coach: Dictionary = session.manifest.get("coach", {})
	for id in coach.get("done", []):
		_done[id] = true
	_capture_start()
	_list = ZinoUI.vbox(6)
	add_child(_list)
	visible = coach.get("enabled", false) and _done.size() < STEPS.size()
	_rebuild()

func show_coach() -> void:
	session.manifest["coach"] = {"enabled": true, "done": _done.keys()}
	ZinoProjectService.save_manifest(session.project_dir, session.manifest)
	_capture_start()
	visible = true
	_rebuild()

func _capture_start() -> void:
	var car := _player()
	_start = {
		"color": car.get("vehicle", {}).get("spec", {}).get("bodyColor", []),
		"race": session.scene().settings.get("race", {}).duplicate(true),
		"blocks": _block_count(),
	}

func _player() -> Dictionary:
	for e in session.scene().entities:
		if e.type == ZinoEntities.TYPE_VEHICLE:
			return e
	return {}

func _block_count() -> int:
	return editor.block_studio.program.get("nodes", []).size() if editor.block_studio else 0

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var head := ZinoUI.hbox(6)
	head.add_child(ZinoUI.label("🎓  Coach", 16, ZinoTheme.TEXT))
	head.add_child(ZinoUI.spacer())
	head.add_child(ZinoUI.dim("%d / %d" % [_done.size(), STEPS.size()], 12))
	head.add_child(ZinoUI.button("Hide", hide_coach))
	_list.add_child(head)
	if _done.size() >= STEPS.size():
		_list.add_child(ZinoUI.label("🎉 You made and tuned a racing game!", 14, ZinoTheme.OK))
		var t := ZinoUI.dim("Next: import your own car (Car tab), generate tracks (Track tab), or switch on Advanced for every professional tool.", 12)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(t)
		return
	for s in STEPS:
		var id: String = s[0]
		var row := ZinoUI.hbox(8)
		var done: bool = _done.has(id)
		row.add_child(ZinoUI.label("✅" if done else "⬜", 14, ZinoTheme.TEXT))
		var txt := ZinoUI.vbox(0)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_child(ZinoUI.label(s[1], 13, ZinoTheme.TEXT_DIM if done else ZinoTheme.TEXT))
		if not done:
			txt.add_child(ZinoUI.dim(s[2], 11))
		row.add_child(txt)
		if not done:
			row.add_child(ZinoUI.button("Show me", func(): _show_me(id)))
		_list.add_child(row)

func _show_me(id: String) -> void:
	match id:
		"play": editor._play()
		"color", "race":
			editor.show_workspace("Scene")
			editor._right_tabs.current_tab = 0
		"recipe":
			editor.show_workspace("Blocks")
			editor.block_studio.open_recipes()
		"publish": editor.show_workspace("Build")

func hide_coach() -> void:
	visible = false
	session.manifest["coach"] = {"enabled": false, "done": _done.keys()}
	ZinoProjectService.save_manifest(session.project_dir, session.manifest)

func mark(id: String) -> void:
	if _done.has(id):
		return
	_done[id] = true
	session.manifest["coach"] = {"enabled": true, "done": _done.keys()}
	ZinoProjectService.save_manifest(session.project_dir, session.manifest)
	ZinoAppLog.info("Coach", "Step done: " + id)
	_rebuild()

func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer < 0.4:
		return
	_timer = 0.0
	if session.mode != "edit":
		mark("play")
	var car := _player()
	if not car.is_empty() and car.vehicle.spec.get("bodyColor", []) != _start.get("color"):
		mark("color")
	var race: Dictionary = session.scene().settings.get("race", {})
	if race.get("laps") != _start.race.get("laps") or race.get("aiOpponents") != _start.race.get("aiOpponents"):
		mark("race")
	if _block_count() > int(_start.get("blocks", 0)):
		mark("recipe")
	if editor.build_center and editor.build_center.visible:
		mark("publish")
