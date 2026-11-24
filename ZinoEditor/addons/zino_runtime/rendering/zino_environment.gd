class_name ZinoEnvironment
extends Node
## Runtime environment control: time of day (sun position, colour, sky energy, night lighting),
## weather (clear, cloudy, rain, storm, fog) with GPU rain particles, wet roads and lightning.

var world_env: WorldEnvironment
var sun: DirectionalLight3D
var camera_provider: Callable = func(): return null
var hours := 15.0
var weather := "clear"
var _base_sun_energy := 1.3
var _base_fog := 0.0008
var _rain: GPUParticles3D
var _lightning_timer := 0.0
var _flash := 0.0
var _wet := 0.0

func setup(env_node: WorldEnvironment, sun_light: DirectionalLight3D, settings: Dictionary) -> void:
	world_env = env_node
	sun = sun_light
	if sun:
		_base_sun_energy = sun.light_energy
	_base_fog = float(settings.get("fogDensity", 0.0008))
	hours = float(settings.get("timeOfDay", 15.0))
	set_time(hours)
	set_weather(str(settings.get("weather", "clear")))

func set_time(h: float) -> void:
	hours = fposmod(h, 24.0)
	if sun == null:
		return
	# Sun rises at 6:00, peaks at 13:00, sets at 20:00.
	var day_t := (hours - 6.0) / 14.0
	var elevation := sin(clampf(day_t, 0.0, 1.0) * PI) * 62.0
	var azimuth := lerpf(-100.0, 100.0, clampf(day_t, 0.0, 1.0))
	var night := day_t < 0.0 or day_t > 1.0
	sun.rotation_degrees = Vector3(-maxf(elevation, 4.0) if not night else -35.0, azimuth, 0.0)
	var low := clampf(1.0 - elevation / 25.0, 0.0, 1.0)
	sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.58, 0.32), low)
	if night:
		sun.light_color = Color(0.55, 0.65, 0.95)      # moonlight
	sun.light_energy = (_base_sun_energy * (1.0 - 0.55 * low) if not night else 0.08) * _weather_light()
	set_headlights(night or low > 0.85 or weather in ["storm", "fog"])
	if world_env and world_env.environment:
		var env := world_env.environment
		env.background_energy_multiplier = 0.06 if night else lerpf(1.0, 0.55, low)
		env.ambient_light_energy = 0.25 if night else lerpf(1.0, 0.7, low)
		if env.sky and env.sky.sky_material is PhysicalSkyMaterial:
			(env.sky.sky_material as PhysicalSkyMaterial).energy_multiplier = 0.05 if night else 1.0

func set_headlights(on: bool) -> void:
	if not is_inside_tree():
		return
	for l in get_tree().get_nodes_in_group("zino_headlights"):
		(l as Node3D).visible = on

func is_night() -> bool:
	var day_t := (hours - 6.0) / 14.0
	return day_t < 0.0 or day_t > 1.0

func set_weather(kind: String) -> void:
	weather = kind if kind in ["clear", "cloudy", "rain", "storm", "fog"] else "clear"
	if world_env and world_env.environment:
		var env := world_env.environment
		var fog_mult: float = {"clear": 1.0, "cloudy": 1.6, "rain": 3.5, "storm": 5.0, "fog": 14.0}[weather]
		env.fog_density = _base_fog * fog_mult
		env.volumetric_fog_density = _base_fog * fog_mult * 1.5
		if env.sky and env.sky.sky_material is PhysicalSkyMaterial:
			(env.sky.sky_material as PhysicalSkyMaterial).turbidity = {"clear": 8.0, "cloudy": 18.0, "rain": 30.0, "storm": 40.0, "fog": 25.0}[weather]
	_set_rain(weather in ["rain", "storm"])
	_wet = 1.0 if weather in ["rain", "storm"] else 0.0
	ZinoMaterials.set_wetness(_wet)
	set_time(hours)

func set_fog(density: float) -> void:
	_base_fog = maxf(0.0, density)
	set_weather(weather)

func _weather_light() -> float:
	return {"clear": 1.0, "cloudy": 0.6, "rain": 0.45, "storm": 0.3, "fog": 0.55}.get(weather, 1.0)

func _set_rain(on: bool) -> void:
	if not on:
		if _rain:
			_rain.queue_free()
			_rain = null
		return
	if _rain:
		_rain.amount = 6000 if weather == "storm" else 3000
		return
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 6000 if weather == "storm" else 3000
	_rain.lifetime = 1.2
	_rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 1, 30)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3(0, -9.8, 0)
	_rain.process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.02, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.82, 0.95, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = mat
	_rain.draw_pass_1 = drop
	add_child(_rain)

func _process(delta: float) -> void:
	if _rain:
		var cam = camera_provider.call()
		if cam is Node3D:
			_rain.global_position = (cam as Node3D).global_position + Vector3(0, 14, 0)
	if weather == "storm" and sun:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = randf_range(4.0, 11.0)
			_flash = 1.0
		if _flash > 0.0:
			_flash = maxf(0.0, _flash - delta * 4.0)
			sun.light_energy = _base_sun_energy * _weather_light() + _flash * 3.0
