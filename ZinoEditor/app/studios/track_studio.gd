class_name ZinoTrackStudio
extends ScrollContainer
## Track Studio tools: generate circuits, and for the selected road add barriers, checkpoints/sectors,
## a starting grid, a pit lane, centre-line markings and preview the racing line.

var session: ZinoEditorSession
var viewport_panel: ZinoViewportPanel
var _box: VBoxContainer
var _gen := {"seed": 7, "radius": 90.0, "corners": 10, "irregularity": 0.35, "width": 12.0, "elevation": 0.0, "banking": 4.0}
var _line_mesh := ImmediateMesh.new()
var _line_node: MeshInstance3D

func setup(s: ZinoEditorSession, vp: ZinoViewportPanel) -> void:
	session = s
	viewport_panel = vp
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = ZinoUI.vbox(8)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(ZinoUI.margin(_box, 10))
	get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_node = MeshInstance3D.new()
	_line_node.mesh = _line_mesh
	_line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.viewport.add_child(_line_node)
	session.selection_changed.connect(func(_i): rebuild())
	session.scene_changed.connect(func(_c): rebuild.call_deferred())
	rebuild()

func _road() -> Dictionary:
	for id in session.selection:
		var e := ZinoFormat.find_entity(session.scene(), id)
		if e.get("type") == ZinoEntities.TYPE_ROAD:
			return e
	for e in session.scene()["entities"]:
		if e.type == ZinoEntities.TYPE_ROAD:
			return e
	return {}

func _road_xform(e: Dictionary) -> Transform3D:
	var n := viewport_panel.builder.node_for(e.get("id", ""))
	return n.global_transform if n else ZinoFormat.transform_from_entity(e)

func rebuild() -> void:
	if _box == null:
		return
	for c in _box.get_children():
		c.queue_free()
	_box.add_child(ZinoUI.heading("Track Studio", 18))
	var g := ZinoUI.section("Generate circuit")
	for f in [["seed", "Seed", 1, 99999, 1], ["radius", "Size (radius)", 30, 600, 1], ["corners", "Control points", 5, 40, 1],
			["irregularity", "Irregularity", 0, 0.8, 0.01], ["width", "Width", 6, 30, 0.5], ["elevation", "Elevation", 0, 40, 0.5], ["banking", "Banking", 0, 20, 0.5]]:
		var key: String = f[0]
		g.add_child(ZinoUI.row(f[1], ZinoUI.spin(f[2], f[3], f[4], float(_gen[key]), func(x): _gen[key] = x), 120))
	var gh := ZinoUI.hbox(6)
	gh.add_child(ZinoUI.button("Random seed", func():
		_gen.seed = randi_range(1, 99999)
		rebuild()))
	gh.add_child(ZinoUI.accent_button("Generate", func(): generate(true)))
	g.add_child(gh)
	g.add_child(ZinoUI.dim("Creates an editable road with start/finish, checkpoints, a grid and guardrails.", 11))
	_box.add_child(g)

	var road := _road()
	if road.is_empty():
		_box.add_child(ZinoUI.dim("Add or generate a road to use the track tools.", 12))
		_draw_line([])
		return
	var xf := _road_xform(road)
	var st := ZinoTrackTools.stats(road.road, xf)
	var t := ZinoUI.section("Road: " + str(road.name))
	t.add_child(ZinoUI.dim("%.0f m %s · %d corners · tightest radius %.0f m" % [st.length, "circuit" if st.closed else "open road", st.corners, st.minRadius], 12))
	var rid: String = road.id
	var bh := ZinoUI.hbox(6)
	bh.add_child(ZinoUI.button("Guardrails", func(): add_barrier(rid, "guardrail")))
	bh.add_child(ZinoUI.button("Walls", func(): add_barrier(rid, "wall")))
	bh.add_child(ZinoUI.button("Tyres", func(): add_barrier(rid, "tires")))
	t.add_child(ZinoUI.row("Barriers", bh, 90))
	var cp := {"n": 4}
	var ch := ZinoUI.hbox(6)
	ch.add_child(ZinoUI.spin(1, 40, 1, 4, func(x): cp.n = int(x)))
	ch.add_child(ZinoUI.button("Place", func(): place_checkpoints(rid, cp.n)))
	t.add_child(ZinoUI.row("Sectors", ch, 90))
	var gr := {"n": 6}
	var grh := ZinoUI.hbox(6)
	grh.add_child(ZinoUI.spin(1, 24, 1, 6, func(x): gr.n = int(x)))
	grh.add_child(ZinoUI.button("Place grid", func(): place_grid(rid, gr.n)))
	t.add_child(ZinoUI.row("Grid slots", grh, 90))
	t.add_child(ZinoUI.row("Pit lane", ZinoUI.button("Add pit lane", func(): add_pit_lane(rid)), 90))
	t.add_child(ZinoUI.row("Markings", ZinoUI.check("Dashed centre line", road.road.get("centerLine", false), func(b):
		session.execute(ZinoSceneEdits.modify(session.scene(), [rid], func(x): x.road["centerLine"] = b, "Centre Line"))), 90))
	t.add_child(ZinoUI.row("Racing line", ZinoUI.check("AI uses the optimised line", road.road.get("racingLine", true), func(b):
		session.execute(ZinoSceneEdits.modify(session.scene(), [rid], func(x): x.road["racingLine"] = b, "Racing Line"))), 90))
	_box.add_child(t)
	_draw_line(ZinoTrackTools.racing_line(road.road, xf) if road.road.get("racingLine", true) else PackedVector3Array())
	var leg := ZinoUI.dim("Magenta line in the viewport: computed racing line. Drag the blue handles to reshape the road.", 11)
	leg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(leg)

func _draw_line(pts) -> void:
	_line_mesh.clear_surfaces()
	if pts.size() < 2 or session.mode != "edit":
		return
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, ZinoMaterials.unshaded(Color(1.0, 0.2, 0.75), true))
	for p in pts:
		_line_mesh.surface_add_vertex(p + Vector3.UP * 0.25)
	_line_mesh.surface_add_vertex(pts[0] + Vector3.UP * 0.25)
	_line_mesh.surface_end()

# --- Actions (each is one undoable command) ------------------------------------------------------

## Generates a complete circuit; replace=true removes the previous generated track group first.
func generate(replace: bool) -> String:
	var ents := ZinoTrackTools.generate_circuit(_gen)
	var road: Dictionary = ents[0]
	var group := ZinoEntities.empty("Generated Track")
	group["generated"] = true
	road.parentId = group.id
	var xf := Transform3D.IDENTITY
	var all: Array = [group, road]
	for e in ZinoTrackTools.checkpoints(road.road, xf, 4):
		e.parentId = group.id
		all.append(e)
	var grid := ZinoTrackTools.grid(road.road, xf, 6)
	for e in grid:
		e.parentId = group.id
		all.append(e)
	var rail := ZinoTrackTools.barrier(road.id, "both", "guardrail")
	rail.parentId = group.id
	all.append(rail)
	var old: Array = []
	if replace:
		for e in session.scene()["entities"]:
			if e.get("generated", false):
				old.append(e.id)
	if not old.is_empty():
		session.execute(ZinoSceneEdits.delete(session.scene(), old, "Remove Old Track"))
	session.execute(ZinoSceneEdits.create(session.scene(), all, "Generate Circuit"))
	# Put the player car and its camera on the first grid slot.
	var slot: Dictionary = grid[0]
	var car := {}
	for e in session.scene()["entities"]:
		if e.type == ZinoEntities.TYPE_VEHICLE:
			car = e
			break
	if not car.is_empty():
		var p := ZinoFormat.v3(slot.transform.position)
		var ride: float = float(car.vehicle.spec.wheelRadius) + float(car.vehicle.spec.suspensionRestLength) + ZinoFormat.v3(car.vehicle.spec.bodySize).y * 0.5
		var t := {car.id: {"position": p + Vector3.UP * ride, "rotation": ZinoFormat.v3(slot.transform.rotation), "scale": Vector3.ONE}}
		session.execute(ZinoSceneEdits.set_transforms(session.scene(), t, "Place Car on Grid"))
	session.select([road.id])
	viewport_panel.frame_all()
	ZinoAppLog.info("Track", "Generated circuit (seed %d, %.0f m)" % [_gen.seed, ZinoTrackTools.stats(road.road, xf).length])
	return road.id

func add_barrier(road_id: String, style: String) -> void:
	var b := ZinoTrackTools.barrier(road_id, "both", style)
	session.execute(ZinoSceneEdits.create(session.scene(), [b], "Add Barriers"))

func place_checkpoints(road_id: String, count: int) -> void:
	var road := ZinoFormat.find_entity(session.scene(), road_id)
	var old: Array = session.scene()["entities"].filter(func(e): return e.type in [ZinoEntities.TYPE_CHECKPOINT, ZinoEntities.TYPE_START_FINISH]).map(func(e): return e.id)
	if not old.is_empty():
		session.execute(ZinoSceneEdits.delete(session.scene(), old, "Remove Checkpoints"))
	session.execute(ZinoSceneEdits.create(session.scene(), ZinoTrackTools.checkpoints(road.road, _road_xform(road), count), "Place Checkpoints"))

func place_grid(road_id: String, count: int) -> void:
	var road := ZinoFormat.find_entity(session.scene(), road_id)
	var old: Array = session.scene()["entities"].filter(func(e): return e.type == ZinoEntities.TYPE_SPAWN).map(func(e): return e.id)
	if not old.is_empty():
		session.execute(ZinoSceneEdits.delete(session.scene(), old, "Remove Grid"))
	session.execute(ZinoSceneEdits.create(session.scene(), ZinoTrackTools.grid(road.road, _road_xform(road), count), "Place Grid"))

func add_pit_lane(road_id: String) -> void:
	var road := ZinoFormat.find_entity(session.scene(), road_id)
	session.execute(ZinoSceneEdits.create(session.scene(), [ZinoTrackTools.pit_lane(road.road, _road_xform(road))], "Add Pit Lane"))
