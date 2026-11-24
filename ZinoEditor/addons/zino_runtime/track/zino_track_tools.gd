@tool
class_name ZinoTrackTools
extends RefCounted
## Track Studio algorithms: procedural circuits, racing lines, checkpoints/sectors, starting grids,
## pit lanes and barrier geometry. Everything returns plain entities/points so results are editable.

## Generates a closed circuit. params: seed, radius, corners, irregularity, width, elevation, banking.
static func generate_circuit(params: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", 1))
	var radius := float(params.get("radius", 90.0))
	var corners := clampi(int(params.get("corners", 10)), 5, 40)
	var irregular := clampf(float(params.get("irregularity", 0.35)), 0.0, 0.8)
	var elevation := float(params.get("elevation", 0.0))
	var width := float(params.get("width", 12.0))
	# Smooth, low-frequency radius variation (two random harmonics) instead of per-point noise.
	var h1 := rng.randf_range(-1.0, 1.0) * irregular
	var h2 := rng.randf_range(-1.0, 1.0) * irregular * 0.6
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var pts: Array = []
	for i in corners:
		var a := TAU * i / corners + rng.randf_range(-0.12, 0.12) * TAU / corners
		var r := radius * (1.0 + h1 * sin(2.0 * a + p1) + h2 * sin(3.0 * a + p2) + rng.randf_range(-0.08, 0.08) * irregular)
		var y := maxf(0.0, sin(a * 2.0 + p1) * elevation) if elevation > 0.0 else 0.0
		pts.append(Vector3(cos(a) * r, y, sin(a) * r))
	# Relax until the tightest corner is at least 1.5 x the road width.
	var min_radius := width * 1.5
	for _iter in 60:
		var probe := ZinoEntities.road(pts, "probe", width, true)
		if stats(probe.road, Transform3D.IDENTITY).minRadius >= min_radius:
			break
		var smoothed: Array = []
		for i in pts.size():
			var prev: Vector3 = pts[(i - 1 + pts.size()) % pts.size()]
			var next: Vector3 = pts[(i + 1) % pts.size()]
			smoothed.append((pts[i] as Vector3).lerp((prev + next) * 0.5, 0.3))
		# Keep the overall size: rescale to the original mean radius.
		var mean := 0.0
		for q in smoothed:
			mean += Vector2(q.x, q.z).length()
		mean /= smoothed.size()
		pts = smoothed.map(func(q): return Vector3(q.x * radius / mean, q.y, q.z * radius / mean))
	var road := ZinoEntities.road(pts, "Generated Circuit", width, true)
	road["road"]["banking"] = float(params.get("banking", 0.0))
	road["road"]["centerLine"] = true
	return [road]

## Samples a road's centreline in world space (road_xform = the road entity's transform).
static func world_centerline(road: Dictionary, road_xform: Transform3D) -> PackedVector3Array:
	var c := ZinoRoadBuilder.sample_centerline(road)
	var out := PackedVector3Array()
	for p in c.points:
		out.append(road_xform * p)
	return out

## A smooth racing line inside the road: iterative curvature smoothing clamped to the road width.
static func racing_line(road: Dictionary, road_xform: Transform3D, margin: float = 1.6) -> PackedVector3Array:
	var center := world_centerline(road, road_xform)
	var n := center.size()
	if n < 4:
		return center
	var closed: bool = road.get("closed", false)
	var half := maxf(0.0, float(road.get("width", 12.0)) * 0.5 - margin)
	var line := center.duplicate()
	for _iter in 120:
		for i in n:
			if not closed and (i == 0 or i == n - 1):
				continue
			var prev := line[(i - 1 + n) % n]
			var next := line[(i + 1) % n]
			var target := (prev + next) * 0.5
			var p := line[i].lerp(target, 0.5)
			# Clamp the lateral offset from the centreline.
			var off := p - center[i]
			off.y = 0.0
			if off.length() > half:
				off = off.normalized() * half
			p = center[i] + off
			line[i] = p
	return line

## Evenly spaced checkpoints (by distance) across the road, facing along it. Index 0 = start/finish.
static func checkpoints(road: Dictionary, road_xform: Transform3D, count: int, start_distance: float = 0.0) -> Array:
	var pts := world_centerline(road, road_xform)
	var closed: bool = road.get("closed", false)
	var total := _length(pts, closed)
	var width := float(road.get("width", 12.0))
	var out: Array = []
	count = maxi(1, count)
	for i in count + (0 if closed else 1):
		var d := fmod(start_distance + total * i / float(count), total) if closed else total * i / float(count)
		var at := _at_distance(pts, closed, d)
		var e: Dictionary
		if i == 0:
			e = ZinoEntities.start_finish()
		elif not closed and i == count:
			e = ZinoEntities.checkpoint(i, "Finish")
		else:
			e = ZinoEntities.checkpoint(i)
		ZinoEntities.set_pos(e, at.pos + Vector3.UP * 2.0)
		# Local X (the trigger width) must lie across the road: yaw = atan2(dir.x, dir.z).
		ZinoEntities.set_rot(e, Vector3(0, rad_to_deg(atan2(at.dir.x, at.dir.z)), 0))
		e["trigger"]["size"] = [width + 2.0, 4.0, 1.0]
		out.append(e)
	return out

## Grid slots behind the start, staggered two by two, facing the driving direction.
static func grid(road: Dictionary, road_xform: Transform3D, slots: int, start_distance: float = 0.0) -> Array:
	var pts := world_centerline(road, road_xform)
	var closed: bool = road.get("closed", false)
	var total := _length(pts, closed)
	var width := float(road.get("width", 12.0))
	var out: Array = []
	for i in maxi(1, slots):
		var back: float = 8.0 + 7.0 * floor(i / 2.0) + 2.5 * (i % 2)
		var d := fposmod(start_distance - back, total) if closed else maxf(0.0, start_distance + back)
		var at := _at_distance(pts, closed, d)
		var right: Vector3 = at.dir.cross(Vector3.UP).normalized()
		var side := (-1.0 if i % 2 == 0 else 1.0) * width * 0.22
		var e := ZinoEntities.spawn_point(i)
		ZinoEntities.set_pos(e, at.pos + right * side + Vector3.UP * ZinoRoadBuilder.SURFACE_LIFT)
		ZinoEntities.set_rot(e, Vector3(0, rad_to_deg(atan2(-at.dir.x, -at.dir.z)), 0))
		out.append(e)
	return out

## A pit lane: an open road running parallel to the main road around the start, with entry and exit.
static func pit_lane(road: Dictionary, road_xform: Transform3D, length: float = 120.0, lane_width: float = 7.0) -> Dictionary:
	var pts := world_centerline(road, road_xform)
	var closed: bool = road.get("closed", false)
	var total := _length(pts, closed)
	var width := float(road.get("width", 12.0))
	var offset := width * 0.5 + lane_width * 0.5 + 3.0
	var lane: Array = []
	var steps := 8
	for i in steps + 1:
		var d := fposmod(-length * 0.5 + length * i / steps, total) if closed else clampf(length * i / steps, 0.0, total)
		var at := _at_distance(pts, closed, d)
		var right: Vector3 = at.dir.cross(Vector3.UP).normalized()
		var taper := 1.0 if i > 0 and i < steps else 0.35
		lane.append(at.pos + right * offset * taper)
	var e := ZinoEntities.road(lane, "Pit Lane", lane_width, false)
	e["road"]["surface"] = "concrete"
	return e

static func barrier(road_id: String, side: String = "both", style: String = "guardrail") -> Dictionary:
	var e := ZinoEntities.base(ZinoEntities.TYPE_BARRIER, {"guardrail": "Guardrail", "wall": "Concrete Wall", "tires": "Tyre Barrier"}.get(style, "Barrier"))
	e["barrier"] = {"roadId": road_id, "side": side, "style": style, "offset": 2.0, "height": 0.9}
	return e

## Builds barrier geometry + collision along a road (in world space) under `parent`.
static func build_barrier(parent: Node3D, b: Dictionary, road: Dictionary, road_xform: Transform3D) -> void:
	var pts := world_centerline(road, road_xform)
	var closed: bool = road.get("closed", false)
	if pts.size() < 2:
		return
	var inv := parent.transform.affine_inverse()   # barrier entities sit at the origin by default
	var half := float(road.get("width", 12.0)) * 0.5 + float(road.get("shoulderWidth", 1.2)) + float(b.get("offset", 2.0))
	var style := str(b.get("style", "guardrail"))
	var h := 6.5 if style == "tunnel" else float(b.get("height", 0.9))
	var mat: Material
	match style:
		"wall", "tunnel": mat = ZinoMaterials.get_material({"preset": "concrete"})
		"tires": mat = ZinoMaterials.get_material({"preset": "rubber"})
		_: mat = ZinoMaterials.get_material({"preset": "metal", "color": [0.78, 0.8, 0.82, 1.0], "metallic": 0.9, "roughness": 0.35})
	var sides: Array = [-1.0, 1.0] if b.get("side", "both") == "both" else ([-1.0] if b.get("side") == "left" else [1.0])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var thick := 0.35 if style in ["wall", "tunnel"] else 0.12
	if style == "tunnel":
		sides = [-1.0, 1.0]
	var n := pts.size()
	var count := n if closed else n - 1
	for s in sides:
		for i in count:
			var a := pts[i]
			var c := pts[(i + 1) % n]
			var dir_a := (pts[(i + 1) % n] - pts[(i - 1 + n) % n] if closed or i > 0 else pts[1] - pts[0]).normalized()
			var dir_c := (pts[(i + 2) % n] - pts[i] if closed or i + 2 < n else pts[n - 1] - pts[n - 2]).normalized()
			var ra: Vector3 = dir_a.cross(Vector3.UP).normalized() * s
			var rc: Vector3 = dir_c.cross(Vector3.UP).normalized() * s
			var a0 := inv * (a + ra * half)
			var c0 := inv * (c + rc * half)
			var a1 := a0 + Vector3.UP * h
			var c1 := c0 + Vector3.UP * h
			var a2 := a0 + (inv.basis * ra).normalized() * thick
			var c2 := c0 + (inv.basis * rc).normalized() * thick
			var a3 := a2 + Vector3.UP * h
			var c3 := c2 + Vector3.UP * h
			for q in [[a0, c0, c1, a1], [c2, a2, a3, c3], [a1, c1, c3, a3]]:
				_quad(st, q, faces)
	if style == "tunnel":
		# Roof spanning both walls.
		for i in count:
			var a := pts[i]
			var c := pts[(i + 1) % n]
			var dir := (c - a).normalized()
			var r := dir.cross(Vector3.UP).normalized()
			var la := inv * (a - r * half + Vector3.UP * h)
			var ra := inv * (a + r * half + Vector3.UP * h)
			var lc := inv * (c - r * half + Vector3.UP * h)
			var rc := inv * (c + r * half + Vector3.UP * h)
			_quad(st, [la, ra, rc, lc], faces)
	st.generate_normals()
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.name = "BarrierMesh"
	mi.mesh = st.commit()
	parent.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "BarrierCollision"
	body.collision_layer = ZinoSceneBuilder.GAMEPLAY_LAYER
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)

static func _quad(st: SurfaceTool, q: Array, faces: PackedVector3Array) -> void:
	for v in [q[0], q[1], q[2], q[0], q[2], q[3], q[0], q[2], q[1], q[0], q[3], q[2]]:
		st.add_vertex(v)
	for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
		faces.append(v)

static func _length(pts: PackedVector3Array, closed: bool) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	if closed and pts.size() > 2:
		total += pts[pts.size() - 1].distance_to(pts[0])
	return total

static func _at_distance(pts: PackedVector3Array, closed: bool, d: float) -> Dictionary:
	var n := pts.size()
	var acc := 0.0
	var segs := n if closed else n - 1
	for i in segs:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var l := a.distance_to(b)
		if acc + l >= d or i == segs - 1:
			var t := clampf((d - acc) / maxf(l, 0.0001), 0.0, 1.0)
			return {"pos": a.lerp(b, t), "dir": (b - a).normalized()}
		acc += l
	return {"pos": pts[0], "dir": (pts[1] - pts[0]).normalized()}

## Track statistics for the Track Studio.
static func stats(road: Dictionary, road_xform: Transform3D) -> Dictionary:
	var pts := world_centerline(road, road_xform)
	var closed: bool = road.get("closed", false)
	var min_r := INF
	var corners := 0
	var in_corner := false
	for i in pts.size():
		if not closed and (i == 0 or i >= pts.size() - 2):
			continue
		var r := ZinoAIDriver._radius(pts[(i - 1 + pts.size()) % pts.size()], pts[i], pts[(i + 1) % pts.size()])
		min_r = minf(min_r, r)
		if r < 60.0 and not in_corner:
			corners += 1
		in_corner = r < 60.0
	return {"length": _length(pts, closed), "minRadius": min_r, "corners": corners, "closed": closed}
