@tool
class_name ZinoMaterials
extends RefCounted
## PBR material presets. Surface detail comes from procedural noise textures generated at runtime,
## so the engine ships no texture files and imported user textures are never touched.

static var _cache := {}
static var _noise_cache := {}

## Returns a shared material for the given material data ({preset, color, metallic, roughness}).
static func get_material(data: Dictionary) -> StandardMaterial3D:
	var key := ZinoFormat.to_json(data, false)
	if _cache.has(key):
		return _cache[key]
	var m := build(data)
	_cache[key] = m
	return m

static func clear_cache() -> void:
	_cache.clear()

static var _dry := {}

## Makes road surfaces look wet (0 = dry, 1 = soaked): darker, glossy, with a clear-coat sheen.
static func set_wetness(w: float) -> void:
	w = clampf(w, 0.0, 1.0)
	for key in _cache:
		var m: StandardMaterial3D = _cache[key]
		var preset := str(ZinoFormat.parse_json(key).data.get("preset", "")) if key.begins_with("{") else ""
		if not preset in ["asphalt", "concrete", "dirt", "gravel"]:
			continue
		if not _dry.has(m):
			_dry[m] = {"rough": m.roughness, "albedo": m.albedo_color}
		var d: Dictionary = _dry[m]
		m.roughness = lerpf(d.rough, 0.12, w)
		m.albedo_color = d.albedo.darkened(0.35 * w)
		m.clearcoat_enabled = w > 0.0
		m.clearcoat = w
		m.clearcoat_roughness = 0.05

static func build(data: Dictionary) -> StandardMaterial3D:
	var preset: String = data.get("preset", "default")
	var color := ZinoFormat.col(data.get("color"), Color(0.8, 0.8, 0.8))
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = float(data.get("metallic", 0.0))
	m.roughness = float(data.get("roughness", 0.6))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match preset:
		"asphalt":
			m.albedo_color = Color(0.085, 0.085, 0.09)
			m.roughness = 0.92
			m.albedo_texture = _noise("asphalt_albedo", 0.9, Color(0.7, 0.7, 0.72), Color(1.25, 1.25, 1.28))
			m.normal_enabled = true
			m.normal_texture = _noise_normal("asphalt_normal", 1.6, 2.0)
			m.normal_scale = 0.3
			m.roughness_texture = _noise("asphalt_rough", 1.3, Color(0.85, 0.85, 0.85), Color(1, 1, 1))
			m.uv1_triplanar = false
		"concrete":
			m.albedo_color = Color(0.55, 0.55, 0.53)
			m.roughness = 0.9
			m.albedo_texture = _noise("concrete_albedo", 0.35, Color(0.85, 0.85, 0.85), Color(1.05, 1.05, 1.05))
			m.normal_enabled = true
			m.normal_texture = _noise_normal("concrete_normal", 0.8, 1.2)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.25, 0.25, 0.25)
		"grass":
			m.roughness = 0.95
			m.albedo_texture = _noise("grass_albedo", 0.12, Color(0.7, 0.78, 0.62), Color(1.12, 1.08, 0.92))
			m.normal_enabled = true
			m.normal_texture = _noise_normal("grass_normal", 0.6, 1.5)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.08, 0.08, 0.08)
		"dirt", "gravel":
			m.albedo_color = Color(0.42, 0.33, 0.24) if preset == "dirt" else Color(0.5, 0.48, 0.45)
			m.roughness = 0.97
			m.albedo_texture = _noise(preset + "_albedo", 0.5, Color(0.75, 0.72, 0.68), Color(1.15, 1.1, 1.05))
			m.normal_enabled = true
			m.normal_texture = _noise_normal(preset + "_normal", 1.0, 3.0)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.2, 0.2, 0.2)
		"carPaint":
			# Metallic base with a glossy clear coat: the classic automotive paint model.
			m.metallic = 0.55
			m.roughness = 0.32
			m.metallic_specular = 0.6
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.04
		"metal":
			m.metallic = 1.0
			m.roughness = 0.25
		"rubber":
			m.albedo_color = Color(0.05, 0.05, 0.055)
			m.roughness = 0.92
			m.metallic = 0.0
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.albedo_color = Color(color.r * 0.2, color.g * 0.22, color.b * 0.25, 0.35)
			m.metallic = 0.2
			m.roughness = 0.02
			m.metallic_specular = 1.0
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.0
	# Texture maps (e.g. downloaded from the Asset Store) override the procedural ones.
	var albedo := ZinoAssets.load_texture(str(data.get("albedoTexture", ""))) if data.get("albedoTexture") else null
	if albedo:
		m.albedo_texture = albedo
		m.albedo_color = color if preset == "default" else Color.WHITE
	var normal := ZinoAssets.load_texture(str(data.get("normalTexture", ""))) if data.get("normalTexture") else null
	if normal:
		m.normal_enabled = true
		m.normal_texture = normal
	var rough := ZinoAssets.load_texture(str(data.get("roughnessTexture", ""))) if data.get("roughnessTexture") else null
	if rough:
		m.roughness_texture = rough
		m.roughness = 1.0
	if albedo or normal:
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * float(data.get("textureScale", 0.25))
	return m

static func unshaded(color: Color, on_top: bool = false, transparent: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent or color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if on_top:
		m.no_depth_test = true
		m.render_priority = 10
	return m

static func lane_marking() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.95, 0.92)
	m.roughness = 0.55
	return m

static func _noise(key: String, frequency_scale: float, dark: Color, light: Color) -> NoiseTexture2D:
	if _noise_cache.has(key):
		return _noise_cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.05 * frequency_scale
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.seed = key.hash()
	var ramp := Gradient.new()
	ramp.set_color(0, dark)
	ramp.set_color(1, light)
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	t.color_ramp = ramp
	_noise_cache[key] = t
	return t

static func _noise_normal(key: String, frequency_scale: float, bump: float) -> NoiseTexture2D:
	if _noise_cache.has(key):
		return _noise_cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.frequency = 0.08 * frequency_scale
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.seed = key.hash()
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	t.as_normal_map = true
	t.bump_strength = bump
	t.noise = n
	_noise_cache[key] = t
	return t
