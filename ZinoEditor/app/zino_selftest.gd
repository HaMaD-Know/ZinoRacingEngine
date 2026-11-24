extends Node
## Automated smoke test of the real, windowed application:
##   Godot.exe --path ZinoEditor -- --zino-selftest=<output dir>
## Creates a project through the app, edits, undoes, plays the racing test scene with real
## physics, saves, and writes screenshots plus selftest_report.json to the output directory.

var app: ZinoApp
var out_dir := ""
var report := {"steps": [], "ok": true}

func run(zino_app: ZinoApp, dir: String) -> void:
	app = zino_app
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _step(name: String, ok: bool, detail: String = "") -> void:
	report.steps.append({"step": name, "ok": ok, "detail": detail})
	if not ok:
		report.ok = false
	ZinoAppLog.write("info" if ok else "error", "SelfTest", "%s %s %s" % ["PASS" if ok else "FAIL", name, detail])

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))

func _run() -> void:
	await _frames(30)
	await _shot("01_home.png")
	_step("home screen shown", app.home != null and app.home.visible)

	var loc := out_dir.path_join("projects")
	_remove_dir(loc)
	DirAccess.make_dir_recursive_absolute(loc)
	var o := ZinoProjectService.default_options()
	o["name"] = "SelfTestCircuit"
	o["location"] = loc
	o["template"] = "circuit"
	app.create_project(o)
	await _frames(10)
	var ed = app.editor_screen
	_step("project created and opened in the editor", ed != null and ed.session != null and ed.session.stack != null)
	if ed == null:
		_finish()
		return
	var s: ZinoEditorSession = ed.session
	_step("editor preview defaults to Ultra Max", ed.viewport_panel.preview_preset == "ultraMax", ed.viewport_panel.preview_preset)
	await _frames(150)
	await _shot("02_editor.png")

	var car_id := ""
	for e in s.scene()["entities"]:
		if e["type"] == "vehicle":
			car_id = e["id"]
	s.select([car_id])
	ed.viewport_panel.set_tool("rotate")
	ed.viewport_panel.frame_selection()
	await _frames(40)
	await _shot("03_car_selected_rotate_gizmo.png")
	_step("vehicle selected", s.selection == [car_id])
	# Real mouse picking through the viewport (screen position of the car).
	s.select([])
	var vp: ZinoViewportPanel = ed.viewport_panel
	var car_node: Node3D = vp.builder.node_for(car_id)
	var screen := vp.camera.unproject_position(car_node.global_position) * vp.size / Vector2(vp.viewport.size)
	vp._pick(screen, false)
	_step("clicking the car in the viewport selects it", s.selection == [car_id], str(screen))
	s.select([car_id])

	var n0: int = s.scene()["entities"].size()
	s.add_entity("cube")
	var cube_id: String = s.selection[0]
	ed.viewport_panel.set_tool("translate")
	var t := {cube_id: {"position": Vector3(4, 0.5, 30), "rotation": Vector3(0, 30, 0), "scale": Vector3(2, 2, 2)}}
	s.execute(ZinoSceneEdits.set_transforms(s.scene(), t, "Move"))
	var node: Node3D = ed.viewport_panel.builder.node_for(cube_id)
	_step("cube added and transformed in the viewport", s.scene()["entities"].size() == n0 + 1 and node != null and node.position.is_equal_approx(Vector3(4, 0.5, 30)))
	s.undo()
	s.undo()
	_step("undo removes the cube", s.scene()["entities"].size() == n0 and ed.viewport_panel.builder.node_for(cube_id) == null)
	s.redo()
	s.redo()
	var redone: Node3D = ed.viewport_panel.builder.node_for(cube_id)
	_step("redo restores the cube and its move", redone != null and redone.position.is_equal_approx(Vector3(4, 0.5, 30)))
	s.select([cube_id])
	s.duplicate_selection()
	_step("duplicate creates a copy", s.scene()["entities"].size() == n0 + 2)
	ed.hierarchy.rebuild()
	_step("hierarchy lists every entity", ed.hierarchy._items.size() == s.scene()["entities"].size())
	ed.viewport_panel.set_view("Top")
	await _frames(20)
	await _shot("04_top_view.png")
	ed.viewport_panel.set_view("Perspective")

	# --- Phase 3: Block Studio
	ed.show_workspace("Blocks")
	await _frames(20)
	var bs: ZinoBlockStudio = ed.block_studio
	var vr: Dictionary = bs.validate()
	_step("block studio opened the starter program", bs.program_path == "Blocks/Game Logic.zblocks" and bs.program.nodes.size() > 15 and vr.ok, "%d blocks" % bs.program.nodes.size())
	var nid := bs.add_block("ui_big")
	_step("block added from the palette", bs.program.nodes.any(func(n): return n.id == nid) and bs._graph.get_node_or_null(NodePath(nid)) != null)
	bs.undo()
	_step("block studio undo", not bs.program.nodes.any(func(n): return n.id == nid))
	await _frames(10)
	await _shot("07_block_studio.png")
	ed.show_workspace("Scene")
	await _frames(5)

	# --- Phase 4: Vehicle Studio
	var glb := out_dir.path_join("studio car.glb")
	var helper = load("res://tests/test_vehicle_model.gd") if ResourceLoader.exists("res://tests/test_vehicle_model.gd") else null
	if helper == null:
		# Release builds do not ship tests: skip only the vehicle import part.
		_step("vehicle model helper available (tests are not shipped in release builds)", true)
	else:
		helper.make_car_glb(glb)
		ed.show_workspace("Vehicle")
		await _frames(5)
		var vs: ZinoVehicleStudio = ed.vehicle_studio
		var imp := ZinoAssetImporter.import_file(s.project_dir, glb)
		var aerr := vs.assign_model(imp.get("rel", ""))
		var spec: Dictionary = ZinoFormat.find_entity(s.scene(), vs.vehicle_id).vehicle.spec
		_step("vehicle studio imports a model and fits 4 wheels", aerr == "" and spec.get("model", {}).get("wheelNodes", {}).size() == 4, aerr)
		await _frames(10)
		vs._dist = 7.0
		await _frames(10)
		await _shot("08_vehicle_studio.png")
		vs.toggle_drive()
		await _frames(10)
		Input.action_press(ZinoInput.ACCELERATE)
		for i in 300:   # 2.5 s of simulated physics (wall-clock time varies with the GPU)
			await get_tree().physics_frame
		var tcar := vs._builder.player_vehicle()
		var tspeed := tcar.speed_kmh if tcar else 0.0
		await _shot("09_test_drive.png")
		Input.action_release(ZinoInput.ACCELERATE)
		_step("test drive on the pad", tspeed > 15.0, "%.1f km/h" % tspeed)
		vs.stop_drive()
		s.undo()   # back to the procedural car for the race below
		ed.show_workspace("Scene")
		await _frames(5)

	# --- Phase 9: UI Studio, Audio Studio, Asset Store
	ed.show_workspace("UI")
	await _frames(15)
	await _shot("10_ui_studio.png")
	var uis: ZinoUIStudio = ed.ui_studio
	uis._layout.laps.offset = [200, 160]
	uis._commit()
	_step("UI Studio saves the HUD layout", s.scene().settings.get("hud", {}).get("laps", {}).get("offset", []) == [200, 160])
	s.undo()
	uis.set_mode("touch")
	await _frames(10)
	await _shot("11_touch_designer.png")
	_step("touch controls designer shows controls", uis._touch != null and uis._touch.control_rect("accelerate").size.x > 50)
	uis.set_mode("hud")
	ed.show_workspace("Audio")
	await _frames(10)
	await _shot("12_audio_studio.png")
	ed.show_workspace("Store")
	var st: ZinoAssetStore = ed.store
	st.set_kind("textures")
	var t0 := Time.get_ticks_msec()
	while not st._items.has("textures") and Time.get_ticks_msec() - t0 < 30000:
		await _frames(5)
	_step("store loads the Poly Haven texture catalogue", st._items.get("textures", []).size() > 100, "%d textures" % st._items.get("textures", []).size())
	await get_tree().create_timer(3.0).timeout
	await _shot("13_asset_store.png")
	var item: Dictionary = {}
	for it in st._items.get("textures", []):
		if it.id == "asphalt_02":
			item = it
	if not item.is_empty():
		var box := {"r": {}}
		st.client.download_finished.connect(func(_id, r): box.r = r, CONNECT_ONE_SHOT)
		st.client.download(item, s.project_dir, "1k")
		t0 = Time.get_ticks_msec()
		while box.r.is_empty() and Time.get_ticks_msec() - t0 < 90000:
			await _frames(5)
		_step("store downloads asphalt_02 (MD5 verified) into Assets/Textures", box.r.get("ok", false) and FileAccess.file_exists(s.project_dir.path_join(box.r.get("main", "x"))), str(box.r.get("error", box.r.get("main", ""))))
		if box.r.get("ok", false):
			var cube := ZinoEntities.primitive("cube", "Store Cube")
			ZinoEntities.set_pos(cube, Vector3(6, 0.5, 30))
			s.execute(ZinoSceneEdits.create(s.scene(), [cube]))
			s.select([cube.id])
			_step("downloaded material applied to a cube", st.apply_texture(box.r.maps) == 1 and str(ZinoFormat.find_entity(s.scene(), cube.id).mesh.material.get("albedoTexture", "")).ends_with(".jpg"))
	ed.show_workspace("Scene")
	await _frames(5)

	ed._play()
	var game: ZinoGameContext = ed.viewport_panel.game
	_step("playtest starts a race with AI opponents", game != null and game.race != null and game.ai_vehicles.size() == 3 and game.race.state == "countdown")
	await get_tree().create_timer(3.6).timeout
	_step("countdown ends and the race starts", game.race.state == "racing")
	Input.action_press(ZinoInput.ACCELERATE)
	await get_tree().create_timer(3.0).timeout
	var car: ZinoVehicle = ed.viewport_panel.builder.player_vehicle()
	var speed := car.speed_kmh if car else 0.0
	await _shot("05_playtest.png")
	Input.action_release(ZinoInput.ACCELERATE)
	_step("playtest drives the car with real physics", speed > 20.0, "%.1f km/h after 3 s, gear %d" % [speed, car.gear if car else 0])
	ed._stop()
	await _frames(10)
	_step("stop restores edit mode", s.mode == "edit" and ed.viewport_panel.builder.node_for(cube_id) != null)

	var saved := s.save()
	var reloaded := ZinoFormat.load_scene_file(s.project_dir.path_join(s.scene_rel))
	_step("save writes the scene", saved and reloaded.ok and reloaded.scene["entities"].size() == s.scene()["entities"].size())
	# --- Phase 2: road point editing, box select, multiple scenes
	var road_id := ""
	for e in s.scene()["entities"]:
		if e["type"] == "road":
			road_id = e["id"]
	ed.viewport_panel.move_road_point(road_id, 0, Vector3(3, 0, 40))
	var p0 := ZinoFormat.v3(ZinoFormat.find_entity(s.scene(), road_id)["road"]["points"][0])
	_step("road control point moved in the viewport", p0.is_equal_approx(Vector3(3, 0, 40)))
	s.undo()
	ed.viewport_panel.frame_all()
	await _frames(5)
	var boxed: Array = ed.viewport_panel.ids_in_screen_rect(Rect2(Vector2.ZERO, ed.viewport_panel.size))
	_step("box selection finds objects on screen", boxed.size() >= 5, "%d objects" % boxed.size())
	s.save()
	var err := s.new_scene("DragTest", "drag")
	_step("new scene from template", err == "" and s.scene_rel == "Scenes/DragTest.zscene" and s.scene()["entities"].any(func(e): return e["name"] == "Drag Strip"), err)
	await _frames(20)
	await _shot("06_second_scene.png")
	err = s.open_scene("Scenes/Main.zscene")
	_step("switch back to the main scene", err == "" and s.scene()["entities"].any(func(e): return e["type"] == "road" and e["name"] == "Circuit Road"), err)
	err = s.save_scene_as("MainCopy")
	_step("save scene as", err == "" and FileAccess.file_exists(s.project_dir.path_join("Scenes/MainCopy.zscene")) and "Scenes/MainCopy.zscene" in s.manifest["scenes"], err)
	_step("project lists all scenes", s.list_scenes().size() == 3)
	s.open_scene("Scenes/Main.zscene")
	var reopen := ZinoProjectService.open_project(s.project_dir)
	_step("project reopens cleanly", reopen.ok and reopen.warnings.is_empty())

	# --- Ease of use: Make a Game wizard → Simple mode editor with Game tab, Coach and recipes
	app.settings.set_value("simpleMode", true)
	var qloc := out_dir.path_join("quick")
	_remove_dir(qloc)
	DirAccess.make_dir_recursive_absolute(qloc)
	s.save()
	var wiz := ZinoMakeGameWizard.new()
	wiz.app = app
	app.add_child(wiz)
	wiz.popup_centered(Vector2i(1000, 700))
	await _frames(5)
	wiz.choices.merge({"gameType": "circuit", "car": "racer", "color": "#0a84ff", "track": "hills", "world": "sunset",
		"laps": 2, "opponents": 3, "name": "SelfTestQuick", "location": qloc}, true)
	wiz._step = 4
	wiz._show()
	await _frames(10)
	await _shot("20_make_a_game.png")
	ed.confirm_close(func(): wiz._create())
	await _frames(120)
	ed = app.editor_screen
	_step("Make a Game opens the new game in Simple mode", ed != null and ed.simple and ed.session.project_dir.ends_with("SelfTestQuick"))
	if ed == null:
		_finish()
		return
	s = ed.session
	_step("Simple mode opens on the Game tab with the Coach", ed._right_tabs.get_current_tab_control() == ed.game_panel and ed.coach.visible)
	await _shot("21_simple_mode.png")
	ed.game_panel._set_settings(func(x): x.race.laps = 5, "Laps")
	await _frames(40)
	_step("Game tab changes the laps", int(s.scene().settings.race.laps) == 5 and ed.coach._done.has("race"))
	s.undo()
	_step("Game tab edits are undoable", int(s.scene().settings.race.laps) == 2)
	ed.show_workspace("Blocks")
	await _frames(10)
	var rids: Array = ed.block_studio.insert_recipe("boost_key")
	var rv: Dictionary = ed.block_studio.validate()
	await _frames(40)
	_step("recipe adds pre-wired blocks", rids.size() == 3 and rv.ok and ed.coach._done.has("recipe"), str(rv.get("errors", [])))
	await _shot("22_recipe.png")
	ed.show_workspace("Build")
	await _frames(40)
	_step("Coach ticks off Publish", ed.coach._done.has("publish"))
	ed.show_workspace("Scene")
	ed._play()
	await _frames(240)
	_step("quick game plays with opponents", s.mode != "edit" and ed.coach._done.has("play"))
	await _shot("23_quick_game_play.png")
	ed._stop()
	await _frames(10)
	report["fps"] = Engine.get_frames_per_second()
	report["gpu"] = RenderingServer.get_video_adapter_name()
	report["renderer"] = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	report["preview"] = ed.viewport_panel.preview_preset
	_finish()

## Recursive delete of the self-test's own output folder (no dependency on test code, which is not shipped).
static func _remove_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)

func _finish() -> void:
	var f := FileAccess.open(out_dir.path_join("selftest_report.json"), FileAccess.WRITE)
	f.store_string(ZinoFormat.to_json(report))
	f.close()
	get_tree().quit(0 if report.ok else 1)
