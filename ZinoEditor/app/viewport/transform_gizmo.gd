class_name ZinoTransformGizmo
extends Node3D
## Move / rotate / scale gizmo. Handles are meshes drawn on top of the scene with matching pick
## bodies on GIZMO_LAYER, so the viewport can ray-pick them independently from scene objects.

const GIZMO_LAYER := 1 << 20      # layer 21
const AXES := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}
const COLORS := {"x": Color(0.96, 0.3, 0.33), "y": Color(0.45, 0.88, 0.32), "z": Color(0.32, 0.56, 1.0), "xyz": Color(0.95, 0.95, 0.95)}
const HIGHLIGHT := Color(1.0, 0.85, 0.2)

var mode := "translate"   # translate, rotate, scale
var local_space := false
var _handles := {}        # axis -> {mesh: MeshInstance3D, mat: StandardMaterial3D}
var _hover := ""

func _ready() -> void:
	rebuild()

func set_mode(m: String) -> void:
	if m != mode:
		mode = m
		rebuild()

func rebuild() -> void:
	for c in get_children():
		c.free()
	_handles.clear()
	match mode:
		"rotate":
			for a in AXES:
				_ring(a)
		"scale":
			for a in AXES:
				_axis(a, true)
			_center_handle(true)
		_:
			for a in AXES:
				_axis(a, false)
			_center_handle(false)

func set_hover(axis: String) -> void:
	if axis == _hover:
		return
	if _handles.has(_hover):
		_handles[_hover].mat.albedo_color = COLORS[_hover]
	_hover = axis
	if _handles.has(axis):
		_handles[axis].mat.albedo_color = HIGHLIGHT

## World-space direction of an axis handle.
func axis_vector(axis: String) -> Vector3:
	if not AXES.has(axis):
		return Vector3.ZERO
	var v: Vector3 = AXES[axis]
	return (global_transform.basis.orthonormalized() * v).normalized() if local_space else v

## Keeps the gizmo a constant size on screen.
func update_screen_size(cam: Camera3D) -> void:
	var s: float
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		s = cam.size * 0.12
	else:
		s = maxf(0.01, cam.global_position.distance_to(global_position)) * 0.13
	var b := global_transform.basis.orthonormalized() if local_space else Basis()
	global_transform = Transform3D(b.scaled(Vector3.ONE * s), global_position)

func world_size() -> float:
	return global_transform.basis.get_scale().x

# --- Construction ------------------------------------------------------------------------

func _material(axis: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = COLORS[axis]
	m.no_depth_test = true
	m.render_priority = 100
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _add(axis: String, mesh: Mesh, xform: Transform3D, shape: Shape3D, shape_xform: Transform3D) -> void:
	var mat: StandardMaterial3D = _handles[axis].mat if _handles.has(axis) else _material(axis)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xform
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = GIZMO_LAYER
	body.collision_mask = 0
	body.set_meta("gizmo_axis", axis)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = shape_xform
	body.add_child(cs)
	add_child(body)
	_handles[axis] = {"mesh": mi, "mat": mat}

static func _align_y_to(dir: Vector3) -> Basis:
	if dir.is_equal_approx(Vector3.UP):
		return Basis()
	if dir.is_equal_approx(Vector3.RIGHT):
		return Basis(Vector3.BACK, -PI / 2)
	return Basis(Vector3.RIGHT, PI / 2)   # +Z

func _axis(axis: String, cube_tip: bool) -> void:
	var dir: Vector3 = AXES[axis]
	var b := _align_y_to(dir)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.025
	shaft.bottom_radius = 0.025
	shaft.height = 0.85
	shaft.radial_segments = 8
	var pick := CylinderShape3D.new()
	pick.radius = 0.09
	pick.height = 1.1
	_add(axis, shaft, Transform3D(b, dir * 0.45), pick, Transform3D(b, dir * 0.55))
	var tip: Mesh
	if cube_tip:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.13
		tip = bm
	else:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.075
		cone.height = 0.22
		cone.radial_segments = 16
		tip = cone
	var mi := MeshInstance3D.new()
	mi.mesh = tip
	mi.transform = Transform3D(b, dir * 0.95)
	mi.material_override = _handles[axis].mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _center_handle(for_scale: bool) -> void:
	var bm: PrimitiveMesh = BoxMesh.new() if for_scale else SphereMesh.new()
	if bm is BoxMesh:
		(bm as BoxMesh).size = Vector3.ONE * 0.16
	else:
		(bm as SphereMesh).radius = 0.08
		(bm as SphereMesh).height = 0.16
	var shape := SphereShape3D.new()
	shape.radius = 0.13
	_add("xyz", bm, Transform3D(), shape, Transform3D())

func _ring(axis: String) -> void:
	var dir: Vector3 = AXES[axis]
	var b := _align_y_to(dir)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 0.9
	torus.rings = 48
	torus.ring_segments = 6
	var mi_shape := ConcavePolygonShape3D.new()
	# Pick ring: a band of quads around the torus so thin rings are still easy to grab.
	var faces := PackedVector3Array()
	var seg := 48
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		var i0 := p0 * 0.78
		var o0 := p0 * 0.98
		var i1 := p1 * 0.78
		var o1 := p1 * 0.98
		faces.append_array([i0, o0, o1, i0, o1, i1])
	mi_shape.set_faces(faces)
	mi_shape.backface_collision = true
	_add(axis, torus, Transform3D(b, Vector3.ZERO), mi_shape, Transform3D(b, Vector3.ZERO))
