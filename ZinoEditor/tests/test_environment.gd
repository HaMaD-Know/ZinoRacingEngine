extends ZinoTest

func _world(settings_patch: Dictionary = {}) -> Dictionary:
	var root := Node3D.new()
	tree.root.add_child(root)
	var scene := ZinoTemplates.racing_test_scene()
	scene.settings.merge(settings_patch, true)
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "ultraMax")
	b.build(scene)
	var sun: DirectionalLight3D = null
	for e in scene.entities:
		if e.type == "light":
			sun = b.node_for(e.id)
	var env := ZinoEnvironment.new()
	root.add_child(env)
	env.setup(b.environment_node(), sun, scene.settings)
	return {"root": root, "b": b, "sun": sun, "env": env}

func test_time_of_day_and_headlights() -> void:
	var w := _world({"timeOfDay": 13.0})
	var env: ZinoEnvironment = w.env
	var beams := tree.get_nodes_in_group("zino_headlights")
	check_eq(beams.size(), 2, "the car has two headlight beams")
	var day_energy: float = w.sun.light_energy
	check(beams.all(func(l): return not l.visible), "headlights off at midday")
	env.set_time(23.0)
	check(env.is_night(), "23:00 is night")
	check(w.sun.light_energy < day_energy * 0.2, "sun dims to moonlight (%.2f → %.2f)" % [day_energy, w.sun.light_energy])
	check(beams.all(func(l): return l.visible), "headlights switch on at night")
	check(w.b.environment_node().environment.background_energy_multiplier < 0.2, "night sky")
	env.set_time(19.6)
	check(w.sun.light_color.g < 0.8, "sunset light is warm")
	w.root.free()

func test_weather_rain_wet_roads_and_fog() -> void:
	var w := _world()
	var env: ZinoEnvironment = w.env
	var asphalt := ZinoMaterials.get_material({"preset": "asphalt"})
	var dry := asphalt.roughness
	env.set_weather("rain")
	check(env.get_node_or_null("Rain") != null, "rain particles created")
	check(asphalt.roughness < dry * 0.5 and asphalt.clearcoat_enabled, "road becomes wet and glossy (%.2f → %.2f)" % [dry, asphalt.roughness])
	var fog_rain: float = w.b.environment_node().environment.fog_density
	env.set_weather("fog")
	check(w.b.environment_node().environment.fog_density > fog_rain, "fog weather is foggier than rain")
	env.set_weather("clear")
	await tree.process_frame
	check(env.get_node_or_null("Rain") == null, "rain stops")
	check_near(asphalt.roughness, dry, 0.001, "road dries")
	w.root.free()

func test_post_fx_settings() -> void:
	var w := _world({"postFx": {"dofEnabled": true, "dofDistance": 80.0, "dofAmount": 0.2, "glowIntensity": 1.5, "contrast": 1.2, "saturation": 0.8, "speedBlur": true}})
	var we: WorldEnvironment = w.b.environment_node()
	check(we.camera_attributes.dof_blur_far_enabled, "depth of field enabled")
	check_near(we.camera_attributes.dof_blur_far_distance, 80.0, 0.01, "DOF distance")
	check_near(we.environment.glow_intensity, 1.5, 0.001, "glow intensity")
	check_near(we.environment.adjustment_contrast, 1.2, 0.001, "contrast")
	check_near(we.environment.adjustment_saturation, 0.8, 0.001, "saturation")
	var car: ZinoVehicle = w.b.player_vehicle()
	car.freeze = true
	var fake := {"car": car}
	var ctx := RefCounted.new()
	var fx := ZinoSpeedFx.new()
	fx.context = _FakeCtx.new(car)
	tree.root.add_child(fx)
	car.speed_kmh = 40.0
	for i in 30:
		await tree.process_frame
	var slow := fx.current_amount()
	car.speed_kmh = 240.0
	for i in 60:
		await tree.process_frame
	check(slow < 0.01 and fx.current_amount() > 0.5, "speed blur grows with speed (%.2f → %.2f)" % [slow, fx.current_amount()])
	fx.free()
	w.root.free()

class _FakeCtx:
	var car
	func _init(c) -> void:
		car = c
	func vehicle(_n):
		return car
