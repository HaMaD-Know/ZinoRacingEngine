@tool
class_name ZinoWorld
extends RefCounted
## Open-world builders: chunked terrain (procedural + sculpted heights, slope/height/paint shading,
## roads flattened into it), vegetation scattering, water and procedural buildings.
## Distance-based visibility ranges stream chunks and vegetation in and out.

const CHUNKS := 4               # terrain is split into CHUNKS x CHUNKS meshes for culling/streaming

# --- Terrain ---------------------------------------------------------------------------------

static func default_terrain() -> Dictionary:
	return {"size": 1200.0, "resolution": 129, "height": 60.0, "seed": 3, "frequency": 0.0025,
		"flattenRoads": true, "heights": "", "paint": "", "streamDistance": 900.0}

## Height samples (resolution²): procedural noise plus sculpted offsets (stored base64 in "heights").
static func terrain_heights(t: Dictionary, scene: Dictionary = {}, terrain_xform: Transform3D = Transform3D.IDENTITY) -> PackedFloat32Array:
	var res := clampi(int(t.get("resolution", 129)), 9, 513)
	var size := float(t.get("size", 1200.0))
	var stored := str(t.get("heights", ""))
	if stored != "":
		var raw := Marshalls.base64_to_raw(stored)
		var arr := raw.to_float32_array()
		if arr.size() == res * res:
			return arr
	var n := FastNoiseLite.new()
	n.seed = int(t.get("seed", 3))
	n.frequency = float(t.get("frequency", 0.0025))
	n.fractal_octaves = 5
	var amp := float(t.get("height", 60.0))
	var h := PackedFloat32Array()
	h.resize(res * res)
	for z in res:
		for x in res:
			var wx := (float(x) / (res - 1) - 0.5) * size
			var wz := (float(z) / (res - 1) - 0.5) * size
			# Valleys near the centre, mountains towards the edges.
			var edge := clampf(Vector2(wx, wz).length() / (size * 0.5), 0.0, 1.0)
			h[z * res + x] = (n.get_noise_2d(wx, wz) * 0.5 + 0.5) * amp * (0.25 + 0.75 * edge * edge) - 2.0
	if t.get("flattenRoads", true) and not scene.is_empty():
		_flatten_roads(h, res, size, scene, terrain_xform)
	return h

static func encode_heights(h: PackedFloat32Array) -> String:
	return Marshalls.raw_to_base64(h.to_byte_array())

static func _flatten_roads(h: PackedFloat32Array, res: int, size: float, scene: Dictionary, txf: Transform3D) -> void:
	var inv := txf.affine_inverse()
	for e in scene.get("entities", []):
		if e.get("type") != ZinoEntities.TYPE_ROAD:
			continue
		var road: Dictionary = e.road
		var pts := ZinoTrackTools.world_centerline(road, ZinoFormat.transform_from_entity(e))
		var half := float(road.get("width", 12.0)) * 0.5 + float(road.get("shoulderWidth", 1.2)) + 3.0
		var cell := size / (res - 1)
		for p in pts:
			var lp := inv * p
			var cx := int(round((lp.x / size + 0.5) * (res - 1)))
			var cz := int(round((lp.z / size + 0.5) * (res - 1)))
			var r := int(ceil((half + 12.0) / cell))
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var x := cx + dx
					var z := cz + dz
					if x < 0 or z < 0 or x >= res or z >= res:
						continue
					var d := Vector2(dx, dz).length() * cell
					var target := lp.y - 0.15
					var k := 1.0 if d <= half else clampf(1.0 - (d - half) / 12.0, 0.0, 1.0)
					var i := z * res + x
					h[i] = lerpf(h[i], target, k)

## Height of the terrain at a local x/z (bilinear).
static func sample(h: PackedFloat32Array, res: int, size: float, x: float, z: float) -> float:
	var fx := clampf((x / size + 0.5) * (res - 1), 0.0, res - 1.001)
	var fz := clampf((z / size + 0.5) * (res - 1), 0.0, res - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(h[iz * res + ix], h[iz * res + ix + 1], tx)
	var b := lerpf(h[(iz + 1) * res + ix], h[(iz + 1) * res + ix + 1], tx)
	return lerpf(a, b, tz)

static func build_terrain(parent: Node3D, t: Dictionary, h: PackedFloat32Array) -> void:
	var res := clampi(int(t.get("resolution", 129)), 9, 513)
	var size := float(t.get("size", 1200.0))
	var paint := PackedByteArray()
	if str(t.get("paint", "")) != "":
		paint = Marshalls.base64_to_raw(str(t.paint))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = ZinoMaterials.get_material({"preset": "grass"}).albedo_texture
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.08, 0.08, 0.08)
	mat.roughness = 0.95
	var cells := res - 1
	var per := int(ceil(float(cells) / CHUNKS))
	var stream := float(t.get("streamDistance", 900.0))
	for cz in CHUNKS:
		for cx in CHUNKS:
			var x0 := cx * per
			var z0 := cz * per
			var x1 := mini(x0 + per, cells)
			var z1 := mini(z0 + per, cells)
			if x0 >= x1 or z0 >= z1:
				continue
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for z in range(z0, z1):
				for x in range(x0, x1):
					var quad := [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]
					for k in [0, 1, 2, 0, 2, 3]:
						var g: Vector2i = quad[k]
						var i := g.y * res + g.x
						var pos := Vector3((float(g.x) / cells - 0.5) * size, h[i], (float(g.y) / cells - 0.5) * size)
						st.set_color(_shade(h, res, size, g.x, g.y, paint))
						st.set_uv(Vector2(pos.x, pos.z) * 0.05)
						st.add_vertex(pos)
			st.generate_normals()
			st.set_material(mat)
			var mi := MeshInstance3D.new()
			mi.name = "TerrainChunk_%d_%d" % [cx, cz]
			mi.mesh = st.commit()
			mi.visibility_range_end = stream
			mi.visibility_range_end_margin = 60.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			parent.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = ZinoSceneBuilder.GAMEPLAY_LAYER
	var cs := CollisionShape3D.new()
	var hs := HeightMapShape3D.new()
	hs.map_width = res
	hs.map_depth = res
	hs.map_data = h
	cs.shape = hs
	cs.scale = Vector3(size / (res - 1), 1.0, size / (res - 1))
	body.add_child(cs)
	parent.add_child(body)

static func _shade(h: PackedFloat32Array, res: int, size: float, x: int, z: int, paint: PackedByteArray) -> Color:
	var i := z * res + x
	var cell := size / (res - 1)
	var hx := h[z * res + mini(x + 1, res - 1)] - h[z * res + maxi(x - 1, 0)]
	var hz := h[mini(z + 1, res - 1) * res + x] - h[maxi(z - 1, 0) * res + x]
	var slope := clampf(Vector2(hx, hz).length() / (2.0 * cell), 0.0, 1.5)
	var grass := Color(0.32, 0.5, 0.2)
	var dirt := Color(0.45, 0.36, 0.26)
	var rock := Color(0.5, 0.49, 0.47)
	var snow := Color(0.92, 0.93, 0.96)
	var c := grass.lerp(rock, smoothstep(0.45, 0.9, slope))
	c = c.lerp(snow, smoothstep(45.0, 60.0, h[i]) * (1.0 - smoothstep(0.6, 1.0, slope)))
	if paint.size() == res * res:
		var p := paint[i]   # 0 = auto, 1 = grass, 2 = dirt, 3 = rock, 4 = sand
		match p:
			1: c = grass
			2: c = dirt
			3: c = rock
			4: c = Color(0.82, 0.74, 0.55)
	return c

# --- Vegetation ------------------------------------------------------------------------------

static func default_vegetation() -> Dictionary:
	return {"area": 900.0, "trees": 900, "grass": 2500, "rocks": 150, "seed": 9, "roadClearance": 6.0, "streamDistance": 500.0}

## Scatters trees, grass tufts and rocks over the terrain (if any), keeping clear of roads.
static func build_vegetation(parent: Node3D, v: Dictionary, scene: Dictionary, terrain_sampler: Callable, world_xform: Transform3D) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(v.get("seed", 9))
	var area := float(v.get("area", 900.0))
	var clearance := float(v.get("roadClearance", 6.0))
	var roads: Array = []
	for e in scene.get("entities", []):
		if e.get("type") == ZinoEntities.TYPE_ROAD:
			roads.append({"pts": ZinoTrackTools.world_centerline(e.road, ZinoFormat.transform_from_entity(e)), "half": float(e.road.get("width", 12.0)) * 0.5 + clearance})
	var counts := {}
	for kind in ["trees", "grass", "rocks"]:
		var wanted := int(v.get(kind, 0))
		var xforms: Array = []
		var tries := 0
		while xforms.size() < wanted and tries < wanted * 4:
			tries += 1
			var p := Vector3(rng.randf_range(-0.5, 0.5) * area, 0, rng.randf_range(-0.5, 0.5) * area)
			var wp := world_xform * p
			if _near_road(wp, roads):
				continue
			var y: float = terrain_sampler.call(wp.x, wp.z)
			if y < 0.2 and kind != "rocks":
				continue   # nothing grows under water level
			var s := rng.randf_range(0.7, 1.4)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
			xforms.append(Transform3D(basis, world_xform.affine_inverse() * Vector3(wp.x, y, wp.z)))
		counts[kind] = xforms.size()
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _veg_mesh(kind)
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = kind.capitalize()
		mmi.multimesh = mm
		mmi.visibility_range_end = float(v.get("streamDistance", 500.0)) * (0.35 if kind == "grass" else 1.0)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == "grass" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mmi)
		if kind == "trees":
			var body := StaticBody3D.new()
			body.name = "TreeCollision"
			body.collision_layer = ZinoSceneBuilder.GAMEPLAY_LAYER
			for x in xforms:
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = 0.3
				cyl.height = 4.0
				cs.shape = cyl
				cs.position = (x as Transform3D).origin + Vector3.UP * 2.0
				body.add_child(cs)
			parent.add_child(body)
	return counts

static func _near_road(p: Vector3, roads: Array) -> bool:
	var q := Vector2(p.x, p.z)
	for r in roads:
		var pts: PackedVector3Array = r.pts
		for i in range(pts.size() - 1):
			# Distance to the segment, not just its end points (samples can be 20+ m apart).
			var a := Vector2(pts[i].x, pts[i].z)
			var c := Vector2(pts[i + 1].x, pts[i + 1].z)
			if Geometry2D.get_closest_point_to_segment(q, a, c).distance_to(q) < r.half:
				return true
	return false

static var _veg_meshes := {}
static func _veg_mesh(kind: String) -> Mesh:
	if _veg_meshes.has(kind):
		return _veg_meshes[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m: Mesh
	match kind:
		"trees":
			var am := ArrayMesh.new()
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.18; trunk.bottom_radius = 0.28; trunk.height = 3.0; trunk.radial_segments = 8
			var leaves := CylinderMesh.new()
			leaves.top_radius = 0.0; leaves.bottom_radius = 2.0; leaves.height = 6.0; leaves.radial_segments = 10
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color(0.35, 0.24, 0.15)
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(0.16, 0.36, 0.17)
			lm.roughness = 0.9
			st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 1.5, 0)))
			st.set_material(tm)
			st.commit(am)
			var st2 := SurfaceTool.new()
			st2.begin(Mesh.PRIMITIVE_TRIANGLES)
			st2.append_from(leaves, 0, Transform3D(Basis(), Vector3(0, 5.5, 0)))
			st2.set_material(lm)
			st2.commit(am)
			m = am
		"grass":
			var q := QuadMesh.new()
			q.size = Vector2(0.9, 0.6)
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.35, 0.55, 0.22)
			gm.cull_mode = BaseMaterial3D.CULL_DISABLED
			gm.roughness = 1.0
			st.append_from(q, 0, Transform3D(Basis(), Vector3(0, 0.3, 0)))
			st.append_from(q, 0, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 0.3, 0)))
			st.set_material(gm)
			m = st.commit()
		_:
			var s := SphereMesh.new()
			s.radius = 0.8; s.height = 1.1; s.radial_segments = 7; s.rings = 4
			s.material = ZinoMaterials.get_material({"preset": "concrete"})
			m = s
	_veg_meshes[kind] = m
	return m

# --- Water and buildings ------------------------------------------------------------------------

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 deep : source_color = vec4(0.03, 0.18, 0.28, 0.85);
uniform vec4 shallow : source_color = vec4(0.12, 0.42, 0.5, 0.7);
void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.08 + TIME * 1.2) * 0.12 + cos(VERTEX.z * 0.06 + TIME) * 0.1;
}
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep.rgb, shallow.rgb, f);
	ALPHA = mix(deep.a, 1.0, f * 0.5);
	ROUGHNESS = 0.04;
	METALLIC = 0.1;
	SPECULAR = 0.8;
	NORMAL_MAP = vec3(0.5 + sin(UV.x * 80.0 + TIME * 2.0) * 0.04, 0.5 + cos(UV.y * 70.0 + TIME * 1.7) * 0.04, 1.0);
}
"""

static func build_water(parent: Node3D, w: Dictionary) -> void:
	var size := ZinoFormat.v3([w.get("size", [300, 0, 300])[0], 0, w.get("size", [300, 0, 300])[2]]) if w.get("size") is Array else Vector3(300, 0, 300)
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x, size.z)
	pm.subdivide_width = 64
	pm.subdivide_depth = 64
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	pm.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "WaterSurface"
	mi.mesh = pm
	parent.add_child(mi)

static func build_building(parent: Node3D, b: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b.get("seed", 1))
	var floors := clampi(int(b.get("floors", 6)), 1, 80)
	var w := float(b.get("width", 18.0))
	var d := float(b.get("depth", 14.0))
	var fh := 3.2
	var h := floors * fh
	var body := MeshInstance3D.new()
	body.name = "Building"
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	body.mesh = bm
	body.position.y = h * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.62, 0.6).lerp(Color(0.45, 0.48, 0.55), rng.randf())
	mat.albedo_texture = _window_texture(floors, rng)
	mat.emission_enabled = true
	mat.emission_texture = mat.albedo_texture
	mat.emission_energy_multiplier = 0.25
	mat.uv1_scale = Vector3(3, 2, 1)
	mat.roughness = 0.6
	mat.metallic = 0.2
	body.material_override = mat
	parent.add_child(body)
	var col := StaticBody3D.new()
	col.name = "BuildingCollision"
	col.collision_layer = ZinoSceneBuilder.GAMEPLAY_LAYER
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	cs.position.y = h * 0.5
	col.add_child(cs)
	parent.add_child(col)

static func _window_texture(floors: int, rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create(64, 64, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.55, 0.55, 0.55))
	for row in 8:
		for col in 8:
			var lit := rng.randf() < 0.35
			var c := Color(1.0, 0.86, 0.55) if lit else Color(0.12, 0.16, 0.22)
			img.fill_rect(Rect2i(col * 8 + 1, row * 8 + 2, 6, 4), c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
