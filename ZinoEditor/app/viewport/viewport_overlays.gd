class_name ZinoViewportOverlays
extends Node3D
## Editor-only overlays in the 3D world: the ground grid and selection bounding boxes.

var grid: MeshInstance3D
var selection_mesh: MeshInstance3D
var _sel_im := ImmediateMesh.new()
var _sel_mat: StandardMaterial3D

func _ready() -> void:
	grid = MeshInstance3D.new()
	grid.name = "Grid"
	grid.mesh = _build_grid(200, 1.0, 10)
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.position.y = 0.004
	add_child(grid)
	_sel_mat = StandardMaterial3D.new()
	_sel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sel_mat.albedo_color = Color(1.0, 0.62, 0.04)   # systemOrange: readable on any scene
	_sel_mat.no_depth_test = true
	_sel_mat.render_priority = 50
	selection_mesh = MeshInstance3D.new()
	selection_mesh.name = "Selection"
	selection_mesh.mesh = _sel_im
	selection_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(selection_mesh)

func set_grid_visible(v: bool) -> void:
	grid.visible = v

## Orients the grid to the plane of the current orthographic view.
func set_grid_plane(view: String) -> void:
	match view:
		"Front": grid.rotation_degrees = Vector3(90, 0, 0)
		"Side": grid.rotation_degrees = Vector3(0, 0, 90)
		_: grid.rotation_degrees = Vector3.ZERO

func draw_selection(nodes: Array) -> void:
	_sel_im.clear_surfaces()
	var any := false
	for n in nodes:
		if n == null or not is_instance_valid(n):
			continue
		var box := world_aabb(n)
		if box.size == Vector3.ZERO:
			box = AABB(n.global_position - Vector3.ONE * 0.3, Vector3.ONE * 0.6)
		if not any:
			_sel_im.surface_begin(Mesh.PRIMITIVE_LINES, _sel_mat)
			any = true
		_box_lines(box.grow(0.03))
	if any:
		_sel_im.surface_end()

## Union of the world AABBs of every visual under `n`, ignoring editor helper meshes.
static func world_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is VisualInstance3D and not (cur is Light3D) and not str(cur.name).begins_with("Editor"):
			var vi := cur as VisualInstance3D
			var b := vi.global_transform * vi.get_aabb()
			if b.size.length() > 0.0001 and b.size.length() < 100000.0:
				out = b if first else out.merge(b)
				first = false
		for c in cur.get_children():
			if c.has_meta(ZinoSceneBuilder.META_ID) and c != n:
				continue   # child entities have their own boxes
			stack.append(c)
	return out

func _box_lines(b: AABB) -> void:
	var p := b.position
	var s := b.size
	var c := [p, p + Vector3(s.x, 0, 0), p + Vector3(s.x, 0, s.z), p + Vector3(0, 0, s.z),
		p + Vector3(0, s.y, 0), p + Vector3(s.x, s.y, 0), p + s, p + Vector3(0, s.y, s.z)]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	for e in edges:
		_sel_im.surface_add_vertex(c[e[0]])
		_sel_im.surface_add_vertex(c[e[1]])

static func _build_grid(half_extent: int, step: float, major_every: int) -> ImmediateMesh:
	var im := ImmediateMesh.new()
	var minor := StandardMaterial3D.new()
	minor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	minor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	minor.albedo_color = Color(1, 1, 1, 0.07)
	var major := minor.duplicate() as StandardMaterial3D
	major.albedo_color = Color(1, 1, 1, 0.16)
	var axis_x := minor.duplicate() as StandardMaterial3D
	axis_x.albedo_color = Color(0.96, 0.3, 0.33, 0.6)
	var axis_z := minor.duplicate() as StandardMaterial3D
	axis_z.albedo_color = Color(0.32, 0.56, 1.0, 0.6)
	var h := float(half_extent)
	for pass_i in 2:
		im.surface_begin(Mesh.PRIMITIVE_LINES, minor if pass_i == 0 else major)
		for i in range(-half_extent, half_extent + 1):
			if i == 0:
				continue
			var is_major := i % major_every == 0
			if (pass_i == 1) != is_major:
				continue
			# Minor lines only near the centre to keep the grid light.
			if pass_i == 0 and absi(i) > 60:
				continue
			var ext := h if is_major else 60.0
			im.surface_add_vertex(Vector3(i * step, 0, -ext)); im.surface_add_vertex(Vector3(i * step, 0, ext))
			im.surface_add_vertex(Vector3(-ext, 0, i * step)); im.surface_add_vertex(Vector3(ext, 0, i * step))
		im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_LINES, axis_x)
	im.surface_add_vertex(Vector3(-h, 0, 0)); im.surface_add_vertex(Vector3(h, 0, 0))
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_LINES, axis_z)
	im.surface_add_vertex(Vector3(0, 0, -h)); im.surface_add_vertex(Vector3(0, 0, h))
	im.surface_end()
	return im
