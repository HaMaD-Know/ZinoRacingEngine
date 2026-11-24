class_name ZinoVehicleStudio
extends HSplitContainer
## Vehicle Studio: import car models, map wheel meshes, place wheels, tune every vehicle system and
## test drive on a private test pad. Edits are undoable scene commands on the vehicle entity.

var session: ZinoEditorSession
var vehicle_id := ""
var _list: ItemList
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _orbit := Vector2(deg_to_rad(35), deg_to_rad(-18))
var _dist := 8.0
var _preview: Node3D
var _builder: ZinoSceneBuilder
var _tabs: TabContainer
var _telemetry: Label
var _driving := false
var _drive_ctx: ZinoGameContext
var _t0 := -1.0
var _zero_to_100 := 0.0
var _top := 0.0
var _rebuild_pending := false

func setup(s: ZinoEditorSession) -> void:
	session = s
	add_child(_build_left())
	var mid := HSplitContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(mid)
	mid.add_child(_build_preview())
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.x = 380
	mid.add_child(_tabs)
	session.scene_changed.connect(func(c):
		if _driving:
			return
		if c.get("reloaded", false) or vehicle_id in c.get("modified", []) or vehicle_id in c.get("removed", []) or not c.get("added", []).is_empty():
			_queue_rebuild())
	visibility_changed.connect(func():
		if visible:
			refresh())

func refresh() -> void:
	_list.clear()
	var first := ""
	for e in session.scene()["entities"]:
		if e.type == ZinoEntities.TYPE_VEHICLE:
			_list.add_item(e.name)
			_list.set_item_metadata(_list.item_count - 1, e.id)
			if first == "":
				first = e.id
			if e.id == vehicle_id:
				_list.select(_list.item_count - 1)
	if ZinoFormat.find_entity(session.scene(), vehicle_id).is_empty():
		vehicle_id = first
		if first != "":
			_list.select(0)
	_rebuild_preview()
	_rebuild_tabs()

func _queue_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	(func():
		_rebuild_pending = false
		if visible:
			refresh()).call_deferred()

# --- Left: vehicles -----------------------------------------------------------------------------

func _build_left() -> Control:
	var v := ZinoUI.vbox(8)
	v.custom_minimum_size.x = 240
	v.add_child(ZinoUI.section("Vehicles in scene"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i):
		vehicle_id = _list.get_item_metadata(i)
		session.select([vehicle_id])
		_rebuild_preview()
		_rebuild_tabs())
	v.add_child(_list)
	v.add_child(ZinoUI.button("Add Vehicle", func():
		session.add_entity("vehicle")
		vehicle_id = session.selection[0] if not session.selection.is_empty() else vehicle_id
		refresh()))
	v.add_child(ZinoUI.button("Import Car Model…", _import_model))
	v.add_child(ZinoUI.dim("GLB, glTF or FBX. The file is copied into Assets/Vehicles; your original is never changed.", 11))
	return v

func _import_model() -> void:
	var fd := FileDialog.new()
	fd.title = "Import Car Model"
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = PackedStringArray(["*.glb, *.gltf, *.fbx ; 3D models"])
	fd.use_native_dialog = true
	add_child(fd)
	fd.file_selected.connect(func(p):
		fd.queue_free()
		var r := ZinoAssetImporter.import_file(session.project_dir, p, "Vehicles")
		if r.has("error"):
			session.app.show_message("Import failed", r.error)
			return
		ZinoAppLog.info("Vehicle", "Imported %s" % r.rel)
		if vehicle_id == "":
			session.add_entity("vehicle")
			vehicle_id = session.selection[0]
		assign_model(r.rel))
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered_ratio(0.6)

## Assigns a model to the current vehicle, auto-detecting wheel meshes and fitting wheels to them.
func assign_model(rel: String) -> String:
	var e := ZinoFormat.find_entity(session.scene(), vehicle_id)
	if e.is_empty():
		return "No vehicle selected."
	ZinoModelLoader.clear_cache()
	var r := ZinoModelLoader.instantiate(rel)
	if r.has("error"):
		return r.error
	var model: Node3D = r.node
	var detected := ZinoModelLoader.detect_wheels(model)
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(model)
	var box := ZinoModelLoader.aabb_in(model, holder)
	var fits := {}
	for k in detected:
		var mi: MeshInstance3D = ZinoModelLoader.mesh_nodes(model)[detected[k]]
		fits[k] = ZinoModelLoader.aabb_in(mi, holder)
	holder.free()
	session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(x):
		var sp: Dictionary = x.vehicle.spec
		var size := box.size
		var scale := 1.0
		# Models authored in centimetres: bring them to ~4.5 m.
		if size.z > 50.0:
			scale = 0.01
		sp["model"] = {"path": rel, "scale": scale, "offset": ZinoFormat.arr3(-box.get_center() * scale), "rotation": [0, 0, 0], "wheelNodes": detected, "hideProceduralBody": true}
		sp["bodySize"] = ZinoFormat.arr3(Vector3(size.x * scale * 0.9, maxf(0.3, size.y * scale * 0.45), size.z * scale * 0.9))
		if fits.size() == 4:
			for w in sp.wheels:
				if fits.has(w.name):
					var c: Vector3 = (fits[w.name].get_center() - box.get_center()) * scale
					w.position = ZinoFormat.arr3(c)
			sp["wheelRadius"] = snappedf(fits.values()[0].size.y * scale * 0.5, 0.001)
			sp["wheelWidth"] = snappedf(fits.values()[0].size.x * scale, 0.001), "Import Car Model"))
	ZinoAppLog.info("Vehicle", "Model assigned; %d wheel mesh(es) detected%s" % [detected.size(), "" if detected.size() == 4 else " — map the rest in Body & Model"])
	return ""

# --- Preview ----------------------------------------------------------------------------------

func _build_preview() -> Control:
	var box := ZinoUI.vbox(0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", ZinoTheme.box(ZinoTheme.BG_2, 0, Color.TRANSPARENT, 0, 6))
	var h := ZinoUI.hbox(6)
	bar.add_child(h)
	h.add_child(ZinoUI.accent_button("Test Drive", toggle_drive))
	h.add_child(ZinoUI.button("Reset Car", func():
		if _drive_ctx and _builder.player_vehicle():
			_builder.player_vehicle().reset_to_spawn()
			_t0 = -1.0))
	h.add_child(ZinoUI.spacer())
	_telemetry = ZinoUI.dim("Drag to orbit · wheel to zoom", 12)
	h.add_child(_telemetry)
	box.add_child(bar)
	var c := SubViewportContainer.new()
	c.stretch = true
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.focus_mode = Control.FOCUS_CLICK
	c.gui_input.connect(_preview_input)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	c.add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	_cam = Camera3D.new()
	_cam.fov = 45
	_vp.add_child(_cam)
	_cam.current = true
	box.add_child(c)
	return box

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)):
		_orbit += Vector2(-event.relative.x, -event.relative.y) * 0.008
		_orbit.y = clampf(_orbit.y, -1.4, 0.3)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(2.0, _dist * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(40.0, _dist * 1.1)

func _rebuild_preview() -> void:
	if _driving:
		return
	for ch in _world.get_children():
		ch.free()
	var e := ZinoFormat.find_entity(session.scene(), vehicle_id)
	var doc := ZinoFormat.new_scene("Preview")
	var floor_e := ZinoEntities.primitive("plane", "Turntable", Color(0.32, 0.33, 0.36), "concrete")
	ZinoEntities.set_scale(floor_e, Vector3(60, 1, 60))
	doc.entities.append(floor_e)
	var sun := ZinoEntities.light("directional")
	doc.entities.append(sun)
	doc.settings.fogEnabled = false
	if not e.is_empty():
		var car: Dictionary = e.duplicate(true)
		car.parentId = null
		var y: float = float(car.vehicle.spec.wheelRadius) + float(car.vehicle.spec.suspensionRestLength) + ZinoFormat.v3(car.vehicle.spec.bodySize).y * 0.5
		car.transform = ZinoFormat.transform_dict(Vector3(0, y, 0), Vector3.ZERO, Vector3.ONE)
		doc.entities.append(car)
	_builder = ZinoSceneBuilder.new(_world, ZinoSceneBuilder.MODE_EDIT, "high")
	_builder.build(doc)
	ZinoGraphics.apply_viewport(_vp, "high")
	if not e.is_empty():
		var v := _builder.node_for(e.id)
		if v and v.has_meta("model_error"):
			_telemetry.text = "Model: " + str(v.get_meta("model_error"))
		# Wheel markers.
		for w in e.vehicle.spec.wheels:
			var m := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = float(e.vehicle.spec.wheelRadius) * 0.95
			tm.outer_radius = float(e.vehicle.spec.wheelRadius) * 1.05
			m.mesh = tm
			m.rotation_degrees = Vector3(0, 0, 90)
			m.material_override = ZinoMaterials.unshaded(ZinoTheme.ACCENT, true)
			m.position = ZinoFormat.v3(w.position)
			if v:
				v.add_child(m)

func _process(delta: float) -> void:
	if not visible or _cam == null:
		return
	var target := Vector3(0, 0.6, 0)
	var car := _builder.player_vehicle() if _builder else null
	if _driving and car:
		target = car.global_position
		var speed := car.speed_kmh
		_top = maxf(_top, speed)
		if _t0 < 0.0 and speed > 1.0:
			_t0 = Time.get_ticks_msec() / 1000.0
		if _t0 >= 0.0 and _zero_to_100 == 0.0 and speed >= 100.0:
			_zero_to_100 = Time.get_ticks_msec() / 1000.0 - _t0
		_telemetry.text = "%d km/h · gear %s · %d rpm · top %d km/h · 0–100: %s · grounded %d/4" % [
			int(speed), "R" if car.gear == -1 else str(car.gear), int(car.rpm), int(_top),
			("%.2f s" % _zero_to_100) if _zero_to_100 > 0.0 else "—", car.grounded_wheels()]
	var b := Basis.from_euler(Vector3(_orbit.y, _orbit.x, 0))
	_cam.global_transform = Transform3D(b, target + b * Vector3(0, 0, _dist))

func toggle_drive() -> void:
	if _driving:
		stop_drive()
		return
	var e := ZinoFormat.find_entity(session.scene(), vehicle_id)
	if e.is_empty():
		return
	_driving = true
	for ch in _world.get_children():
		ch.free()
	var doc := ZinoFormat.new_scene("Test Pad")
	doc.settings.race.enabled = false
	var pad := ZinoEntities.primitive("plane", "Test Pad", Color(0.2, 0.2, 0.22), "asphalt")
	ZinoEntities.set_scale(pad, Vector3(1200, 1, 1200))
	doc.entities.append(pad)
	doc.entities.append(ZinoEntities.light("directional"))
	var car: Dictionary = e.duplicate(true)
	car.parentId = null
	car.vehicle.playerControlled = true
	var y: float = float(car.vehicle.spec.wheelRadius) + float(car.vehicle.spec.suspensionRestLength) + ZinoFormat.v3(car.vehicle.spec.bodySize).y * 0.5 + 0.05
	car.transform = ZinoFormat.transform_dict(Vector3(0, y, 0), Vector3.ZERO, Vector3.ONE)
	doc.entities.append(car)
	_builder = ZinoSceneBuilder.new(_world, ZinoSceneBuilder.MODE_PLAY, "high")
	_builder.build(doc)
	_drive_ctx = ZinoGameContext.new()
	_vp.add_child(_drive_ctx)
	_drive_ctx.start(_builder, session.project_dir, [], {"ai_count": 0, "start_race": false})
	_drive_ctx.hud.visible = false
	_t0 = -1.0
	_zero_to_100 = 0.0
	_top = 0.0
	_dist = 9.0
	ZinoAppLog.info("Vehicle", "Test drive: W/S throttle & brake, A/D steer, Space handbrake, Q/E gears (manual), N nitro")

func stop_drive() -> void:
	_driving = false
	if _drive_ctx:
		_drive_ctx.stop()
		_drive_ctx.free()
		_drive_ctx = null
	_telemetry.text = "Drag to orbit · wheel to zoom"
	_rebuild_preview()

# --- Tuning tabs --------------------------------------------------------------------------------

func _rebuild_tabs() -> void:
	var keep := _tabs.current_tab
	for c in _tabs.get_children():
		_tabs.remove_child(c)   # detach first so the new tabs can reuse the names
		c.queue_free()
	(func(): if _tabs.get_tab_count() > keep and keep >= 0: _tabs.current_tab = keep).call_deferred()
	var e := ZinoFormat.find_entity(session.scene(), vehicle_id)
	if e.is_empty():
		var l := ZinoUI.dim("Add a vehicle to the scene to tune it.", 13)
		l.name = "Vehicle"
		_tabs.add_child(l)
		return
	var s: Dictionary = e.vehicle.spec
	_tab("Body & Model", func(v): _body_tab(v, e, s))
	_tab("Wheels", func(v): _wheels_tab(v, s))
	_tab("Engine", func(v): _engine_tab(v, s))
	_tab("Chassis", func(v): _chassis_tab(v, s))
	_tab("Camera & Sound", func(v): _cam_sound_tab(v, e))

func _tab(title: String, fill: Callable) -> void:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := ZinoUI.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(ZinoUI.margin(v, 10))
	sc.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.call(v)
	_tabs.add_child(sc)

func _set_spec(label: String, key: String, value) -> void:
	session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(x): x.vehicle.spec[key] = value, label))

func _num(v: VBoxContainer, label: String, s: Dictionary, key: String, lo: float, hi: float, step: float, suffix: String = "") -> void:
	v.add_child(ZinoUI.row(label, ZinoUI.spin(lo, hi, step, float(s.get(key, 0)), func(x): _set_spec(label, key, x), suffix), 150))

func _body_tab(v: VBoxContainer, e: Dictionary, s: Dictionary) -> void:
	v.add_child(ZinoUI.row("Name", _name_edit(e), 150))
	v.add_child(ZinoUI.row("Handling profile", ZinoUI.option(ZinoEntities.PROFILES.map(func(p): return [p, p.capitalize()]), s.get("profile", "arcade"), func(p):
		session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(x):
			var keep := {"bodyColor": x.vehicle.spec.get("bodyColor"), "model": x.vehicle.spec.get("model"), "wheels": x.vehicle.spec.get("wheels"), "bodySize": x.vehicle.spec.get("bodySize")}
			var ns := ZinoEntities.default_vehicle_spec(p)
			for k in keep:
				if keep[k] != null:
					ns[k] = keep[k]
			x.vehicle.spec = ns, "Handling Profile"))), 150))
	v.add_child(ZinoUI.row("Paint", ZinoUI.color_button(ZinoFormat.col(s.get("bodyColor")), func(c): _set_spec("Paint", "bodyColor", ZinoFormat.arr_col(c))), 150))
	v.add_child(ZinoUI.vec3_row("Body size", ZinoFormat.v3(s.get("bodySize")), 0.01, func(x): _set_spec("Body Size", "bodySize", ZinoFormat.arr3(x))))
	v.add_child(ZinoUI.vec3_row("Centre of mass", ZinoFormat.v3(s.get("centerOfMass")), 0.01, func(x): _set_spec("Centre of Mass", "centerOfMass", ZinoFormat.arr3(x))))
	_num(v, "Mass", s, "massKg", 50, 20000, 10, " kg")
	v.add_child(ZinoUI.section("Imported model"))
	var m = s.get("model")
	if not (m is Dictionary):
		v.add_child(ZinoUI.dim("Procedural body. Use “Import Car Model…” to use your own GLB/glTF/FBX car.", 12))
		return
	v.add_child(ZinoUI.row("File", ZinoUI.dim(str(m.path), 12), 150))
	var setm := func(label: String, key: String, value):
		session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(x): x.vehicle.spec.model[key] = value, label))
	v.add_child(ZinoUI.row("Scale", ZinoUI.spin(0.001, 100, 0.001, float(m.get("scale", 1.0)), func(x): setm.call("Model Scale", "scale", x)), 150))
	v.add_child(ZinoUI.vec3_row("Offset", ZinoFormat.v3(m.get("offset")), 0.01, func(x): setm.call("Model Offset", "offset", ZinoFormat.arr3(x))))
	v.add_child(ZinoUI.vec3_row("Rotation", ZinoFormat.v3(m.get("rotation")), 1.0, func(x): setm.call("Model Rotation", "rotation", ZinoFormat.arr3(x))))
	v.add_child(ZinoUI.row("Procedural body", ZinoUI.check("Hide", m.get("hideProceduralBody", true), func(b): setm.call("Body Visibility", "hideProceduralBody", b)), 150))
	v.add_child(ZinoUI.section("Wheel meshes"))
	var r := ZinoModelLoader.instantiate(str(m.path))
	var paths: Array = [["", "(none — procedural wheel)"]]
	if r.has("node"):
		for p in ZinoModelLoader.mesh_nodes(r.node):
			paths.append([p, p])
		r.node.free()
	var wn: Dictionary = m.get("wheelNodes", {})
	for key in ["FL", "FR", "RL", "RR"]:
		var k: String = key
		v.add_child(ZinoUI.row(k, ZinoUI.option(paths, wn.get(k, ""), func(p):
			session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(x):
				var d: Dictionary = x.vehicle.spec.model.get("wheelNodes", {})
				if p == "":
					d.erase(k)
				else:
					d[k] = p
				x.vehicle.spec.model["wheelNodes"] = d, "Wheel Mesh"))), 150))
	v.add_child(ZinoUI.button("Re-detect wheels and fit", func(): assign_model(str(m.path))))

func _name_edit(e: Dictionary) -> LineEdit:
	var le := LineEdit.new()
	le.text = e.name
	le.text_submitted.connect(func(t):
		if t.strip_edges() != "":
			session.execute(ZinoSceneEdits.rename(session.scene(), vehicle_id, t.strip_edges())))
	return le

func _wheels_tab(v: VBoxContainer, s: Dictionary) -> void:
	_num(v, "Wheel radius", s, "wheelRadius", 0.05, 2.0, 0.005, " m")
	_num(v, "Wheel width", s, "wheelWidth", 0.05, 1.0, 0.005, " m")
	for i in s.wheels.size():
		var w: Dictionary = s.wheels[i]
		var idx: int = i
		v.add_child(ZinoUI.section("Wheel " + str(w.name)))
		v.add_child(ZinoUI.vec3_row("Position", ZinoFormat.v3(w.position), 0.01, func(x):
			session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(y): y.vehicle.spec.wheels[idx].position = ZinoFormat.arr3(x), "Wheel Position"))))
		var flags := ZinoUI.hbox(10)
		for f in ["steer", "drive", "handbrake"]:
			var flag: String = f
			flags.add_child(ZinoUI.check(flag.capitalize(), w.get(flag, false), func(b):
				session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(y): y.vehicle.spec.wheels[idx][flag] = b, "Wheel " + flag))))
		v.add_child(flags)

func _engine_tab(v: VBoxContainer, s: Dictionary) -> void:
	v.add_child(ZinoUI.row("Drive", ZinoUI.option([["rwd", "Rear-wheel"], ["fwd", "Front-wheel"], ["awd", "All-wheel"]], s.get("drive", "rwd"), func(d):
		session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(x):
			x.vehicle.spec.drive = d
			for w in x.vehicle.spec.wheels:
				w.drive = (d == "awd") or (d == "fwd" and w.steer) or (d == "rwd" and not w.steer), "Drive"))), 150))
	_num(v, "Engine force", s, "maxEngineForce", 10, 60000, 50)
	_num(v, "Top speed", s, "topSpeedKmh", 10, 600, 1, " km/h")
	_num(v, "Idle RPM", s, "idleRpm", 300, 3000, 50)
	_num(v, "Max RPM", s, "maxRpm", 1000, 20000, 100)
	_num(v, "Final drive", s, "finalDrive", 0.5, 10, 0.05)
	_num(v, "Reverse ratio", s, "reverseRatio", 0.5, 8, 0.05)
	v.add_child(ZinoUI.row("Gearbox", ZinoUI.option([[true, "Automatic"], [false, "Manual (Q / E)"]], s.get("automatic", true), func(b): _set_spec("Gearbox", "automatic", b)), 150))
	v.add_child(ZinoUI.section("Gear ratios"))
	var ratios: Array = s.get("gearRatios", [])
	for i in ratios.size():
		var idx: int = i
		var h := ZinoUI.hbox(4)
		h.add_child(ZinoUI.spin(0.1, 10, 0.01, float(ratios[i]), func(x):
			session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(y): y.vehicle.spec.gearRatios[idx] = x, "Gear Ratio"))))
		h.add_child(ZinoUI.button("✕", func():
			if ratios.size() > 1:
				session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(y): y.vehicle.spec.gearRatios.remove_at(idx), "Remove Gear"))))
		v.add_child(ZinoUI.row("Gear %d" % (i + 1), h, 150))
	if ratios.size() < 10:
		v.add_child(ZinoUI.button("Add gear", func():
			session.execute(ZinoSceneEdits.modify(session.scene(), [vehicle_id], func(y):
				var g: Array = y.vehicle.spec.gearRatios
				g.append(snappedf(float(g.back()) * 0.82, 0.01)), "Add Gear"))))

func _chassis_tab(v: VBoxContainer, s: Dictionary) -> void:
	v.add_child(ZinoUI.section("Suspension"))
	_num(v, "Rest length", s, "suspensionRestLength", 0.01, 1.0, 0.005, " m")
	_num(v, "Travel", s, "suspensionTravel", 0.01, 1.0, 0.005, " m")
	_num(v, "Stiffness", s, "suspensionStiffness", 1, 500, 0.5)
	_num(v, "Compression damping", s, "dampingCompression", 0, 20, 0.1)
	_num(v, "Rebound damping", s, "dampingRelaxation", 0, 20, 0.1)
	_num(v, "Anti-roll", s, "rollInfluence", 0, 1, 0.01)
	v.add_child(ZinoUI.section("Steering"))
	_num(v, "Max steer angle", s, "maxSteerAngle", 1, 70, 0.5, "°")
	_num(v, "High-speed factor", s, "highSpeedSteerFactor", 0.05, 1, 0.01)
	_num(v, "Steering speed", s, "steerSpeed", 0.5, 20, 0.1)
	v.add_child(ZinoUI.section("Tyres & brakes"))
	_num(v, "Front grip", s, "tireFrictionSlip", 0.1, 30, 0.1)
	_num(v, "Rear grip", s, "rearFrictionSlip", 0.1, 30, 0.1)
	_num(v, "Brake force", s, "maxBrakeForce", 0, 500, 1)
	_num(v, "Handbrake force", s, "handbrakeForce", 0, 500, 1)
	v.add_child(ZinoUI.section("Aerodynamics"))
	_num(v, "Downforce", s, "downforce", 0, 20, 0.1)
	_num(v, "Drag coefficient", s, "dragCoefficient", 0, 2, 0.01)

func _cam_sound_tab(v: VBoxContainer, e: Dictionary) -> void:
	v.add_child(ZinoUI.section("Chase camera"))
	var cam := {}
	for x in session.scene()["entities"]:
		if x.type == ZinoEntities.TYPE_CAMERA and x.camera.get("targetId") == vehicle_id:
			cam = x
	if cam.is_empty():
		v.add_child(ZinoUI.dim("No camera follows this vehicle.", 12))
		v.add_child(ZinoUI.button("Add chase camera", func():
			var c := ZinoEntities.camera("Chase Camera", "chase", vehicle_id)
			session.execute(ZinoSceneEdits.create(session.scene(), [c], "Add Chase Camera"))))
	else:
		var cid: String = cam.id
		for f in [["followDistance", "Distance", 1, 50, 0.1], ["followHeight", "Height", 0, 20, 0.1], ["lookAhead", "Look-ahead", 0, 30, 0.1], ["smoothing", "Smoothing", 0.5, 30, 0.1], ["fov", "Field of view", 20, 120, 0.5]]:
			var key: String = f[0]
			v.add_child(ZinoUI.row(f[1], ZinoUI.spin(f[2], f[3], f[4], float(cam.camera.get(key, 0)), func(x):
				session.execute(ZinoSceneEdits.modify(session.scene(), [cid], func(y): y.camera[key] = x, "Camera " + key))), 150))
	v.add_child(ZinoUI.section("Engine sound (scene)"))
	var audio: Dictionary = session.scene().settings.get("audio", {})
	for f in [["engineCylinders", "Cylinders", 1, 16, 1, 6], ["engineCharacter", "Character (smooth → raspy)", 0, 1, 0.05, 0.5], ["engineVolume", "Engine volume", 0, 2, 0.05, 0.8]]:
		var key: String = f[0]
		v.add_child(ZinoUI.row(f[1], ZinoUI.spin(f[2], f[3], f[4], float(audio.get(key, f[5])), func(x):
			var st: Dictionary = session.scene().settings.duplicate(true)
			var a: Dictionary = st.get("audio", {})
			a[key] = x
			st["audio"] = a
			session.execute(ZinoSceneEdits.settings(session.scene(), st, "Engine Sound"))), 150))
	v.add_child(ZinoUI.dim("Engine audio is synthesised from RPM and throttle; hear it in Test Drive.", 11))
