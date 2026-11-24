class_name ZinoWorldStudio
extends ScrollContainer
## Open World tools: terrain sculpting and painting brushes, vegetation, water, buildings,
## traffic and streaming distances. Brush strokes are single undoable commands.

var session: ZinoEditorSession
var viewport_panel: ZinoViewportPanel
var brush_active := false
var brush := {"mode": "raise", "radius": 18.0, "strength": 1.0}
var _box: VBoxContainer
var _stroke_h := PackedFloat32Array()
var _stroke_paint := PackedByteArray()
var _stroke_id := ""
var _last_rebuild := 0

const MODES := [["raise", "Raise"], ["lower", "Lower"], ["smooth", "Smooth"], ["flatten", "Flatten"],
	["paintGrass", "Paint grass"], ["paintDirt", "Paint dirt"], ["paintRock", "Paint rock"], ["paintSand", "Paint sand"], ["paintAuto", "Erase paint"]]

func setup(s: ZinoEditorSession, vp: ZinoViewportPanel) -> void:
	session = s
	viewport_panel = vp
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = ZinoUI.vbox(8)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(ZinoUI.margin(_box, 10))
	get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session.selection_changed.connect(func(_i): rebuild())
	session.scene_changed.connect(func(c):
		if _stroke_id == "":
			rebuild.call_deferred())
	vp.world_brush = self
	rebuild()

func terrain_entity() -> Dictionary:
	for id in session.selection:
		var e := ZinoFormat.find_entity(session.scene(), id)
		if e.get("type") == ZinoEntities.TYPE_TERRAIN:
			return e
	for e in session.scene().entities:
		if e.type == ZinoEntities.TYPE_TERRAIN:
			return e
	return {}

func rebuild() -> void:
	if _box == null:
		return
	for c in _box.get_children():
		c.queue_free()
	_box.add_child(ZinoUI.heading("Open World", 18))
	var add := ZinoUI.section("Add to world")
	var g := GridContainer.new()
	g.columns = 2
	for k in ["terrain", "vegetation", "water", "building"]:
		var kind: String = k
		var b := ZinoUI.button(ZinoEntities.CREATABLE[kind], func(): session.add_entity(kind))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
	add.add_child(g)
	add.add_child(ZinoUI.button("Tunnel walls on selected road", func():
		for id in session.selection:
			var e := ZinoFormat.find_entity(session.scene(), id)
			if e.get("type") == ZinoEntities.TYPE_ROAD:
				var t := ZinoTrackTools.barrier(id, "both", "tunnel")
				t["name"] = "Tunnel"
				session.execute(ZinoSceneEdits.create(session.scene(), [t], "Add Tunnel"))))
	_box.add_child(add)

	var te := terrain_entity()
	var ts := ZinoUI.section("Terrain brushes")
	if te.is_empty():
		ts.add_child(ZinoUI.dim("Add a terrain to sculpt and paint it.", 12))
	else:
		ts.add_child(ZinoUI.row("Brush", ZinoUI.toggle("Sculpt / paint in viewport", brush_active, func(on): brush_active = on), 90))
		ts.add_child(ZinoUI.row("Mode", ZinoUI.option(MODES, brush.mode, func(m): brush.mode = m), 90))
		ts.add_child(ZinoUI.row("Radius", ZinoUI.spin(2, 200, 1, brush.radius, func(x): brush.radius = x, " m"), 90))
		ts.add_child(ZinoUI.row("Strength", ZinoUI.spin(0.05, 5, 0.05, brush.strength, func(x): brush.strength = x), 90))
		ts.add_child(ZinoUI.dim("With the brush on, left-drag on the terrain. Each stroke is one undo step.", 11))
		var t: Dictionary = te.terrain
		var tid: String = te.id
		var set_t := func(key: String, value):
			session.execute(ZinoSceneEdits.modify(session.scene(), [tid], func(x): x.terrain[key] = value, "Terrain " + key))
		ts.add_child(ZinoUI.row("Size", ZinoUI.spin(100, 8000, 10, float(t.get("size", 1200)), func(x): set_t.call("size", x), " m"), 90))
		ts.add_child(ZinoUI.row("Height", ZinoUI.spin(0, 500, 1, float(t.get("height", 60)), func(x): set_t.call("height", x), " m"), 90))
		ts.add_child(ZinoUI.row("Seed", ZinoUI.spin(1, 99999, 1, float(t.get("seed", 3)), func(x): set_t.call("seed", int(x))), 90))
		ts.add_child(ZinoUI.row("Detail", ZinoUI.option([[65, "Low (65²)"], [129, "Medium (129²)"], [257, "High (257²)"]], int(t.get("resolution", 129)), func(x): set_t.call("resolution", x)), 90))
		ts.add_child(ZinoUI.row("Roads", ZinoUI.check("Flatten terrain under roads", t.get("flattenRoads", true), func(b): set_t.call("flattenRoads", b)), 90))
		ts.add_child(ZinoUI.row("Stream", ZinoUI.spin(100, 10000, 10, float(t.get("streamDistance", 900)), func(x): set_t.call("streamDistance", x), " m"), 90))
		if str(t.get("heights", "")) != "":
			ts.add_child(ZinoUI.button("Reset sculpting (regenerate from seed)", func():
				session.execute(ZinoSceneEdits.modify(session.scene(), [tid], func(x):
					x.terrain.heights = ""
					x.terrain.paint = "", "Reset Terrain"))))
	_box.add_child(ts)

	var tr := ZinoUI.section("Traffic")
	var traffic: Dictionary = session.scene().settings.get("traffic", {"count": 0, "speedKmh": 55.0})
	var set_tr := func(key: String, value):
		var st: Dictionary = session.scene().settings.duplicate(true)
		var t2: Dictionary = st.get("traffic", {"count": 0, "speedKmh": 55.0})
		t2[key] = value
		st["traffic"] = t2
		session.execute(ZinoSceneEdits.settings(session.scene(), st, "Traffic"))
	tr.add_child(ZinoUI.row("Cars", ZinoUI.spin(0, 24, 1, float(traffic.get("count", 0)), func(x): set_tr.call("count", int(x))), 90))
	tr.add_child(ZinoUI.row("Speed", ZinoUI.spin(10, 150, 1, float(traffic.get("speedKmh", 55)), func(x): set_tr.call("speedKmh", x), " km/h"), 90))
	tr.add_child(ZinoUI.dim("Traffic drives the road network in the right-hand lane during play.", 11))
	_box.add_child(tr)

# --- Brush strokes (called by the viewport) ---------------------------------------------------

func wants_mouse() -> bool:
	return brush_active and session.mode == "edit" and not terrain_entity().is_empty()

func begin_stroke() -> void:
	var te := terrain_entity()
	_stroke_id = te.id
	_stroke_h = viewport_panel.builder.terrain_heights.get(te.id, PackedFloat32Array()).duplicate()
	var res := int(te.terrain.get("resolution", 129))
	_stroke_paint = Marshalls.base64_to_raw(str(te.terrain.get("paint", ""))) if str(te.terrain.get("paint", "")) != "" else PackedByteArray()
	if _stroke_paint.size() != res * res:
		_stroke_paint = PackedByteArray()
		_stroke_paint.resize(res * res)

## Applies the brush at a world position (from a ray hit on the terrain).
func apply_at(world: Vector3, delta: float) -> void:
	if _stroke_id == "":
		return
	var te := ZinoFormat.find_entity(session.scene(), _stroke_id)
	var t: Dictionary = te.terrain
	var res := int(t.get("resolution", 129))
	var size := float(t.get("size", 1200.0))
	var local := ZinoFormat.transform_from_entity(te).affine_inverse() * world
	var cell := size / (res - 1)
	var cx := (local.x / size + 0.5) * (res - 1)
	var cz := (local.z / size + 0.5) * (res - 1)
	var r := float(brush.radius) / cell
	var center_h := ZinoWorld.sample(_stroke_h, res, size, local.x, local.z)
	var paint_code := {"paintGrass": 1, "paintDirt": 2, "paintRock": 3, "paintSand": 4, "paintAuto": 0}
	for z in range(maxi(0, int(cz - r)), mini(res, int(cz + r) + 2)):
		for x in range(maxi(0, int(cx - r)), mini(res, int(cx + r) + 2)):
			var d := Vector2(x - cx, z - cz).length() / r
			if d > 1.0:
				continue
			var fall := 0.5 + 0.5 * cos(d * PI)
			var i := z * res + x
			var k := float(brush.strength) * fall * delta * 12.0
			match brush.mode:
				"raise": _stroke_h[i] += k
				"lower": _stroke_h[i] -= k
				"flatten": _stroke_h[i] = lerpf(_stroke_h[i], center_h, clampf(k * 0.3, 0.0, 1.0))
				"smooth":
					var avg := (_stroke_h[i] + _stroke_h[z * res + mini(x + 1, res - 1)] + _stroke_h[z * res + maxi(x - 1, 0)] + _stroke_h[mini(z + 1, res - 1) * res + x] + _stroke_h[maxi(z - 1, 0) * res + x]) / 5.0
					_stroke_h[i] = lerpf(_stroke_h[i], avg, clampf(k * 0.3, 0.0, 1.0))
				_:
					if fall > 0.3:
						_stroke_paint[i] = paint_code.get(brush.mode, 0)
	# Live preview: rebuild the terrain visuals at most 8 times per second.
	if Time.get_ticks_msec() - _last_rebuild > 125:
		_last_rebuild = Time.get_ticks_msec()
		_preview(te)

func _preview(te: Dictionary) -> void:
	var n := viewport_panel.builder.node_for(te.id)
	if n == null:
		return
	for c in n.get_children():
		if not str(c.name).begins_with("Editor"):
			c.free()
	var t: Dictionary = te.terrain.duplicate()
	t["paint"] = Marshalls.raw_to_base64(_stroke_paint)
	ZinoWorld.build_terrain(n, t, _stroke_h)

func end_stroke() -> void:
	if _stroke_id == "":
		return
	var id := _stroke_id
	var h := ZinoWorld.encode_heights(_stroke_h)
	var p := Marshalls.raw_to_base64(_stroke_paint)
	var label := "Paint Terrain" if str(brush.mode).begins_with("paint") else "Sculpt Terrain"
	_stroke_id = ""
	session.execute(ZinoSceneEdits.modify(session.scene(), [id], func(x):
		x.terrain["heights"] = h
		x.terrain["paint"] = p, label))
