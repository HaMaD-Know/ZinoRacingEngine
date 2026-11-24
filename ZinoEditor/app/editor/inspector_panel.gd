class_name ZinoInspectorPanel
extends ScrollContainer
## Inspector: edits the selected entity (transform, material, light, camera, vehicle physics,
## road geometry, trigger, spawn) or, with nothing selected, the scene's world settings.
## Every change is an undoable command.

var session: ZinoEditorSession
var _box: VBoxContainer
var _self_edit := false

func setup(s: ZinoEditorSession) -> void:
	session = s
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = ZinoUI.vbox(10)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(ZinoUI.margin(_box, 10))
	get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session.selection_changed.connect(func(_ids): rebuild())
	session.scene_changed.connect(func(c):
		if _self_edit:
			return
		for id in session.selection:
			if id in c.get("modified", []) or c.get("reloaded", false):
				rebuild.call_deferred()
				return
		if session.selection.is_empty() and c.get("settingsChanged", false):
			rebuild.call_deferred())
	session.state_changed.connect(func(): _box.modulate.a = 1.0 if session.mode == "edit" else 0.5)
	rebuild()

func rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	var sel: Array = session.selection
	if sel.is_empty():
		_world_settings()
	elif sel.size() > 1:
		_multi(sel)
	else:
		var e := ZinoFormat.find_entity(session.scene(), sel[0])
		if not e.is_empty():
			_entity(e)

func _edit(label: String, mutate: Callable, refresh: bool = false) -> void:
	_self_edit = true
	session.modify_selected(mutate, label)
	_self_edit = false
	if refresh:
		rebuild.call_deferred()

# --- Sections ------------------------------------------------------------------------------

func _world_settings() -> void:
	var s: Dictionary = session.scene().get("settings", {})
	_box.add_child(ZinoUI.heading("World", 18))
	_box.add_child(ZinoUI.dim("Nothing selected — editing scene settings.", 12))
	var sec := ZinoUI.section("Environment")
	var envs: Array = []
	for k in ZinoProjectService.ENVIRONMENTS:
		envs.append([k, ZinoProjectService.ENVIRONMENTS[k]])
	sec.add_child(ZinoUI.row("Preset", ZinoUI.option(envs, s.get("environmentPreset", "day"), func(v): _set_setting("environmentPreset", v))))
	sec.add_child(ZinoUI.row("Exposure", ZinoUI.spin(0.1, 8, 0.05, float(s.get("exposure", 1.0)), func(v): _set_setting("exposure", v))))
	sec.add_child(ZinoUI.row("Ambient", ZinoUI.spin(0, 8, 0.05, float(s.get("ambientIntensity", 1.0)), func(v): _set_setting("ambientIntensity", v))))
	sec.add_child(ZinoUI.row("Fog", ZinoUI.check("Enabled (volumetric on Ultra)", s.get("fogEnabled", true), func(v): _set_setting("fogEnabled", v))))
	sec.add_child(ZinoUI.row("Fog density", ZinoUI.spin(0, 0.1, 0.0001, float(s.get("fogDensity", 0.0012)), func(v): _set_setting("fogDensity", v))))
	sec.add_child(ZinoUI.row("Fog color", ZinoUI.color_button(ZinoFormat.col(s.get("fogColor")), func(c): _set_setting("fogColor", ZinoFormat.arr_col(c)))))
	sec.add_child(ZinoUI.row("Time of day", ZinoUI.spin(0, 24, 0.25, float(s.get("timeOfDay", 14.0)), func(v): _set_setting("timeOfDay", v), " h")))
	sec.add_child(ZinoUI.row("Weather", ZinoUI.option([["clear", "Clear"], ["cloudy", "Cloudy"], ["rain", "Rain (wet roads)"], ["storm", "Storm"], ["fog", "Fog"]], s.get("weather", "clear"), func(v): _set_setting("weather", v))))
	_box.add_child(sec)
	var fx: Dictionary = s.get("postFx", {})
	var fxs := ZinoUI.section("Post-processing")
	var set_fx := func(key: String, value):
		var f2: Dictionary = session.scene()["settings"].get("postFx", {}).duplicate(true)
		f2[key] = value
		_set_setting("postFx", f2)
	fxs.add_child(ZinoUI.row("Depth of field", ZinoUI.check("Blur the distance", fx.get("dofEnabled", false), func(v): set_fx.call("dofEnabled", v))))
	fxs.add_child(ZinoUI.row("DOF distance", ZinoUI.spin(5, 2000, 1, float(fx.get("dofDistance", 120.0)), func(v): set_fx.call("dofDistance", v), " m")))
	fxs.add_child(ZinoUI.row("DOF amount", ZinoUI.spin(0, 1, 0.01, float(fx.get("dofAmount", 0.08)), func(v): set_fx.call("dofAmount", v))))
	fxs.add_child(ZinoUI.row("Glow", ZinoUI.spin(0, 4, 0.05, float(fx.get("glowIntensity", 0.35)), func(v): set_fx.call("glowIntensity", v))))
	fxs.add_child(ZinoUI.row("Contrast", ZinoUI.spin(0.5, 2, 0.01, float(fx.get("contrast", 1.04)), func(v): set_fx.call("contrast", v))))
	fxs.add_child(ZinoUI.row("Saturation", ZinoUI.spin(0, 2, 0.01, float(fx.get("saturation", 1.06)), func(v): set_fx.call("saturation", v))))
	fxs.add_child(ZinoUI.row("Speed blur", ZinoUI.check("Radial blur at high speed (in game)", fx.get("speedBlur", true), func(v): set_fx.call("speedBlur", v))))
	_box.add_child(fxs)
	var race: Dictionary = s.get("race", {})
	var rs := ZinoUI.section("Race")
	var set_race := func(key: String, value):
		var st: Dictionary = session.scene()["settings"].duplicate(true)
		var r2: Dictionary = st.get("race", {})
		r2[key] = value
		st["race"] = r2
		_self_edit = true
		session.execute(ZinoSceneEdits.settings(session.scene(), st, "Race Settings"))
		_self_edit = false
	rs.add_child(ZinoUI.row("Race", ZinoUI.check("Enabled", race.get("enabled", true), func(v): set_race.call("enabled", v))))
	rs.add_child(ZinoUI.row("Mode", ZinoUI.option([["auto", "Automatic"], ["circuit", "Circuit"], ["sprint", "Sprint"], ["timeTrial", "Time trial"], ["elimination", "Elimination"]], race.get("mode", "auto"), func(v): set_race.call("mode", v))))
	rs.add_child(ZinoUI.row("Laps", ZinoUI.spin(1, 99, 1, float(race.get("laps", 3)), func(v): set_race.call("laps", int(v)))))
	rs.add_child(ZinoUI.row("Countdown", ZinoUI.spin(0, 10, 0.5, float(race.get("countdown", 3.0)), func(v): set_race.call("countdown", v), " s")))
	rs.add_child(ZinoUI.row("AI opponents", ZinoUI.spin(0, 11, 1, float(race.get("aiOpponents", 3)), func(v): set_race.call("aiOpponents", int(v)))))
	rs.add_child(ZinoUI.row("AI difficulty", ZinoUI.spin(0, 1, 0.05, float(race.get("aiDifficulty", 0.7)), func(v): set_race.call("aiDifficulty", v))))
	rs.add_child(ZinoUI.row("AI behaviour", ZinoUI.option([["cautious", "Cautious"], ["balanced", "Balanced"], ["aggressive", "Aggressive"]], race.get("aiBehavior", "balanced"), func(v): set_race.call("aiBehavior", v))))
	rs.add_child(ZinoUI.row("Start", ZinoUI.check("Start automatically", race.get("autoStart", true), func(v): set_race.call("autoStart", v))))
	_box.add_child(rs)
	var stats := ZinoUI.section("Scene")
	var counts := {}
	for e in session.scene()["entities"]:
		counts[e["type"]] = counts.get(e["type"], 0) + 1
	stats.add_child(ZinoUI.dim("%d objects: %s" % [session.scene()["entities"].size(), ", ".join(counts.keys().map(func(k): return "%d %s" % [counts[k], k]))], 12))
	_box.add_child(stats)

func _set_setting(key: String, value) -> void:
	var s: Dictionary = session.scene()["settings"].duplicate(true)
	s[key] = value
	_self_edit = true
	session.execute(ZinoSceneEdits.settings(session.scene(), s, "Scene Settings"))
	_self_edit = false

func _multi(sel: Array) -> void:
	_box.add_child(ZinoUI.heading("%d objects selected" % sel.size(), 18))
	var h := ZinoUI.hbox(6)
	h.add_child(ZinoUI.button("Duplicate", session.duplicate_selection))
	h.add_child(ZinoUI.button("Delete", session.delete_selection))
	_box.add_child(h)
	_box.add_child(ZinoUI.row("Active", ZinoUI.check("Visible / enabled", true, func(v): _edit("Set Active", func(e): e["active"] = v))))
	_box.add_child(ZinoUI.dim("Use the gizmo to move, rotate or scale all selected objects together.", 12))

func _entity(e: Dictionary) -> void:
	var head := ZinoUI.hbox(6)
	var name_edit := LineEdit.new()
	name_edit.text = e["name"]
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(t): _rename(t))
	name_edit.focus_exited.connect(func(): _rename(name_edit.text))
	head.add_child(name_edit)
	head.add_child(ZinoUI.check("Active", e.get("active", true), func(v): _edit("Set Active", func(x): x["active"] = v)))
	_box.add_child(head)
	_box.add_child(ZinoUI.dim("%s · %s" % [str(e["type"]).capitalize(), e["id"]], 11))

	var t := ZinoFormat.read_transform(e)
	var ts := ZinoUI.section("Transform")
	ts.add_child(ZinoUI.vec3_row("Position", t.position, 0.01, func(v): _edit("Move", func(x): x["transform"]["position"] = ZinoFormat.arr3(v))))
	ts.add_child(ZinoUI.vec3_row("Rotation", t.rotation, 0.1, func(v): _edit("Rotate", func(x): x["transform"]["rotation"] = ZinoFormat.arr3(v))))
	ts.add_child(ZinoUI.vec3_row("Scale", t.scale, 0.01, func(v): _edit("Scale", func(x): x["transform"]["scale"] = ZinoFormat.arr3(v))))
	_box.add_child(ts)

	match e["type"]:
		ZinoEntities.TYPE_PRIMITIVE: _primitive(e)
		ZinoEntities.TYPE_LIGHT: _light(e)
		ZinoEntities.TYPE_CAMERA: _camera(e)
		ZinoEntities.TYPE_VEHICLE: _vehicle(e)
		ZinoEntities.TYPE_ROAD: _road(e)
		ZinoEntities.TYPE_CHECKPOINT, ZinoEntities.TYPE_START_FINISH: _trigger(e)
		ZinoEntities.TYPE_SPAWN:
			var sp := ZinoUI.section("Grid Spawn")
			sp.add_child(ZinoUI.row("Grid slot", ZinoUI.spin(0, 63, 1, float(e["spawn"].get("gridIndex", 0)), func(v): _edit("Grid Slot", func(x): x["spawn"]["gridIndex"] = int(v)))))
			_box.add_child(sp)

func _rename(t: String) -> void:
	var n := t.strip_edges()
	if n != "" and session.selection.size() == 1 and n != ZinoFormat.find_entity(session.scene(), session.selection[0]).get("name"):
		_self_edit = true
		session.execute(ZinoSceneEdits.rename(session.scene(), session.selection[0], n))
		_self_edit = false

func _material_rows(sec: VBoxContainer, m: Dictionary, path: Array) -> void:
	var presets: Array = ZinoEntities.MATERIAL_PRESETS.map(func(p): return [p, p.capitalize()])
	sec.add_child(ZinoUI.row("Material", ZinoUI.option(presets, m.get("preset", "default"), func(v): _edit("Material", func(x): _dig(x, path)["preset"] = v))))
	sec.add_child(ZinoUI.row("Color", ZinoUI.color_button(ZinoFormat.col(m.get("color")), func(c): _edit("Color", func(x): _dig(x, path)["color"] = ZinoFormat.arr_col(c)))))
	sec.add_child(ZinoUI.row("Metallic", ZinoUI.spin(0, 1, 0.01, float(m.get("metallic", 0.0)), func(v): _edit("Metallic", func(x): _dig(x, path)["metallic"] = v))))
	sec.add_child(ZinoUI.row("Roughness", ZinoUI.spin(0, 1, 0.01, float(m.get("roughness", 0.6)), func(v): _edit("Roughness", func(x): _dig(x, path)["roughness"] = v))))

static func _dig(x: Dictionary, path: Array) -> Dictionary:
	var cur: Dictionary = x
	for k in path:
		if not cur.has(k) or not (cur[k] is Dictionary):
			cur[k] = {}
		cur = cur[k]
	return cur

func _primitive(e: Dictionary) -> void:
	var m: Dictionary = e.get("mesh", {})
	var sec := ZinoUI.section("Mesh")
	var shapes: Array = ZinoEntities.PRIMITIVES.map(func(p): return [p, p.capitalize()])
	sec.add_child(ZinoUI.row("Shape", ZinoUI.option(shapes, m.get("primitive", "cube"), func(v): _edit("Shape", func(x): x["mesh"]["primitive"] = v))))
	_material_rows(sec, m.get("material", {}), ["mesh", "material"])
	sec.add_child(ZinoUI.row("Shadows", ZinoUI.check("Cast shadows", m.get("castShadows", true), func(v): _edit("Shadows", func(x): x["mesh"]["castShadows"] = v))))
	sec.add_child(ZinoUI.row("Physics", ZinoUI.check("Solid collider", m.get("collider", true), func(v): _edit("Collider", func(x): x["mesh"]["collider"] = v))))
	_box.add_child(sec)

func _light(e: Dictionary) -> void:
	var l: Dictionary = e.get("light", {})
	var sec := ZinoUI.section("%s Light" % str(l.get("kind", "point")).capitalize())
	sec.add_child(ZinoUI.row("Color", ZinoUI.color_button(ZinoFormat.col(l.get("color")), func(c): _edit("Light Color", func(x): x["light"]["color"] = ZinoFormat.arr_col(c)))))
	sec.add_child(ZinoUI.row("Intensity", ZinoUI.spin(0, 100, 0.05, float(l.get("intensity", 1.0)), func(v): _edit("Light Intensity", func(x): x["light"]["intensity"] = v))))
	if l.get("kind") != "directional":
		sec.add_child(ZinoUI.row("Range", ZinoUI.spin(0.1, 1000, 0.5, float(l.get("range", 10.0)), func(v): _edit("Light Range", func(x): x["light"]["range"] = v), " m")))
	if l.get("kind") == "spot":
		sec.add_child(ZinoUI.row("Spot angle", ZinoUI.spin(1, 89, 1, float(l.get("spotAngle", 45.0)), func(v): _edit("Spot Angle", func(x): x["light"]["spotAngle"] = v), "°")))
	sec.add_child(ZinoUI.row("Shadows", ZinoUI.check("Cast shadows", l.get("shadows", true), func(v): _edit("Light Shadows", func(x): x["light"]["shadows"] = v))))
	_box.add_child(sec)

func _camera(e: Dictionary) -> void:
	var c: Dictionary = e.get("camera", {})
	var sec := ZinoUI.section("Camera")
	sec.add_child(ZinoUI.row("Mode", ZinoUI.option([["fixed", "Fixed"], ["chase", "Chase target"]], c.get("mode", "fixed"), func(v): _edit("Camera Mode", func(x): x["camera"]["mode"] = v, true))))
	if c.get("mode") == "chase":
		var targets: Array = [[null, "(none)"]]
		for v in session.scene()["entities"]:
			if v["type"] == ZinoEntities.TYPE_VEHICLE:
				targets.append([v["id"], v["name"]])
		sec.add_child(ZinoUI.row("Target", ZinoUI.option(targets, c.get("targetId"), func(v): _edit("Camera Target", func(x): x["camera"]["targetId"] = v))))
		sec.add_child(ZinoUI.row("Distance", ZinoUI.spin(1, 50, 0.1, float(c.get("followDistance", 6.5)), func(v): _edit("Follow Distance", func(x): x["camera"]["followDistance"] = v), " m")))
		sec.add_child(ZinoUI.row("Height", ZinoUI.spin(0, 20, 0.1, float(c.get("followHeight", 2.1)), func(v): _edit("Follow Height", func(x): x["camera"]["followHeight"] = v), " m")))
		sec.add_child(ZinoUI.row("Look-ahead", ZinoUI.spin(0, 30, 0.1, float(c.get("lookAhead", 4.0)), func(v): _edit("Look Ahead", func(x): x["camera"]["lookAhead"] = v), " m")))
		sec.add_child(ZinoUI.row("Smoothing", ZinoUI.spin(0.5, 30, 0.1, float(c.get("smoothing", 7.0)), func(v): _edit("Camera Smoothing", func(x): x["camera"]["smoothing"] = v))))
	sec.add_child(ZinoUI.row("Field of view", ZinoUI.spin(10, 140, 0.5, float(c.get("fov", 65.0)), func(v): _edit("FOV", func(x): x["camera"]["fov"] = v), "°")))
	sec.add_child(ZinoUI.row("Far clip", ZinoUI.spin(10, 100000, 10, float(c.get("far", 4000.0)), func(v): _edit("Far Clip", func(x): x["camera"]["far"] = v), " m")))
	_box.add_child(sec)

func _vehicle(e: Dictionary) -> void:
	var vd: Dictionary = e.get("vehicle", {})
	var s: Dictionary = vd.get("spec", {})
	var sec := ZinoUI.section("Vehicle")
	sec.add_child(ZinoUI.row("Player", ZinoUI.check("Player controlled", vd.get("playerControlled", true), func(v): _edit("Player Control", func(x): x["vehicle"]["playerControlled"] = v))))
	var profiles: Array = ZinoEntities.PROFILES.map(func(p): return [p, p.capitalize()])
	sec.add_child(ZinoUI.row("Physics profile", ZinoUI.option(profiles, s.get("profile", "arcade"), func(v): _edit("Physics Profile", func(x):
		var color = x["vehicle"]["spec"].get("bodyColor")
		var spec := ZinoEntities.default_vehicle_spec(v)
		spec["bodyColor"] = color
		x["vehicle"]["spec"] = spec, true))))
	sec.add_child(ZinoUI.row("Paint", ZinoUI.color_button(ZinoFormat.col(s.get("bodyColor")), func(c): _spec("Paint", "bodyColor", ZinoFormat.arr_col(c)))))
	sec.add_child(ZinoUI.row("Mass", ZinoUI.spin(50, 20000, 10, float(s.get("massKg", 1350)), func(v): _spec("Mass", "massKg", v), " kg")))
	_box.add_child(sec)
	var eng := ZinoUI.section("Engine & Transmission")
	eng.add_child(ZinoUI.row("Drive", ZinoUI.option([["rwd", "Rear-wheel"], ["fwd", "Front-wheel"], ["awd", "All-wheel"]], s.get("drive", "rwd"), func(v): _edit("Drive", func(x):
		var sp: Dictionary = x["vehicle"]["spec"]
		sp["drive"] = v
		for w in sp["wheels"]:
			w["drive"] = (v == "awd") or (v == "fwd" and w["steer"]) or (v == "rwd" and not w["steer"])))))
	eng.add_child(ZinoUI.row("Engine force", ZinoUI.spin(10, 50000, 50, float(s.get("maxEngineForce", 6500)), func(v): _spec("Engine Force", "maxEngineForce", v))))
	eng.add_child(ZinoUI.row("Top speed", ZinoUI.spin(10, 600, 1, float(s.get("topSpeedKmh", 230)), func(v): _spec("Top Speed", "topSpeedKmh", v), " km/h")))
	eng.add_child(ZinoUI.row("Max RPM", ZinoUI.spin(1000, 20000, 100, float(s.get("maxRpm", 7200)), func(v): _spec("Max RPM", "maxRpm", v))))
	eng.add_child(ZinoUI.row("Final drive", ZinoUI.spin(0.5, 10, 0.05, float(s.get("finalDrive", 3.7)), func(v): _spec("Final Drive", "finalDrive", v))))
	eng.add_child(ZinoUI.row("Gearbox", ZinoUI.check("Automatic (%d gears)" % s.get("gearRatios", []).size(), s.get("automatic", true), func(v): _spec("Gearbox", "automatic", v))))
	_box.add_child(eng)
	var ch := ZinoUI.section("Chassis, Tires & Brakes")
	ch.add_child(ZinoUI.row("Steer angle", ZinoUI.spin(1, 70, 0.5, float(s.get("maxSteerAngle", 32)), func(v): _spec("Steer Angle", "maxSteerAngle", v), "°")))
	ch.add_child(ZinoUI.row("Front grip", ZinoUI.spin(0.1, 30, 0.1, float(s.get("tireFrictionSlip", 10.5)), func(v): _spec("Front Grip", "tireFrictionSlip", v))))
	ch.add_child(ZinoUI.row("Rear grip", ZinoUI.spin(0.1, 30, 0.1, float(s.get("rearFrictionSlip", 10.5)), func(v): _spec("Rear Grip", "rearFrictionSlip", v))))
	ch.add_child(ZinoUI.row("Spring stiffness", ZinoUI.spin(1, 500, 0.5, float(s.get("suspensionStiffness", 45)), func(v): _spec("Suspension", "suspensionStiffness", v))))
	ch.add_child(ZinoUI.row("Suspension travel", ZinoUI.spin(0.01, 1.0, 0.01, float(s.get("suspensionTravel", 0.25)), func(v): _spec("Suspension Travel", "suspensionTravel", v), " m")))
	ch.add_child(ZinoUI.row("Brake force", ZinoUI.spin(0, 500, 1, float(s.get("maxBrakeForce", 40)), func(v): _spec("Brakes", "maxBrakeForce", v))))
	ch.add_child(ZinoUI.row("Downforce", ZinoUI.spin(0, 20, 0.1, float(s.get("downforce", 2.5)), func(v): _spec("Downforce", "downforce", v))))
	ch.add_child(ZinoUI.dim("Wheels: %s" % ", ".join(s.get("wheels", []).map(func(w): return "%s%s%s" % [w["name"], " steer" if w["steer"] else "", " drive" if w["drive"] else ""])), 11))
	_box.add_child(ch)

func _spec(label: String, key: String, value) -> void:
	_edit(label, func(x): x["vehicle"]["spec"][key] = value)

func _road(e: Dictionary) -> void:
	var r: Dictionary = e.get("road", {})
	var sec := ZinoUI.section("Road")
	sec.add_child(ZinoUI.row("Width", ZinoUI.spin(2, 60, 0.1, float(r.get("width", 12)), func(v): _road_set("Road Width", "width", v), " m")))
	sec.add_child(ZinoUI.row("Banking", ZinoUI.spin(-30, 30, 0.5, float(r.get("banking", 0)), func(v): _road_set("Road Banking", "banking", v), "°")))
	sec.add_child(ZinoUI.row("Shoulder", ZinoUI.spin(0, 10, 0.1, float(r.get("shoulderWidth", 1.2)), func(v): _road_set("Shoulder", "shoulderWidth", v), " m")))
	var surfaces: Array = ["asphalt", "concrete", "dirt", "gravel", "grass"].map(func(p): return [p, p.capitalize()])
	sec.add_child(ZinoUI.row("Surface", ZinoUI.option(surfaces, r.get("surface", "asphalt"), func(v): _road_set("Road Surface", "surface", v))))
	sec.add_child(ZinoUI.row("Loop", ZinoUI.check("Closed circuit", r.get("closed", true), func(v): _road_set("Road Loop", "closed", v))))
	sec.add_child(ZinoUI.row("Markings", ZinoUI.check("Edge lines", r.get("edgeLines", true), func(v): _road_set("Edge Lines", "edgeLines", v))))
	sec.add_child(ZinoUI.row("Smoothness", ZinoUI.spin(2, 64, 1, float(r.get("samplesPerSegment", 14)), func(v): _road_set("Road Smoothness", "samplesPerSegment", int(v)))))
	var pts: Array = r.get("points", [])
	sec.add_child(ZinoUI.dim("%d control points · centreline %.0f m" % [pts.size(), ZinoRoadBuilder.centerline_length(r)], 12))
	var h := ZinoUI.hbox(6)
	h.add_child(ZinoUI.button("Add point", func(): _edit("Add Road Point", func(x):
		var p: Array = x["road"]["points"]
		if p.size() >= 2:
			var a := ZinoFormat.v3(p[p.size() - 2])
			var b := ZinoFormat.v3(p[p.size() - 1])
			p.append(ZinoFormat.arr3(b + (b - a)))
		else:
			p.append([0.0, 0.0, -20.0 * p.size()]), true)))
	h.add_child(ZinoUI.button("Remove last", func(): _edit("Remove Road Point", func(x):
		if x["road"]["points"].size() > 2:
			x["road"]["points"].pop_back(), true)))
	sec.add_child(h)
	var pts_box := ZinoUI.vbox(4)
	for i in pts.size():
		var idx := i
		pts_box.add_child(ZinoUI.vec3_row("P%d" % i, ZinoFormat.v3(pts[i]), 0.1, func(v): _edit("Move Road Point", func(x): x["road"]["points"][idx] = ZinoFormat.arr3(v))))
	sec.add_child(pts_box)
	_box.add_child(sec)

func _road_set(label: String, key: String, value) -> void:
	_edit(label, func(x): x["road"][key] = value, key == "closed")

func _trigger(e: Dictionary) -> void:
	var t: Dictionary = e.get("trigger", {})
	var sec := ZinoUI.section("Start / Finish" if e["type"] == ZinoEntities.TYPE_START_FINISH else "Checkpoint")
	sec.add_child(ZinoUI.row("Order", ZinoUI.spin(0, 999, 1, float(t.get("index", 0)), func(v): _edit("Checkpoint Order", func(x): x["trigger"]["index"] = int(v)))))
	sec.add_child(ZinoUI.vec3_row("Size", ZinoFormat.v3(t.get("size"), Vector3(14, 4, 1)), 0.1, func(v): _edit("Trigger Size", func(x): x["trigger"]["size"] = ZinoFormat.arr3(v))))
	sec.add_child(ZinoUI.dim("Lap counting and race rules arrive with the RaceManager (Phase 6).", 11))
	_box.add_child(sec)
