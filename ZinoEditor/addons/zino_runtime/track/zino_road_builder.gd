@tool
class_name ZinoRoadBuilder
extends RefCounted
## Generates road geometry from a road component: a Catmull-Rom centreline through the control
## points, a solid road slab with UVs/normals/tangents, optional banking, painted edge lines,
## grass-verge shoulders and a matching trimesh collision shape.

const SURFACE_LIFT := 0.05   # top surface sits this far above the entity origin (avoids z-fighting with ground)
const LINE_WIDTH := 0.22
const LINE_INSET := 0.45

## Samples the centreline. Returns {points: PackedVector3Array, tangents: PackedVector3Array}.
static func sample_centerline(road: Dictionary) -> Dictionary:
	var ctrl: Array = []
	for p in road.get("points", []):
		ctrl.append(ZinoFormat.v3(p))
	var closed: bool = road.get("closed", false)
	var samples := maxi(2, int(road.get("samplesPerSegment", 14)))
	var pts := PackedVector3Array()
	var n := ctrl.size()
	if n < 2:
		return {"points": pts, "tangents": PackedVector3Array()}
	var seg_count := n if closed else n - 1
	for s in seg_count:
		var p0: Vector3 = ctrl[(s - 1 + n) % n] if (closed or s > 0) else ctrl[0] * 2.0 - ctrl[1]
		var p1: Vector3 = ctrl[s]
		var p2: Vector3 = ctrl[(s + 1) % n]
		var p3: Vector3
		if closed or s + 2 < n:
			p3 = ctrl[(s + 2) % n]
		else:
			p3 = p2 * 2.0 - p1
		for i in samples:
			pts.append(catmull_rom(p0, p1, p2, p3, float(i) / samples))
	if not closed:
		pts.append(ctrl[n - 1])
	var tangents := PackedVector3Array()
	var m := pts.size()
	for i in m:
		var a: Vector3
		var b: Vector3
		if closed:
			a = pts[(i - 1 + m) % m]
			b = pts[(i + 1) % m]
		else:
			a = pts[maxi(i - 1, 0)]
			b = pts[mini(i + 1, m - 1)]
		var t := b - a
		tangents.append(t.normalized() if t.length() > 0.0001 else Vector3.FORWARD)
	return {"points": pts, "tangents": tangents}

## Centripetal-free uniform Catmull-Rom (passes through p1 at t=0 and p2 at t=1).
static func catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

static func centerline_length(road: Dictionary) -> float:
	var c := sample_centerline(road)
	var pts: PackedVector3Array = c.points
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	if road.get("closed", false) and pts.size() > 2:
		total += pts[pts.size() - 1].distance_to(pts[0])
	return total

## Builds the road visuals and collision under `parent`. Returns the StaticBody3D created.
static func build(parent: Node3D, road: Dictionary, with_collision: bool = true) -> StaticBody3D:
	var line := sample_centerline(road)
	var pts: PackedVector3Array = line.points
	var tans: PackedVector3Array = line.tangents
	var closed: bool = road.get("closed", false)
	var width := maxf(1.0, float(road.get("width", 12.0)))
	var thickness := maxf(0.05, float(road.get("thickness", 0.3)))
	var bank := deg_to_rad(float(road.get("banking", 0.0)))
	var shoulder := maxf(0.0, float(road.get("shoulderWidth", 1.2)))

	var lefts := PackedVector3Array()
	var ups := PackedVector3Array()
	for i in pts.size():
		var fwd := tans[i]
		var left := Vector3.UP.cross(fwd).normalized()
		if left.length() < 0.5:
			left = Vector3.LEFT
		var up := fwd.cross(left).normalized() * -1.0
		if up.y < 0:
			up = -up
		if bank != 0.0:
			# Bank into the turn, proportional to local curvature (sign of turn direction).
			var prev := tans[(i - 1 + tans.size()) % tans.size()] if closed or i > 0 else tans[i]
			var turn := prev.cross(fwd).y
			var angle := clampf(turn * 25.0, -1.0, 1.0) * bank
			left = left.rotated(fwd, angle)
			up = up.rotated(fwd, angle)
		lefts.append(left)
		ups.append(up)

	var mesh := ArrayMesh.new()
	var road_mat := ZinoMaterials.get_material({"preset": road.get("surface", "asphalt")})
	_add_strip(mesh, pts, lefts, ups, closed, -width * 0.5, width * 0.5, SURFACE_LIFT, true, road_mat, thickness)
	if shoulder > 0.0:
		var verge := ZinoMaterials.get_material({"preset": "concrete"})
		_add_strip(mesh, pts, lefts, ups, closed, width * 0.5, width * 0.5 + shoulder, SURFACE_LIFT * 0.6, false, verge, 0.0)
		_add_strip(mesh, pts, lefts, ups, closed, -width * 0.5 - shoulder, -width * 0.5, SURFACE_LIFT * 0.6, false, verge, 0.0)
	if road.get("centerLine", false):
		_add_dashes(mesh, pts, lefts, ups, SURFACE_LIFT + 0.006, ZinoMaterials.lane_marking())
	if road.get("edgeLines", true):
		var paint := ZinoMaterials.lane_marking()
		var o := width * 0.5 - LINE_INSET
		_add_strip(mesh, pts, lefts, ups, closed, o - LINE_WIDTH, o, SURFACE_LIFT + 0.005, false, paint, 0.0)
		_add_strip(mesh, pts, lefts, ups, closed, -o, -o + LINE_WIDTH, SURFACE_LIFT + 0.005, false, paint, 0.0)

	var mi := MeshInstance3D.new()
	mi.name = "RoadMesh"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "RoadCollision"
	parent.add_child(body)
	if with_collision and mesh.get_surface_count() > 0:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		# Collide with the drivable slab only (surface 0).
		var slab := ArrayMesh.new()
		slab.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
		shape.shape = slab.create_trimesh_shape()
		body.add_child(shape)
	return body

## Dashed centre line: 3 m dashes with 6 m gaps.
static func _add_dashes(mesh: ArrayMesh, pts: PackedVector3Array, lefts: PackedVector3Array, ups: PackedVector3Array, lift: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist := 0.0
	var w := LINE_WIDTH * 0.5
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		var mid := dist + seg * 0.5
		dist += seg
		if fmod(mid, 9.0) > 3.0:
			continue
		var a := pts[i] + ups[i] * lift
		var b := pts[i + 1] + ups[i + 1] * lift
		_quad(st, a + lefts[i] * w, a - lefts[i] * w, b - lefts[i + 1] * w, b + lefts[i + 1] * w, ups[i], ups[i + 1],
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	st.generate_tangents()
	st.set_material(mat)
	st.commit(mesh)

## Adds one surface: a ribbon between lateral offsets [a, b] (b > a, positive = left side),
## lifted `lift` above the centreline. If `solid`, side walls and an underside of depth `depth` are added.
static func _add_strip(mesh: ArrayMesh, pts: PackedVector3Array, lefts: PackedVector3Array, ups: PackedVector3Array,
		closed: bool, a: float, b: float, lift: float, solid: bool, mat: Material, depth: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var rows := n + 1 if closed else n
	var dist := 0.0
	var u_scale := 1.0 / 6.0   # texture repeats every 6 m along the road
	var v_span := absf(b - a) / 6.0
	var top_l := PackedVector3Array()
	var top_r := PackedVector3Array()
	var vs := PackedFloat32Array()
	for r in rows:
		var i: int = r % n
		if r > 0:
			dist += pts[i].distance_to(pts[(r - 1) % n])
		top_l.append(pts[i] + lefts[i] * b + ups[i] * lift)
		top_r.append(pts[i] + lefts[i] * a + ups[i] * lift)
		vs.append(dist * u_scale)
	for r in range(rows - 1):
		var i0: int = r % n
		var i1: int = (r + 1) % n
		_quad(st, top_l[r], top_r[r], top_r[r + 1], top_l[r + 1], ups[i0], ups[i1],
			Vector2(0, vs[r]), Vector2(v_span, vs[r]), Vector2(v_span, vs[r + 1]), Vector2(0, vs[r + 1]))
	if solid and depth > 0.0:
		for r in range(rows - 1):
			var i0: int = r % n
			var i1: int = (r + 1) % n
			var dl0 := top_l[r] - ups[i0] * depth
			var dl1 := top_l[r + 1] - ups[i1] * depth
			var dr0 := top_r[r] - ups[i0] * depth
			var dr1 := top_r[r + 1] - ups[i1] * depth
			# Left wall, right wall, underside.
			_quad(st, dl0, top_l[r], top_l[r + 1], dl1, lefts[i0], lefts[i1], Vector2(0, vs[r]), Vector2(0.05, vs[r]), Vector2(0.05, vs[r + 1]), Vector2(0, vs[r + 1]))
			_quad(st, top_r[r], dr0, dr1, top_r[r + 1], -lefts[i0], -lefts[i1], Vector2(0, vs[r]), Vector2(0.05, vs[r]), Vector2(0.05, vs[r + 1]), Vector2(0, vs[r + 1]))
			_quad(st, dr0, dl0, dl1, dr1, -ups[i0], -ups[i1], Vector2(0, vs[r]), Vector2(v_span, vs[r]), Vector2(v_span, vs[r + 1]), Vector2(0, vs[r + 1]))
		if not closed:
			for r in [0, rows - 1]:
				var i: int = r % n
				var cap_n := -(pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized() if r == 0 else (pts[i] - pts[maxi(i - 1, 0)]).normalized()
				var dl := top_l[r] - ups[i] * depth
				var dr := top_r[r] - ups[i] * depth
				if r == 0:
					_quad(st, top_r[r], top_l[r], dl, dr, cap_n, cap_n, Vector2.ZERO, Vector2(1, 0), Vector2(1, 0.05), Vector2(0, 0.05))
				else:
					_quad(st, top_l[r], top_r[r], dr, dl, cap_n, cap_n, Vector2.ZERO, Vector2(1, 0), Vector2(1, 0.05), Vector2(0, 0.05))
	st.generate_tangents()
	st.set_material(mat)
	st.commit(mesh)

## Quad p0-p1-p2-p3 with p0/p1 on row A (normal na) and p2/p3 on row B (normal nb).
## Wound clockwise when seen from the side the normals face (Godot's front-face winding), whatever order the corners arrive in.
static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, na: Vector3, nb: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2) -> void:
	var face_n := (p1 - p0).cross(p3 - p0)
	var flip := face_n.dot(na + nb) > 0.0
	var tri := [[p0, na, uv0], [p1, na, uv1], [p2, nb, uv2], [p0, na, uv0], [p2, nb, uv2], [p3, nb, uv3]]
	if flip:
		tri = [[p0, na, uv0], [p2, nb, uv2], [p1, na, uv1], [p0, na, uv0], [p3, nb, uv3], [p2, nb, uv2]]
	for v in tri:
		st.set_normal(v[1])
		st.set_uv(v[2])
		st.add_vertex(v[0])
