@tool
class_name ZinoSceneBuilder
extends RefCounted
## Builds Godot nodes from a Zino scene document and keeps them in sync incrementally.
##
## Modes:
##  - MODE_EDIT:   physics frozen, editor markers visible, pick bodies on PICK_LAYER (Zino Editor viewport)
##  - MODE_PLAY:   full simulation, markers hidden, chase camera active (playtest and exported games)
##  - MODE_AUTHOR: like play but frozen, every node owned by `owner_root` so the Godot editor can save it as .tscn

const MODE_EDIT := 0
const MODE_PLAY := 1
const MODE_AUTHOR := 2

const GAMEPLAY_LAYER := 1
const TRIGGER_LAYER := 1 << 2
const PICK_LAYER := 1 << 19   # layer 20, used only by the Zino Editor for mouse picking

const META_ID := "zino_id"
const ENV_NODE := "ZinoEnvironment"

var root: Node3D
var mode := MODE_EDIT
var graphics_preset := ZinoGraphics.DEFAULT_PRESET
var owner_root: Node = null
var nodes := {}          # entity id -> Node3D
var scene: Dictionary = {}

func _init(target_root: Node3D, build_mode: int = MODE_EDIT, preset: String = ZinoGraphics.DEFAULT_PRESET) -> void:
	root = target_root
	mode = build_mode
	graphics_preset = preset

# --- Whole-scene build -------------------------------------------------------------

func build(scene_doc: Dictionary) -> void:
	clear()
	scene = scene_doc
	_build_environment()
	# Parents before children: iterate until every entity is placed (parents may appear later in the list).
	# Barriers depend on their road, so they are built after everything else.
	var all: Array = scene.get("entities", [])
	var pending: Array = all.filter(func(e): return e.get("type") != ZinoEntities.TYPE_BARRIER)
	pending.append_array(all.filter(func(e): return e.get("type") == ZinoEntities.TYPE_BARRIER))
	# Vegetation is placed on the terrain, so it comes last.
	pending = pending.filter(func(e): return e.get("type") != ZinoEntities.TYPE_VEGETATION)
	pending.append_array(all.filter(func(e): return e.get("type") == ZinoEntities.TYPE_VEGETATION))
	var guard := pending.size() + 1
	while not pending.is_empty() and guard > 0:
		guard -= 1
		var rest: Array = []
		for e in pending:
			var parent = e.get("parentId")
			if parent == null or nodes.has(parent):
				_create(e)
			else:
				rest.append(e)
		if rest.size() == pending.size():
			for e in rest:
				push_warning("Zino: entity '%s' has an unresolved parent; placed at root." % e.get("name"))
				_create(e, true)
			break
		pending = rest
	_link_cameras()

func clear() -> void:
	for id in nodes.keys():
		var n: Node = nodes[id]
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	var env := root.get_node_or_null(ENV_NODE)
	if env:
		env.free()

## Applies an incremental change set: {added: [], removed: [], modified: [], settingsChanged: bool}.
func apply_changes(scene_doc: Dictionary, changes: Dictionary) -> void:
	scene = scene_doc
	if changes.get("reloaded", false):
		build(scene_doc)
		return
	for id in changes.get("removed", []):
		remove_entity(id)
	for id in changes.get("added", []):
		var e := ZinoFormat.find_entity(scene, id)
		if not e.is_empty():
			rebuild_entity(e)
	var modified: Array = changes.get("modified", []).duplicate()
	for id in changes.get("modified", []) + changes.get("added", []) + changes.get("removed", []):
		var t := str(ZinoFormat.find_entity(scene, id).get("type", ""))
		if t in [ZinoEntities.TYPE_TERRAIN, ZinoEntities.TYPE_ROAD, ""]:
			for v in scene.get("entities", []):
				if v.get("type") == ZinoEntities.TYPE_VEGETATION and not v["id"] in modified:
					modified.append(v["id"])
	# A changed or moved road also rebuilds the barriers that follow it.
	for id in changes.get("modified", []) + changes.get("added", []):
		if ZinoFormat.find_entity(scene, id).get("type") == ZinoEntities.TYPE_ROAD:
			for b in scene.get("entities", []):
				if b.get("type") == ZinoEntities.TYPE_BARRIER and b.get("barrier", {}).get("roadId") == id and not b["id"] in modified:
					modified.append(b["id"])
	for id in modified:
		var e := ZinoFormat.find_entity(scene, id)
		if not e.is_empty():
			rebuild_entity(e)
	if changes.get("settingsChanged", false):
		_build_environment()
	_link_cameras()

func remove_entity(id: String) -> void:
	var n: Node = nodes.get(id)
	nodes.erase(id)
	if n and is_instance_valid(n):
		# Keep children alive: they are re-created or removed by their own change entries.
		for child in n.get_children():
			if child.has_meta(META_ID):
				child.reparent(root, true)
		n.free()

## Re-creates one entity node in place (keeping its children entity nodes).
func rebuild_entity(e: Dictionary) -> Node3D:
	var id: String = e["id"]
	var old: Node3D = nodes.get(id)
	var child_entities: Array = []
	var old_index := -1
	if old and is_instance_valid(old):
		old_index = old.get_index()
		for c in old.get_children():
			if c.has_meta(META_ID):
				child_entities.append(c)
		for c in child_entities:
			old.remove_child(c)
		nodes.erase(id)
		old.free()
	var n := _create(e)
	if old_index >= 0 and n.get_parent() == root:
		root.move_child(n, mini(old_index, root.get_child_count() - 1))
	for c in child_entities:
		n.add_child(c)
		_set_owner_recursive(c)
	return n

func node_for(id: String) -> Node3D:
	var n = nodes.get(id)
	return n if n != null and is_instance_valid(n) else null

## Walks up from any node to the entity node that owns it. Returns "" when not part of the scene.
static func entity_id_of(node: Node) -> String:
	var cur := node
	while cur != null:
		if cur.has_meta(META_ID):
			return cur.get_meta(META_ID)
		cur = cur.get_parent()
	return ""

func environment_node() -> WorldEnvironment:
	return root.get_node_or_null(ENV_NODE) as WorldEnvironment

# --- Entity creation ---------------------------------------------------------------

func _create(e: Dictionary, force_root: bool = false) -> Node3D:
	var n: Node3D
	match e.get("type", "empty"):
		ZinoEntities.TYPE_PRIMITIVE: n = _build_primitive(e)
		ZinoEntities.TYPE_LIGHT: n = _build_light(e)
		ZinoEntities.TYPE_CAMERA: n = _build_camera(e)
		ZinoEntities.TYPE_VEHICLE: n = _build_vehicle(e)
		ZinoEntities.TYPE_ROAD: n = _build_road(e)
		ZinoEntities.TYPE_CHECKPOINT, ZinoEntities.TYPE_START_FINISH: n = _build_trigger(e)
		ZinoEntities.TYPE_SPAWN: n = _build_spawn(e)
		ZinoEntities.TYPE_BARRIER: n = _build_barrier(e)
		ZinoEntities.TYPE_TERRAIN: n = _build_terrain(e)
		ZinoEntities.TYPE_MODEL: n = _build_model(e)
		ZinoEntities.TYPE_VEGETATION: n = _build_vegetation(e)
		ZinoEntities.TYPE_WATER: n = _build_simple(e, func(p): ZinoWorld.build_water(p, e.get("water", {})))
		ZinoEntities.TYPE_BUILDING: n = _build_simple(e, func(p): ZinoWorld.build_building(p, e.get("building", {})))
		_: n = _build_empty(e)
	n.name = _node_name(e)
	n.set_meta(META_ID, e["id"])
	n.transform = ZinoFormat.transform_from_entity(e)
	n.visible = e.get("active", true)
	var parent_node: Node = root
	if not force_root and e.get("parentId") != null and nodes.has(e["parentId"]):
		parent_node = nodes[e["parentId"]]
	parent_node.add_child(n)
	if n is ZinoVehicle:
		(n as ZinoVehicle).spawn_transform = n.global_transform
	nodes[e["id"]] = n
	_set_owner_recursive(n)
	return n

func _node_name(e: Dictionary) -> String:
	var s := str(e.get("name", "Entity")).validate_node_name()
	return s if s != "" else "Entity"

func _set_owner_recursive(n: Node) -> void:
	if mode != MODE_AUTHOR or owner_root == null:
		return
	if n != owner_root:
		n.owner = owner_root
	for c in n.get_children():
		_set_owner_recursive(c)

func _editor() -> bool:
	return mode == MODE_EDIT

func _build_empty(e: Dictionary) -> Node3D:
	var n := Node3D.new()
	if _editor():
		n.add_child(_marker_axes(0.6))
		_add_pick(n, SphereShape3D.new(), 0.4)
	return n

func _build_primitive(e: Dictionary) -> Node3D:
	var n := Node3D.new()
	var m: Dictionary = e.get("mesh", {})
	var shape_name: String = m.get("primitive", "cube")
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh: PrimitiveMesh
	var col_shape: Shape3D
	match shape_name:
		"sphere":
			var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0; sm.radial_segments = 48; sm.rings = 24
			mesh = sm
			var ss := SphereShape3D.new(); ss.radius = 0.5
			col_shape = ss
		"cylinder":
			var cm := CylinderMesh.new(); cm.top_radius = 0.5; cm.bottom_radius = 0.5; cm.height = 1.0; cm.radial_segments = 48
			mesh = cm
			var cs := CylinderShape3D.new(); cs.radius = 0.5; cs.height = 1.0
			col_shape = cs
		"capsule":
			var cap := CapsuleMesh.new(); cap.radius = 0.25; cap.height = 1.0
			mesh = cap
			var caps := CapsuleShape3D.new(); caps.radius = 0.25; caps.height = 1.0
			col_shape = caps
		"plane":
			var pm := PlaneMesh.new(); pm.size = Vector2(1, 1)
			pm.subdivide_width = 0; pm.subdivide_depth = 0
			mesh = pm
			var bs := BoxShape3D.new(); bs.size = Vector3(1, 0.02, 1)
			col_shape = bs
		_:
			var bm := BoxMesh.new(); bm.size = Vector3.ONE
			mesh = bm
			var bx := BoxShape3D.new(); bx.size = Vector3.ONE
			col_shape = bx
	mi.mesh = mesh
	mi.material_override = ZinoMaterials.get_material(m.get("material", {}))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if m.get("castShadows", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var scale := ZinoFormat.read_transform(e)["scale"] as Vector3
	if m.get("collider", true):
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = GAMEPLAY_LAYER
		var cs3 := CollisionShape3D.new()
		cs3.shape = _scaled_shape(col_shape, scale)
		body.add_child(cs3)
		# Cancel the entity's scale on the body and bake it into the shape instead,
		# because physics engines do not support non-uniformly scaled bodies.
		body.transform = Transform3D(Basis.from_scale(_safe_inverse(scale)), Vector3.ZERO)
		n.add_child(body)
	if _editor():
		var pick_shape := col_shape.duplicate()
		_add_pick_shape(n, _scaled_shape(pick_shape, scale), scale)
	return n

func _build_light(e: Dictionary) -> Node3D:
	var l: Dictionary = e.get("light", {})
	var light: Light3D
	match l.get("kind", "point"):
		"directional":
			var d := DirectionalLight3D.new()
			ZinoGraphics.apply_sun(d, graphics_preset)
			light = d
		"spot":
			var s := SpotLight3D.new()
			s.spot_range = float(l.get("range", 25.0))
			s.spot_angle = float(l.get("spotAngle", 45.0))
			light = s
		_:
			var o := OmniLight3D.new()
			o.omni_range = float(l.get("range", 15.0))
			light = o
	light.light_color = ZinoFormat.col(l.get("color"), Color.WHITE)
	light.light_energy = float(l.get("intensity", 1.0))
	light.shadow_enabled = l.get("shadows", true)
	light.light_volumetric_fog_energy = 1.0
	if _editor():
		var icon := MeshInstance3D.new()
		icon.name = "EditorIcon"
		var sm := SphereMesh.new(); sm.radius = 0.25; sm.height = 0.5
		icon.mesh = sm
		icon.material_override = ZinoMaterials.unshaded(Color(1.0, 0.86, 0.3))
		icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		light.add_child(icon)
		if l.get("kind") != "point":
			light.add_child(_direction_arrow(Color(1.0, 0.86, 0.3), 2.0))
		_add_pick(light, SphereShape3D.new(), 0.45)
	return light

func _build_camera(e: Dictionary) -> Node3D:
	var c: Dictionary = e.get("camera", {})
	var cam: Camera3D
	if mode != MODE_EDIT and c.get("mode") == "chase":
		cam = ZinoChaseCamera.new()
	else:
		cam = Camera3D.new()
	cam.fov = float(c.get("fov", 65.0))
	cam.near = float(c.get("near", 0.1))
	cam.far = float(c.get("far", 4000.0))
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL if c.get("orthographic", false) else Camera3D.PROJECTION_PERSPECTIVE
	cam.size = float(c.get("orthoSize", 20.0))
	cam.current = false
	if _editor():
		cam.add_child(_camera_gizmo())
		_add_pick(cam, BoxShape3D.new(), 0.7)
	return cam

func _build_vehicle(e: Dictionary) -> Node3D:
	var v := ZinoVehicle.new()
	var vd: Dictionary = e.get("vehicle", {})
	var spec: Dictionary = vd.get("spec", ZinoEntities.default_vehicle_spec())
	v.collision_layer = GAMEPLAY_LAYER
	v.collision_mask = GAMEPLAY_LAYER
	_build_car_body(v, spec)
	v.configure(spec)
	if spec.get("model") is Dictionary and str(spec.model.get("path", "")) != "":
		_attach_model(v, spec)
	# Author mode (Godot editor .tscn) keeps the car live so the saved scene is playable.
	v.input_enabled = mode != MODE_EDIT and vd.get("playerControlled", true)
	v.freeze = mode == MODE_EDIT
	v.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	if _editor():
		var body := ZinoFormat.v3(spec.get("bodySize"), Vector3(1.85, 0.62, 4.3))
		var bs := BoxShape3D.new()
		bs.size = body + Vector3(0, float(spec.get("wheelRadius", 0.34)) * 2.0, 0)
		_add_pick_shape(v, bs, Vector3.ONE, Vector3(0, -float(spec.get("wheelRadius", 0.34)) * 0.5, 0))
	return v

## Procedural car body: chassis, cabin with glass, bumpers and lights. Replaced by imported models in Vehicle Studio (Phase 4).
func _build_car_body(v: ZinoVehicle, spec: Dictionary) -> void:
	var size := ZinoFormat.v3(spec.get("bodySize"), Vector3(1.85, 0.62, 4.3))
	var paint := ZinoMaterials.get_material({"preset": "carPaint", "color": spec.get("bodyColor", [0.72, 0.04, 0.03, 1.0])})
	var glass := ZinoMaterials.get_material({"preset": "glass", "color": [0.3, 0.35, 0.4, 1.0]})
	var trim := ZinoMaterials.get_material({"preset": "rubber"})
	var col := CollisionShape3D.new()
	col.name = "BodyCollision"
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	v.add_child(col)
	var body := Node3D.new()
	body.name = "Body"
	v.add_child(body)
	_box(body, "Chassis", size, Vector3.ZERO, paint)
	var kart := size.z < 2.5
	if not kart:
		var cabin := Vector3(size.x * 0.84, size.y * 0.75, size.z * 0.46)
		_box(body, "Cabin", cabin, Vector3(0, size.y * 0.5 + cabin.y * 0.5, size.z * 0.04), glass)
		_box(body, "Roof", Vector3(cabin.x * 0.98, 0.05, cabin.z * 0.7), Vector3(0, size.y * 0.5 + cabin.y + 0.02, size.z * 0.06), paint)
		_box(body, "FrontBumper", Vector3(size.x * 1.01, size.y * 0.35, 0.18), Vector3(0, -size.y * 0.3, -size.z * 0.5 - 0.05), trim)
		_box(body, "RearBumper", Vector3(size.x * 1.01, size.y * 0.35, 0.18), Vector3(0, -size.y * 0.3, size.z * 0.5 + 0.05), trim)
		var head := StandardMaterial3D.new()
		head.albedo_color = Color(1, 1, 0.95)
		head.emission_enabled = true
		head.emission = Color(1, 0.97, 0.9)
		head.emission_energy_multiplier = 2.0
		var tail := StandardMaterial3D.new()
		tail.albedo_color = Color(0.6, 0.02, 0.02)
		tail.emission_enabled = true
		tail.emission = Color(1, 0.05, 0.03)
		tail.emission_energy_multiplier = 1.2
		for sx in [-1.0, 1.0]:
			_box(body, "HeadLight", Vector3(0.38, 0.12, 0.05), Vector3(sx * size.x * 0.33, size.y * 0.15, -size.z * 0.5 - 0.01), head)
			# Real headlights; ZinoEnvironment switches them on at night and in bad weather.
			var beam := SpotLight3D.new()
			beam.name = "HeadlightBeam"
			beam.position = Vector3(sx * size.x * 0.33, size.y * 0.15, -size.z * 0.5 - 0.05)
			beam.light_color = Color(1.0, 0.95, 0.85)
			beam.light_energy = 6.0
			beam.spot_range = 45.0
			beam.spot_angle = 28.0
			beam.shadow_enabled = graphics_preset in ["ultraMax", "ultra"]
			beam.visible = false
			beam.add_to_group("zino_headlights")
			body.add_child(beam)
			_box(body, "TailLight", Vector3(0.4, 0.1, 0.05), Vector3(sx * size.x * 0.33, size.y * 0.15, size.z * 0.5 + 0.01), tail)
	else:
		_box(body, "Seat", Vector3(0.5, 0.45, 0.5), Vector3(0, size.y * 0.5 + 0.22, size.z * 0.12), trim)

## Replaces the procedural body with an imported model. Wheel meshes named in model.wheelNodes are
## hidden in the body and re-created on the physics wheels so they spin and steer.
func _attach_model(v: ZinoVehicle, spec: Dictionary) -> void:
	var m: Dictionary = spec.model
	var r := ZinoModelLoader.instantiate(str(m.path))
	if r.has("error"):
		push_warning("Zino: %s — using the procedural body" % r.error)
		v.set_meta("model_error", r.error)
		return
	var model: Node3D = r.node
	model.name = "Model"
	model.position = ZinoFormat.v3(m.get("offset"), Vector3.ZERO)
	model.rotation_degrees = ZinoFormat.v3(m.get("rotation"), Vector3.ZERO)
	model.scale = Vector3.ONE * float(m.get("scale", 1.0))
	v.add_child(model)
	var body := v.get_node_or_null("Body")
	if body and m.get("hideProceduralBody", true):
		body.visible = false
	var wheel_nodes: Dictionary = m.get("wheelNodes", {})
	var meshes := ZinoModelLoader.mesh_nodes(model)
	for w in v.wheels():
		var key := str(w.name).trim_prefix("Wheel_")
		var path := str(wheel_nodes.get(key, ""))
		if path == "" or not meshes.has(path):
			continue
		var src: MeshInstance3D = meshes[path]
		# Works before the vehicle is in the scene tree: chain local transforms up to the vehicle.
		var rel := Transform3D.IDENTITY
		var cur: Node = src
		while cur != null and cur != v:
			if cur is Node3D:
				rel = (cur as Node3D).transform * rel
			cur = cur.get_parent()
		var local_box := rel * src.get_aabb()
		var copy := MeshInstance3D.new()
		copy.name = "ModelWheel"
		copy.mesh = src.mesh
		copy.material_override = src.material_override
		for i in src.get_surface_override_material_count():
			copy.set_surface_override_material(i, src.get_surface_override_material(i))
		# Keep the mesh's orientation and scale relative to the car, centred on the physics wheel.
		copy.transform = Transform3D(rel.basis, rel.origin - local_box.get_center())
		src.visible = false
		var vis := w.get_node_or_null("Visual")
		if vis:
			vis.visible = false
		w.add_child(copy)

func _box(parent: Node3D, box_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _build_road(e: Dictionary) -> Node3D:
	var n := Node3D.new()
	var road: Dictionary = e.get("road", {})
	var body := ZinoRoadBuilder.build(n, road, true)
	body.collision_layer = GAMEPLAY_LAYER
	if _editor():
		var pick := StaticBody3D.new()
		pick.name = "EditorPick"
		pick.collision_layer = PICK_LAYER
		pick.collision_mask = 0
		for c in body.get_children():
			if c is CollisionShape3D:
				var cs := CollisionShape3D.new()
				cs.shape = c.shape
				pick.add_child(cs)
		n.add_child(pick)
		# Control-point markers.
		for p in road.get("points", []):
			var m := MeshInstance3D.new()
			m.name = "ControlPoint"
			var sm := SphereMesh.new(); sm.radius = 0.35; sm.height = 0.7
			m.mesh = sm
			m.position = ZinoFormat.v3(p) + Vector3(0, 0.5, 0)
			m.material_override = ZinoMaterials.unshaded(Color(0.3, 0.75, 1.0))
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(m)
	return n

func _build_barrier(e: Dictionary) -> Node3D:
	var n := Node3D.new()
	var b: Dictionary = e.get("barrier", {})
	var road_e := ZinoFormat.find_entity(scene, str(b.get("roadId", "")))
	var road_node := node_for(str(b.get("roadId", "")))
	if road_e.is_empty() or road_node == null:
		return n
	n.transform = ZinoFormat.transform_from_entity(e)
	ZinoTrackTools.build_barrier(n, b, road_e.get("road", {}), road_node.global_transform if road_node.is_inside_tree() else road_node.transform)
	if _editor():
		var pick := StaticBody3D.new()
		pick.name = "EditorPick"
		pick.collision_layer = PICK_LAYER
		pick.collision_mask = 0
		for c in n.get_children():
			if c is StaticBody3D:
				for s in c.get_children():
					if s is CollisionShape3D:
						var cs := CollisionShape3D.new()
						cs.shape = s.shape
						pick.add_child(cs)
		n.add_child(pick)
	return n

var terrain_heights := {}             # terrain id -> PackedFloat32Array (used by vegetation and sculpting)

func _build_terrain(e: Dictionary) -> Node3D:
	var n := Node3D.new()
	var t: Dictionary = e.get("terrain", {})
	var h := ZinoWorld.terrain_heights(t, scene, ZinoFormat.transform_from_entity(e))
	terrain_heights[e.id] = h
	ZinoWorld.build_terrain(n, t, h)
	if _editor():
		n.get_node("TerrainCollision").collision_layer = GAMEPLAY_LAYER | PICK_LAYER
	return n

## Terrain height at a world x/z (0 when there is no terrain).
func terrain_height(x: float, z: float) -> float:
	for e in scene.get("entities", []):
		if e.get("type") == ZinoEntities.TYPE_TERRAIN and terrain_heights.has(e.id):
			var t: Dictionary = e.terrain
			var xf := ZinoFormat.transform_from_entity(e)
			var local := xf.affine_inverse() * Vector3(x, 0, z)
			var size := float(t.get("size", 1200.0))
			if absf(local.x) <= size * 0.5 and absf(local.z) <= size * 0.5:
				return (xf * Vector3(local.x, ZinoWorld.sample(terrain_heights[e.id], int(t.get("resolution", 129)), size, local.x, local.z), local.z)).y
	return 0.0

func _build_vegetation(e: Dictionary) -> Node3D:
	var n := Node3D.new()
	var counts := ZinoWorld.build_vegetation(n, e.get("vegetation", {}), scene, terrain_height, ZinoFormat.transform_from_entity(e))
	n.set_meta("counts", counts)
	if _editor():
		_add_pick(n, BoxShape3D.new(), 3.0)
	return n

func _build_model(e: Dictionary) -> Node3D:
	var n := Node3D.new()
	var m: Dictionary = e.get("model", {})
	var r := ZinoModelLoader.instantiate(str(m.get("path", "")))
	if r.has("error"):
		push_warning("Zino: " + str(r.error))
		n.add_child(_marker_axes(1.0))
		_add_pick(n, BoxShape3D.new(), 1.0)
		return n
	var model: Node3D = r.node
	n.add_child(model)
	var box := _local_aabb(model)
	var col := str(m.get("collision", "box"))
	if col != "none":
		var body := StaticBody3D.new()
		body.name = "ModelCollision"
		body.collision_layer = GAMEPLAY_LAYER
		if col == "mesh":
			for mi in ZinoModelLoader.mesh_nodes(model).values():
				var cs := CollisionShape3D.new()
				cs.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
				cs.transform = _chain_xform(mi, n)
				body.add_child(cs)
		else:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = box.size
			cs.shape = bs
			cs.position = box.get_center()
			body.add_child(cs)
		n.add_child(body)
	if _editor():
		var bs2 := BoxShape3D.new()
		bs2.size = box.size
		_add_pick_shape(n, bs2, ZinoFormat.read_transform(e).scale, box.get_center())
	return n

static func _chain_xform(node: Node, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

static func _local_aabb(model: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in ZinoModelLoader.mesh_nodes(model).values():
		var b := _chain_xform(mi, model.get_parent()) * (mi as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)

func _build_simple(e: Dictionary, fill: Callable) -> Node3D:
	var n := Node3D.new()
	fill.call(n)
	if _editor():
		var pick := StaticBody3D.new()
		pick.name = "EditorPick"
		pick.collision_layer = PICK_LAYER
		pick.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		if e.type == ZinoEntities.TYPE_WATER:
			var sz := ZinoFormat.v3(e.water.get("size"), Vector3(300, 0, 300))
			bs.size = Vector3(sz.x, 0.5, sz.z)
		else:
			bs.size = Vector3(float(e.building.get("width", 18)), int(e.building.get("floors", 6)) * 3.2, float(e.building.get("depth", 14)))
			cs.position.y = bs.size.y * 0.5
		cs.shape = bs
		pick.add_child(cs)
		n.add_child(pick)
	return n

func _build_trigger(e: Dictionary) -> Node3D:
	var t: Dictionary = e.get("trigger", {})
	var size := ZinoFormat.v3(t.get("size"), Vector3(14, 4, 1))
	var area := Area3D.new()
	area.collision_layer = TRIGGER_LAYER
	area.collision_mask = GAMEPLAY_LAYER
	area.monitoring = mode == MODE_PLAY
	area.set_meta("zino_checkpoint_index", int(t.get("index", 0)))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	area.add_child(cs)
	var is_start: bool = e.get("type") == ZinoEntities.TYPE_START_FINISH
	if is_start:
		area.add_child(_start_gantry(size))
	if _editor():
		var vis := MeshInstance3D.new()
		vis.name = "EditorVolume"
		var bm := BoxMesh.new()
		bm.size = size
		vis.mesh = bm
		vis.material_override = ZinoMaterials.unshaded(Color(1.0, 0.35, 0.2, 0.25) if is_start else Color(0.2, 0.9, 0.5, 0.22), false, true)
		vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		area.add_child(vis)
		_add_pick_shape(area, bs, Vector3.ONE)
	return area

func _start_gantry(size: Vector3) -> Node3D:
	var g := Node3D.new()
	g.name = "Gantry"
	var metal := ZinoMaterials.get_material({"preset": "metal", "color": [0.85, 0.86, 0.88, 1.0], "metallic": 1.0, "roughness": 0.3})
	var half := size.x * 0.5 + 0.4
	var h := 6.0
	for sx in [-1.0, 1.0]:
		_box(g, "Pole", Vector3(0.35, h, 0.35), Vector3(sx * half, h * 0.5 - 2.0, 0), metal)
	var banner_mat := StandardMaterial3D.new()
	banner_mat.albedo_texture = _checker_texture()
	banner_mat.roughness = 0.6
	banner_mat.uv1_scale = Vector3(size.x / 1.2, 1, 1)
	_box(g, "Banner", Vector3(half * 2.0, 1.2, 0.12), Vector3(0, h - 2.6, 0), banner_mat)
	# Painted chequered line on the road surface.
	var line := MeshInstance3D.new()
	line.name = "Line"
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x, 1.2)
	line.mesh = pm
	line.position = Vector3(0, -2.0 + ZinoRoadBuilder.SURFACE_LIFT + 0.012, 0)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_texture = _checker_texture()
	line_mat.uv1_scale = Vector3(size.x / 1.2, 1, 1)
	line_mat.roughness = 0.7
	line.material_override = line_mat
	g.add_child(line)
	return g

static var _checker: ImageTexture
static func _checker_texture() -> ImageTexture:
	if _checker:
		return _checker
	var img := Image.create(64, 64, true, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var white := ((x / 32) + (y / 32)) % 2 == 0
			img.set_pixel(x, y, Color(0.95, 0.95, 0.95) if white else Color(0.05, 0.05, 0.05))
	img.generate_mipmaps()
	_checker = ImageTexture.create_from_image(img)
	return _checker

func _build_spawn(e: Dictionary) -> Node3D:
	var n := Marker3D.new()
	if _editor():
		n.add_child(_direction_arrow(Color(0.35, 0.8, 1.0), 2.5))
		_add_pick(n, SphereShape3D.new(), 0.8)
	return n

# --- Environment --------------------------------------------------------------------

func _build_environment() -> void:
	var old := root.get_node_or_null(ENV_NODE)
	if old:
		old.free()
	var we := WorldEnvironment.new()
	we.name = ENV_NODE
	we.environment = ZinoGraphics.build_environment(scene.get("settings", {}), graphics_preset)
	var attrs := CameraAttributesPractical.new()
	# Fixed exposure: predictable look in the editor and in the game; tune with the scene's Exposure setting.
	attrs.auto_exposure_enabled = false
	var fx: Dictionary = scene.get("settings", {}).get("postFx", {})
	attrs.dof_blur_far_enabled = fx.get("dofEnabled", false) and graphics_preset in ["ultraMax", "ultra", "high"]
	attrs.dof_blur_far_distance = float(fx.get("dofDistance", 120.0))
	attrs.dof_blur_far_transition = float(fx.get("dofDistance", 120.0)) * 0.5
	attrs.dof_blur_amount = float(fx.get("dofAmount", 0.08))
	we.camera_attributes = attrs
	root.add_child(we)
	root.move_child(we, 0)
	_set_owner_recursive(we)

# --- Play-mode wiring ----------------------------------------------------------------

func _link_cameras() -> void:
	if mode == MODE_EDIT:
		return
	for e in scene.get("entities", []):
		if e.get("type") != ZinoEntities.TYPE_CAMERA:
			continue
		var cam := node_for(e["id"])
		var c: Dictionary = e.get("camera", {})
		if cam is ZinoChaseCamera and c.get("targetId") != null:
			var target := node_for(c["targetId"])
			if target:
				(cam as ZinoChaseCamera).setup(target, c)
	if mode == MODE_AUTHOR:
		var pc := play_camera()
		if pc:
			pc.current = true

## The camera a play session should look through: first chase camera, else first camera.
func play_camera() -> Camera3D:
	var fallback: Camera3D = null
	for e in scene.get("entities", []):
		if e.get("type") != ZinoEntities.TYPE_CAMERA or not e.get("active", true):
			continue
		var cam := node_for(e["id"]) as Camera3D
		if cam is ZinoChaseCamera:
			return cam
		if fallback == null:
			fallback = cam
	return fallback

func player_vehicle() -> ZinoVehicle:
	for e in scene.get("entities", []):
		if e.get("type") == ZinoEntities.TYPE_VEHICLE and e.get("vehicle", {}).get("playerControlled", true):
			var v := node_for(e["id"])
			if v is ZinoVehicle:
				return v
	return null

# --- Editor helpers ------------------------------------------------------------------

func _add_pick(parent: Node3D, shape: Shape3D, radius_or_size: float) -> void:
	if shape is SphereShape3D:
		(shape as SphereShape3D).radius = radius_or_size
	elif shape is BoxShape3D:
		(shape as BoxShape3D).size = Vector3.ONE * radius_or_size
	_add_pick_shape(parent, shape, Vector3.ONE)

func _add_pick_shape(parent: Node3D, shape: Shape3D, parent_scale: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.name = "EditorPick"
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	body.transform = Transform3D(Basis.from_scale(_safe_inverse(parent_scale)), offset)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)

static func _scaled_shape(shape: Shape3D, s: Vector3) -> Shape3D:
	var a := Vector3(absf(s.x), absf(s.y), absf(s.z))
	if shape is BoxShape3D:
		var b := BoxShape3D.new(); b.size = (shape as BoxShape3D).size * a
		return b
	if shape is SphereShape3D:
		var sp := SphereShape3D.new(); sp.radius = (shape as SphereShape3D).radius * maxf(a.x, maxf(a.y, a.z))
		return sp
	if shape is CylinderShape3D:
		var c := CylinderShape3D.new(); c.radius = (shape as CylinderShape3D).radius * maxf(a.x, a.z); c.height = (shape as CylinderShape3D).height * a.y
		return c
	if shape is CapsuleShape3D:
		var cp := CapsuleShape3D.new(); cp.radius = (shape as CapsuleShape3D).radius * maxf(a.x, a.z); cp.height = (shape as CapsuleShape3D).height * a.y
		return cp
	return shape

static func _safe_inverse(s: Vector3) -> Vector3:
	return Vector3(1.0 / s.x if absf(s.x) > 0.0001 else 1.0, 1.0 / s.y if absf(s.y) > 0.0001 else 1.0, 1.0 / s.z if absf(s.z) > 0.0001 else 1.0)

func _marker_axes(length: float) -> Node3D:
	var n := Node3D.new()
	n.name = "EditorAxes"
	var dirs := [[Vector3.RIGHT, Color(0.95, 0.3, 0.3)], [Vector3.UP, Color(0.4, 0.9, 0.3)], [Vector3.BACK, Color(0.3, 0.55, 1.0)]]
	for d in dirs:
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES, ZinoMaterials.unshaded(d[1]))
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_add_vertex(d[0] * length)
		im.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
	return n

func _direction_arrow(color: Color, length: float) -> Node3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, ZinoMaterials.unshaded(color))
	var tip := Vector3(0, 0, -length)
	im.surface_add_vertex(Vector3.ZERO); im.surface_add_vertex(tip)
	for side in [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), Vector3(0, 0.3, 0), Vector3(0, -0.3, 0)]:
		im.surface_add_vertex(tip); im.surface_add_vertex(tip + Vector3(0, 0, 0.5) + side)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.name = "EditorArrow"
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _camera_gizmo() -> Node3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, ZinoMaterials.unshaded(Color(0.85, 0.85, 0.95)))
	var d := 1.2
	var w := 0.7
	var h := 0.45
	var corners := [Vector3(-w, -h, -d), Vector3(w, -h, -d), Vector3(w, h, -d), Vector3(-w, h, -d)]
	for i in 4:
		im.surface_add_vertex(Vector3.ZERO); im.surface_add_vertex(corners[i])
		im.surface_add_vertex(corners[i]); im.surface_add_vertex(corners[(i + 1) % 4])
	im.surface_add_vertex(Vector3(-0.25, h + 0.05, -d)); im.surface_add_vertex(Vector3(0, h + 0.3, -d))
	im.surface_add_vertex(Vector3(0, h + 0.3, -d)); im.surface_add_vertex(Vector3(0.25, h + 0.05, -d))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.name = "EditorFrustum"
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
