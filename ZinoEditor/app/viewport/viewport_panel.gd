class_name ZinoViewportPanel
extends Control
## The Zino Editor's 3D viewport. It renders the real Godot scene built by ZinoSceneBuilder (the same
## code exported games run), with an editor camera, picking, a transform gizmo, grid, selection boxes,
## orthographic views and an in-editor playtest that drives the real vehicle physics.

signal tool_changed(tool: String)
signal stats_changed(text: String)
signal block_traced(node_id: String)
signal block_error(node_id: String, message: String)
signal stop_requested()

var session: ZinoEditorSession
var container: SubViewportContainer
var viewport: SubViewport
var world_root: Node3D
var builder: ZinoSceneBuilder
var camera: ZinoEditorCamera
var gizmo: ZinoTransformGizmo
var overlays: ZinoViewportOverlays
var tool := "translate"          # select, translate, rotate, scale
var snap := false
var preview_preset := ZinoGraphics.DEFAULT_PRESET

var _view_label: Label
var _fps_label: Label
var _mode_badge: PanelContainer
var _hint: Label
var _drag := {}                  # active gizmo drag state
var _mouse_mode := ""            # "", orbit, pan
var _last_mouse := Vector2.ZERO
var _fly := false
var _press_pos := Vector2.ZERO
var _saved_editor_cam: Transform3D
var game: ZinoGameContext            # running playtest session
var env_preview: ZinoEnvironment     # time of day / weather preview while editing
var show_stats := false
var world_brush                      # ZinoWorldStudio when terrain brushes are available
var _brushing := false
var _brush_pos := Vector2.ZERO
var _road_handles: Node3D           # draggable control points of the selected road
var _road_line := ImmediateMesh.new()
var _box_start := Vector2.INF       # box selection start (panel coords)
var _box_rect: Panel
var _press_additive := false

func setup(editor_session: ZinoEditorSession) -> void:
	session = editor_session
	preview_preset = session.preview_preset()
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	container = SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.physics_object_picking = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	world_root = Node3D.new()
	world_root.name = "ZinoWorld"
	viewport.add_child(world_root)
	camera = ZinoEditorCamera.new()
	camera.name = "EditorCamera"
	viewport.add_child(camera)
	camera.current = true
	camera.view_changed.connect(_on_view_changed)
	overlays = ZinoViewportOverlays.new()
	overlays.name = "Overlays"
	viewport.add_child(overlays)
	gizmo = ZinoTransformGizmo.new()
	gizmo.name = "Gizmo"
	viewport.add_child(gizmo)
	gizmo.visible = false
	_road_handles = Node3D.new()
	_road_handles.name = "RoadHandles"
	viewport.add_child(_road_handles)
	var line_mi := MeshInstance3D.new()
	line_mi.mesh = _road_line
	line_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(line_mi)
	builder = ZinoSceneBuilder.new(world_root, ZinoSceneBuilder.MODE_EDIT, preview_preset)
	_build_overlay_ui()
	apply_quality()
	builder.build(session.scene())
	_refresh_env_preview()
	overlays.set_grid_visible(session.app.settings.get_value("showGrid", true))
	snap = session.app.settings.get_value("snapEnabled", false)
	session.scene_changed.connect(_on_scene_changed)
	session.selection_changed.connect(func(_ids): _refresh_selection())
	session.placement_provider = func(): return _placement_point()
	frame_all.call_deferred()

# --- Quality --------------------------------------------------------------------------

func set_preview_preset(p: String) -> void:
	preview_preset = p
	apply_quality()
	builder.graphics_preset = p
	if session.mode == "edit":
		builder.build(session.scene())
		_refresh_selection()

func apply_quality() -> void:
	ZinoGraphics.apply_viewport(viewport, preview_preset)
	if session.app.settings.get_value("lightweightMode", false) and session.mode == "edit":
		viewport.scaling_3d_scale = minf(viewport.scaling_3d_scale, 0.5)
	var warn := ZinoGraphics.capability_warnings(preview_preset)
	for w in warn:
		ZinoAppLog.warn("Graphics", w)

# --- Overlay UI ------------------------------------------------------------------------------

func _build_overlay_ui() -> void:
	var top := ZinoUI.hbox(6)
	top.position = Vector2(10, 8)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(top)
	var view_btn := MenuButton.new()
	view_btn.text = "Perspective"
	view_btn.flat = false
	view_btn.focus_mode = Control.FOCUS_NONE
	for v in ["Perspective", "Top", "Front", "Side"]:
		view_btn.get_popup().add_item(v)
	view_btn.get_popup().index_pressed.connect(func(i): set_view(view_btn.get_popup().get_item_text(i)))
	top.add_child(view_btn)
	_view_label = view_btn.get_child(0) as Label if view_btn.get_child_count() > 0 else null
	set_meta("view_button", view_btn)
	top.add_child(ZinoUI.toggle("Grid", session.app.settings.get_value("showGrid", true), func(on):
		overlays.set_grid_visible(on)
		session.app.settings.set_value("showGrid", on), "Toggle grid (G)"))
	_fps_label = ZinoUI.label("", 12, ZinoTheme.TEXT_DIM)
	_fps_label.position = Vector2(12, 0)
	_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_fps_label.offset_top = -26
	_fps_label.offset_left = 12
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps_label)
	_hint = ZinoUI.label("RMB drag: orbit · MMB / Shift+RMB: pan · Wheel: zoom · RMB+WASD: fly · F: frame", 12, ZinoTheme.TEXT_DIM)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.offset_top = -26
	_hint.offset_right = -12
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_mode_badge = ZinoUI.pill("  ● PLAYING — W/S throttle & brake · A/D steer · Space handbrake · R reset · C camera  ", ZinoTheme.ACCENT)
	_mode_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mode_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mode_badge.offset_top = 10
	_mode_badge.visible = false
	_mode_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mode_badge)
	_box_rect = Panel.new()
	_box_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_rect.add_theme_stylebox_override("panel", ZinoTheme.box(Color(ZinoTheme.ACCENT, 0.12), 3, ZinoTheme.ACCENT, 1, 0))
	_box_rect.visible = false
	add_child(_box_rect)

func _on_view_changed(view: String) -> void:
	var b: MenuButton = get_meta("view_button")
	b.text = view
	overlays.set_grid_plane(view)

func set_view(view: String) -> void:
	camera.set_view(view)

# --- Per-frame -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if session == null:
		return
	if _fly and session.mode == "edit":
		var dir := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): dir.z += 1
		if Input.is_physical_key_pressed(KEY_S): dir.z -= 1
		if Input.is_physical_key_pressed(KEY_D): dir.x += 1
		if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
		if Input.is_physical_key_pressed(KEY_E): dir.y += 1
		if Input.is_physical_key_pressed(KEY_Q): dir.y -= 1
		if dir != Vector3.ZERO:
			camera.fly(dir, delta, Input.is_physical_key_pressed(KEY_SHIFT))
	if _brushing:
		var hit := _raycast(_brush_pos, ZinoSceneBuilder.GAMEPLAY_LAYER)
		if not hit.is_empty():
			world_brush.apply_at(hit.position, delta)
	_update_gizmo()
	if not _drag.is_empty():
		_refresh_selection_boxes()
	var txt := "%d FPS · %s preview" % [Engine.get_frames_per_second(), ZinoGraphics.label(preview_preset)]
	if session.mode != "edit":
		var car := builder.player_vehicle()
		if car:
			txt += "   ·   %d km/h  gear %s  %d rpm" % [int(car.speed_kmh), "R" if car.gear == -1 else str(car.gear), int(car.rpm)]
	if show_stats:
		txt += "   ·   %d draw calls · %dk primitives · VRAM %d MB · RAM %d MB" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
			int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)]
	_fps_label.text = txt

func _update_gizmo() -> void:
	var nodes := _selected_nodes()
	var show := session.mode == "edit" and tool != "select" and not nodes.is_empty()
	gizmo.visible = show
	if not show:
		return
	if _drag.is_empty():
		var center := Vector3.ZERO
		for n in nodes:
			center += n.global_position
		center /= nodes.size()
		gizmo.global_transform = Transform3D(nodes[0].global_transform.basis.orthonormalized() if gizmo.local_space else Basis(), center)
	gizmo.update_screen_size(camera)

# --- Input ----------------------------------------------------------------------------------

## Touch (iPad/iPhone): one finger drags to orbit (a short tap selects), two fingers pinch to zoom and
## drag to pan. Touching an object or gizmo still moves it, exactly like the mouse.
var _touches := {}
var _touch_moved := 0.0
var touch_ui := DisplayServer.is_touchscreen_available()

func _cancel_single_touch() -> void:
	_mouse_mode = "touch_multi"
	_box_start = Vector2.INF
	_box_rect.visible = false
	if not _drag.is_empty():
		_end_drag(false)
	if _brushing:
		_brushing = false
		world_brush.end_stroke()

func _gui_input(event: InputEvent) -> void:
	if session == null:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() >= 2:
			_cancel_single_touch()
		accept_event()
		return
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touches.size() >= 2 and _touches.has(sd.index):
			var ids: Array = _touches.keys()
			var a0: Vector2 = _touches[ids[0]]
			var b0: Vector2 = _touches[ids[1]]
			_touches[sd.index] = sd.position
			var a1: Vector2 = _touches[ids[0]]
			var b1: Vector2 = _touches[ids[1]]
			var d0 := a0.distance_to(b0)
			var d1 := a1.distance_to(b1)
			if d0 > 1.0 and d1 > 1.0:
				camera.zoom(log(d0 / d1) / log(1.15))
			camera.pan((a1 + b1) * 0.5 - (a0 + b0) * 0.5, size.y)
		elif _touches.has(sd.index):
			_touches[sd.index] = sd.position
		accept_event()
		return
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		if mg.factor > 0.0:
			camera.zoom(-log(mg.factor) / log(1.15))
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			grab_focus()
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed: camera.zoom(-1.0 * mb.factor if mb.factor > 0 else -1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed: camera.zoom(1.0 * mb.factor if mb.factor > 0 else 1.0)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_mouse_mode = "pan" if mb.shift_pressed else "orbit"
					_fly = session.mode == "edit"
				else:
					_mouse_mode = ""
					_fly = false
			MOUSE_BUTTON_MIDDLE:
				_mouse_mode = "pan" if mb.pressed else ""
			MOUSE_BUTTON_LEFT:
				if session.mode != "edit":
					return
				if mb.pressed:
					if mb.alt_pressed:
						_mouse_mode = "orbit"
					else:
						_press_pos = mb.position
						_press_additive = mb.ctrl_pressed or mb.shift_pressed
						if world_brush and world_brush.wants_mouse():
							_brushing = true
							_brush_pos = mb.position
							world_brush.begin_stroke()
						elif not _try_begin_road_drag(mb.position) and not _try_begin_drag(mb.position):
							if touch_ui:
								_mouse_mode = "touch_orbit"
								_touch_moved = 0.0
							else:
								_box_start = mb.position
				else:
					if _mouse_mode == "touch_orbit" or _mouse_mode == "touch_multi":
						if _mouse_mode == "touch_orbit" and _touch_moved < 10.0:
							_pick(_press_pos, _press_additive)
						_mouse_mode = ""
						_last_mouse = mb.position
						accept_event()
						return
					if _mouse_mode == "orbit":
						_mouse_mode = ""
					if _brushing:
						_brushing = false
						world_brush.end_stroke()
					elif not _drag.is_empty():
						_end_drag(true)
					elif _box_start != Vector2.INF:
						if _box_rect.visible:
							_box_select(Rect2(_box_start, mb.position - _box_start).abs(), _press_additive)
						else:
							_pick(_press_pos, _press_additive)
						_box_start = Vector2.INF
						_box_rect.visible = false
		_last_mouse = mb.position
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var d := mm.position - _last_mouse
		_last_mouse = mm.position
		if _brushing:
			_brush_pos = mm.position
		elif not _drag.is_empty():
			if _drag.get("kind") == "road":
				_update_road_drag(mm.position)
			else:
				_update_drag(mm.position, mm.shift_pressed)
		elif _box_start != Vector2.INF and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			if mm.position.distance_to(_box_start) > 6.0:
				var rect := Rect2(_box_start, mm.position - _box_start).abs()
				_box_rect.position = rect.position
				_box_rect.size = rect.size
				_box_rect.visible = true
		elif _mouse_mode == "touch_orbit":
			_touch_moved += d.length()
			if _touch_moved >= 10.0:
				camera.orbit(d)
		elif _mouse_mode == "touch_multi":
			pass
		elif _mouse_mode == "orbit":
			camera.orbit(d)
		elif _mouse_mode == "pan":
			camera.pan(d, size.y)
		elif session.mode == "edit" and gizmo.visible:
			gizmo.set_hover(_gizmo_hit(mm.position))
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not _drag.is_empty():
		_end_drag(false)
		accept_event()

func _ray(pos: Vector2) -> Dictionary:
	var vp_pos := pos * Vector2(viewport.size) / size
	return {"from": camera.project_ray_origin(vp_pos), "dir": camera.project_ray_normal(vp_pos)}

func _raycast(pos: Vector2, mask: int) -> Dictionary:
	var r := _ray(pos)
	var q := PhysicsRayQueryParameters3D.create(r.from, r.from + r.dir * 10000.0, mask)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return viewport.find_world_3d().direct_space_state.intersect_ray(q)

func _gizmo_hit(pos: Vector2) -> String:
	if not gizmo.visible:
		return ""
	var hit := _raycast(pos, ZinoTransformGizmo.GIZMO_LAYER)
	if hit.is_empty():
		return ""
	return str(hit.collider.get_meta("gizmo_axis", ""))

func _pick(pos: Vector2, additive: bool) -> void:
	var hit := _raycast(pos, ZinoSceneBuilder.PICK_LAYER)
	if hit.is_empty():
		if not additive:
			session.select([])
		return
	var id := ZinoSceneBuilder.entity_id_of(hit.collider)
	if id != "":
		session.select([id], additive)

# --- Gizmo dragging ----------------------------------------------------------------------------

func _try_begin_drag(pos: Vector2) -> bool:
	var axis := _gizmo_hit(pos)
	if axis == "":
		return false
	var nodes := _selected_nodes()
	if nodes.is_empty():
		return false
	var starts := {}
	for n in nodes:
		starts[ZinoSceneBuilder.entity_id_of(n)] = {"global": n.global_transform, "scale": n.scale}
	var pivot := gizmo.global_position
	var axis_dir := gizmo.axis_vector(axis)
	var cam_dir := -camera.global_transform.basis.z
	var normal: Vector3
	if tool == "rotate":
		normal = axis_dir
	elif axis == "xyz":
		normal = cam_dir
	else:
		normal = axis_dir.cross(cam_dir).cross(axis_dir).normalized()
		if normal.length() < 0.01:
			normal = cam_dir
	var plane := Plane(normal, pivot)
	var start_hit = _plane_hit(plane, pos)
	if start_hit == null:
		return false
	_drag = {"axis": axis, "axis_dir": axis_dir, "plane": plane, "start_hit": start_hit, "pivot": pivot,
		"starts": starts, "start_mouse": pos, "size": gizmo.world_size(), "local_axis": _local_axis_index(axis)}
	return true

func _plane_hit(plane: Plane, pos: Vector2):
	var r := _ray(pos)
	return plane.intersects_ray(r.from, r.dir)

func _local_axis_index(axis: String) -> int:
	return {"x": 0, "y": 1, "z": 2}.get(axis, -1)

func _update_drag(pos: Vector2, fine: bool) -> void:
	var hit = _plane_hit(_drag.plane, pos)
	if hit == null:
		return
	var settings := session.app.settings
	var axis: String = _drag.axis
	var a: Vector3 = _drag.axis_dir
	var delta: Vector3 = hit - _drag.start_hit
	var snapping := snap != Input.is_key_pressed(KEY_CTRL)
	for id in _drag.starts:
		var n := builder.node_for(id)
		if n == null:
			continue
		var st: Dictionary = _drag.starts[id]
		var g: Transform3D = st.global
		match tool:
			"translate":
				var move := delta if axis == "xyz" else a * delta.dot(a)
				if fine:
					move *= 0.1
				if snapping:
					var step := float(settings.get_value("translateSnap", 0.5))
					move = Vector3(snappedf(move.x, step), snappedf(move.y, step), snappedf(move.z, step))
				n.global_position = g.origin + move
			"rotate":
				var v0: Vector3 = _drag.start_hit - _drag.pivot
				var v1: Vector3 = hit - _drag.pivot
				var angle := atan2(a.dot(v0.cross(v1)), v0.dot(v1))
				if snapping:
					angle = deg_to_rad(snappedf(rad_to_deg(angle), float(settings.get_value("rotateSnap", 15.0))))
				var rot := Basis(a, angle)
				n.global_transform = Transform3D(rot * g.basis, _drag.pivot + rot * (g.origin - _drag.pivot))
			"scale":
				var factor: float
				if axis == "xyz":
					factor = 1.0 + (_drag.start_mouse.y - pos.y) / 150.0
				else:
					factor = 1.0 + delta.dot(a) / maxf(0.01, _drag.size)
				if snapping:
					factor = maxf(0.01, snappedf(factor, float(settings.get_value("scaleSnap", 0.1))))
				factor = maxf(0.001, factor)
				var s: Vector3 = st.scale
				if axis == "xyz":
					s *= factor
				else:
					s[_drag.local_axis] *= factor
				n.scale = s

func _end_drag(commit: bool) -> void:
	if _drag.get("kind") == "road":
		_end_road_drag(commit)
		return
	var transforms := {}
	for id in _drag.starts:
		var n := builder.node_for(id)
		if n == null:
			continue
		if commit:
			transforms[id] = {"position": n.position, "rotation": n.rotation_degrees, "scale": n.scale}
		else:
			n.global_transform = _drag.starts[id].global
			n.scale = _drag.starts[id].scale
	var label: String = {"translate": "Move", "rotate": "Rotate", "scale": "Scale"}.get(tool, "Transform")
	_drag = {}
	if commit and not transforms.is_empty():
		session.execute(ZinoSceneEdits.set_transforms(session.scene(), transforms, label))

# --- Scene sync ------------------------------------------------------------------------------

func _on_scene_changed(changes: Dictionary) -> void:
	if session.mode != "edit":
		return
	builder.apply_changes(session.scene(), changes)
	if changes.get("settingsChanged", false) or changes.get("reloaded", false) or not changes.get("added", []).is_empty():
		_refresh_env_preview()
	_refresh_selection()

func _refresh_env_preview() -> void:
	if env_preview:
		env_preview.free()
		env_preview = null
	if session.mode != "edit":
		return
	env_preview = ZinoEnvironment.new()
	viewport.add_child(env_preview)
	env_preview.camera_provider = func(): return camera
	var sun: DirectionalLight3D = null
	for e in session.scene().entities:
		if e.type == ZinoEntities.TYPE_LIGHT and e.light.get("kind") == "directional":
			sun = builder.node_for(e.id) as DirectionalLight3D
			break
	env_preview.setup(builder.environment_node(), sun, session.scene().get("settings", {}))

func _selected_nodes() -> Array:
	var out: Array = []
	for id in session.selection:
		var n := builder.node_for(id)
		if n:
			out.append(n)
	return out

func _refresh_selection() -> void:
	_refresh_selection_boxes()
	_rebuild_road_handles()

# --- Road control points ------------------------------------------------------------------------

func _selected_road() -> Dictionary:
	if session.mode != "edit" or session.selection.size() != 1:
		return {}
	var e := ZinoFormat.find_entity(session.scene(), session.selection[0])
	return e if e.get("type") == ZinoEntities.TYPE_ROAD else {}

func _rebuild_road_handles() -> void:
	for c in _road_handles.get_children():
		c.free()
	_road_line.clear_surfaces()
	var e := _selected_road()
	var node: Node3D = builder.node_for(e.get("id", "")) if not e.is_empty() else null
	if node == null:
		return
	var pts: Array = e["road"].get("points", [])
	var mat := ZinoMaterials.unshaded(Color(0.3, 0.8, 1.0), true)
	for i in pts.size():
		var h := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.6
		sm.height = 1.2
		h.mesh = sm
		h.material_override = mat
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var body := StaticBody3D.new()
		body.collision_layer = ZinoTransformGizmo.GIZMO_LAYER
		body.collision_mask = 0
		body.set_meta("road_point", i)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 1.0
		cs.shape = sh
		body.add_child(cs)
		h.add_child(body)
		_road_handles.add_child(h)
		h.global_position = node.global_transform * ZinoFormat.v3(pts[i])
	_draw_road_polyline(node, pts, e["road"].get("closed", false))

func _draw_road_polyline(node: Node3D, pts: Array, closed: bool) -> void:
	_road_line.clear_surfaces()
	if pts.size() < 2:
		return
	_road_line.surface_begin(Mesh.PRIMITIVE_LINES, ZinoMaterials.unshaded(Color(0.3, 0.8, 1.0, 0.8), true))
	var n := pts.size() if closed else pts.size() - 1
	for i in n:
		_road_line.surface_add_vertex(node.global_transform * ZinoFormat.v3(pts[i]) + Vector3.UP * 0.3)
		_road_line.surface_add_vertex(node.global_transform * ZinoFormat.v3(pts[(i + 1) % pts.size()]) + Vector3.UP * 0.3)
	_road_line.surface_end()

func _try_begin_road_drag(pos: Vector2) -> bool:
	if _road_handles.get_child_count() == 0:
		return false
	var hit := _raycast(pos, ZinoTransformGizmo.GIZMO_LAYER)
	if hit.is_empty() or not hit.collider.has_meta("road_point"):
		return false
	var idx: int = hit.collider.get_meta("road_point")
	var handle: Node3D = _road_handles.get_child(idx)
	_drag = {"kind": "road", "index": idx, "plane": Plane(Vector3.UP, handle.global_position), "id": session.selection[0]}
	return true

func _update_road_drag(pos: Vector2) -> void:
	var hit = _plane_hit(_drag.plane, pos)
	if hit == null:
		return
	if snap != Input.is_key_pressed(KEY_CTRL):
		var step := float(session.app.settings.get_value("translateSnap", 0.5))
		hit = Vector3(snappedf(hit.x, step), hit.y, snappedf(hit.z, step))
	var handle: Node3D = _road_handles.get_child(_drag.index)
	handle.global_position = hit
	var node := builder.node_for(_drag.id)
	var pts: Array = []
	for h in _road_handles.get_children():
		pts.append(ZinoFormat.arr3(node.global_transform.affine_inverse() * (h as Node3D).global_position))
	_draw_road_polyline(node, pts, ZinoFormat.find_entity(session.scene(), _drag.id)["road"].get("closed", false))

func _end_road_drag(commit: bool) -> void:
	var d := _drag
	_drag = {}
	var node := builder.node_for(d.id)
	if not commit or node == null:
		_rebuild_road_handles()
		return
	var local := node.global_transform.affine_inverse() * (_road_handles.get_child(d.index) as Node3D).global_position
	var idx: int = d.index
	session.execute(ZinoSceneEdits.modify(session.scene(), [d.id], func(e): e["road"]["points"][idx] = ZinoFormat.arr3(local), "Move Road Point"))

## Moves a road control point to a world position (used by the drag handles and by tests).
func move_road_point(road_id: String, index: int, world_pos: Vector3) -> void:
	var node := builder.node_for(road_id)
	if node == null:
		return
	var local := node.global_transform.affine_inverse() * world_pos
	session.execute(ZinoSceneEdits.modify(session.scene(), [road_id], func(e): e["road"]["points"][index] = ZinoFormat.arr3(local), "Move Road Point"))

# --- Box selection ---------------------------------------------------------------------------

func _box_select(rect: Rect2, additive: bool) -> void:
	var ids := ids_in_screen_rect(rect)
	if additive:
		var merged: Array = session.selection.duplicate()
		for id in ids:
			if not id in merged:
				merged.append(id)
		session.select(merged)
	else:
		session.select(ids)
	ZinoAppLog.info("Viewport", "Box selected %d object(s)" % ids.size())

## Entities whose origin projects inside `rect` (panel coordinates). The ground plane is ignored.
func ids_in_screen_rect(rect: Rect2) -> Array:
	var ids: Array = []
	var scale_to_panel := size / Vector2(viewport.size)
	for id in builder.nodes:
		var n := builder.node_for(id)
		var e := ZinoFormat.find_entity(session.scene(), id)
		if n == null or e.is_empty() or (e.get("type") == ZinoEntities.TYPE_PRIMITIVE and e.get("mesh", {}).get("primitive") == "plane"):
			continue
		if camera.is_position_behind(n.global_position):
			continue
		var p := camera.unproject_position(n.global_position) * scale_to_panel
		if rect.has_point(p):
			ids.append(id)
	return ids


func _refresh_selection_boxes() -> void:
	overlays.draw_selection(_selected_nodes() if session.mode == "edit" else [])

func set_tool(t: String) -> void:
	tool = t
	if t != "select":
		gizmo.set_mode(t)
	tool_changed.emit(t)

func frame_selection() -> void:
	var nodes := _selected_nodes()
	if nodes.is_empty():
		frame_all()
		return
	var box := AABB()
	var first := true
	for n in nodes:
		var b := ZinoViewportOverlays.world_aabb(n)
		if b.size == Vector3.ZERO:
			b = AABB(n.global_position - Vector3.ONE, Vector3.ONE * 2)
		box = b if first else box.merge(b)
		first = false
	camera.frame(box)

func frame_all() -> void:
	var box := AABB()
	var first := true
	for id in builder.nodes:
		var n := builder.node_for(id)
		var e := ZinoFormat.find_entity(session.scene(), id)
		if n == null or e.get("type") == ZinoEntities.TYPE_PRIMITIVE and e.get("mesh", {}).get("primitive") == "plane":
			continue   # ignore the huge ground plane
		var b := ZinoViewportOverlays.world_aabb(n)
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(Vector3(-10, 0, -10), Vector3(20, 5, 20))
	camera.frame(box)
	camera.distance *= 0.8
	camera.zoom(0)

## Where new objects go: the point on the ground the camera looks at.
func _placement_point() -> Vector3:
	var p := camera.pivot
	return Vector3(snappedf(p.x, 0.5), 0.0, snappedf(p.z, 0.5))

# --- Playtest ----------------------------------------------------------------------------------

func start_play() -> bool:
	if session.mode != "edit":
		return false
	_saved_editor_cam = camera.global_transform
	if env_preview:
		env_preview.free()
		env_preview = null
	builder.mode = ZinoSceneBuilder.MODE_PLAY
	builder.build(session.scene().duplicate(true))
	var cam := builder.play_camera()
	if cam == null:
		ZinoAppLog.warn("Play", "No camera in the scene; using the editor camera.")
	else:
		cam.current = true
	var car := builder.player_vehicle()
	if car == null:
		ZinoAppLog.warn("Play", "No player-controlled vehicle in the scene.")
	var progs := ZinoBlockCompiler.load_project_programs(session.project_dir, session.manifest)
	for e in progs.errors:
		ZinoAppLog.error("Blocks", e + " (program skipped)")
	game = ZinoGameContext.new()
	game.name = "Game"
	viewport.add_child(game)
	game.start(builder, session.project_dir, progs.irs, {"save_key": session.project_name() + "_editor"})
	game.blocks.trace_enabled = true
	game.blocks.block_executed.connect(func(node_id): block_traced.emit(node_id))
	game.blocks.log_message.connect(func(level, text): ZinoAppLog.write(level, "Blocks", text))
	game.blocks.runtime_error.connect(func(node_id, msg): block_error.emit(node_id, msg))
	game.quit_requested.connect(func(): stop_requested.emit())
	gizmo.visible = false
	overlays.visible = false
	_road_handles.visible = false
	_road_line.clear_surfaces()
	_mode_badge.visible = true
	_hint.visible = false
	session.set_mode("play")
	apply_quality()
	grab_focus()
	ZinoAppLog.info("Play", "Playtest started (%s physics at %d Hz)" % [ProjectSettings.get_setting("physics/3d/physics_engine"), Engine.physics_ticks_per_second])
	return true

func set_paused(paused: bool) -> void:
	if session.mode == "edit":
		return
	PhysicsServer3D.set_active(not paused)
	world_root.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	session.set_mode("paused" if paused else "play")
	ZinoAppLog.info("Play", "Paused" if paused else "Resumed")

func stop_play() -> void:
	if session.mode == "edit":
		return
	PhysicsServer3D.set_active(true)
	world_root.process_mode = Node.PROCESS_MODE_INHERIT
	if game:
		game.stop()
		game.free()   # free now so nothing in the session touches the scene being rebuilt
		game = null
	builder.mode = ZinoSceneBuilder.MODE_EDIT
	builder.build(session.scene())
	_refresh_env_preview()
	camera.current = true
	overlays.visible = true
	_road_handles.visible = true
	_mode_badge.visible = false
	_hint.visible = true
	session.set_mode("edit")
	apply_quality()
	_refresh_selection()
	ZinoAppLog.info("Play", "Playtest stopped; the scene is unchanged.")
