extends ZinoTest
## Drives the real ZinoVehicle on a real road with the physics engine (headless).

func _make_world(profile: String = "arcade") -> Dictionary:
	var root := Node3D.new()
	tree.root.add_child(root)
	var scene := ZinoTemplates.racing_test_scene(profile)
	var builder := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "performance")
	builder.build(scene)
	var car := builder.player_vehicle()
	car.input_enabled = false   # the test drives it directly
	return {"root": root, "builder": builder, "car": car}

func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame

func test_vehicle_has_four_wheels_and_settles_on_road() -> void:
	var w := _make_world()
	var car: ZinoVehicle = w.car
	check_eq(car.wheel_count(), 4, "four wheels")
	await _frames(240)
	check_eq(car.grounded_wheels(), 4, "all wheels touch the road after settling")
	check(car.global_position.y > 0.3 and car.global_position.y < 1.5, "body rests at a sensible height (%.2f)" % car.global_position.y)
	check(car.linear_velocity.length() < 0.5, "car is at rest (%.2f m/s)" % car.linear_velocity.length())
	w.root.free()

func test_throttle_moves_car_forward_and_brake_stops_it() -> void:
	var w := _make_world()
	var car: ZinoVehicle = w.car
	await _frames(180)
	var start := car.global_position
	var fwd := -car.global_transform.basis.z
	car.throttle = 1.0
	await _frames(360)   # 3 s at 120 Hz
	var moved := (car.global_position - start).dot(fwd)
	print("    3 s full throttle: %.1f m forward, %.1f km/h, gear %d, rpm %.0f" % [moved, car.speed_kmh, car.gear, car.rpm])
	check(moved > 10.0, "car moved forward under throttle (%.1f m)" % moved)
	check(car.forward_speed > 5.0, "forward speed positive (%.1f m/s)" % car.forward_speed)
	check(car.speed_kmh > 40.0, "reaches > 40 km/h in 3 s (%.1f)" % car.speed_kmh)
	car.throttle = 0.0
	car.brake_input = 1.0
	var t := 0
	while car.forward_speed > 0.5 and t < 1200:
		await tree.physics_frame
		t += 1
	print("    braking to stop: %.2f s" % (t / 120.0))
	check(car.forward_speed <= 0.5, "brakes stop the car")
	w.root.free()

func test_steering_turns_the_car() -> void:
	var w := _make_world()
	var car: ZinoVehicle = w.car
	await _frames(120)
	var yaw0 := car.global_rotation.y
	car.throttle = 0.5
	car.steer_input = -1.0   # steer left
	await _frames(240)
	var dyaw := wrapf(car.global_rotation.y - yaw0, -PI, PI)
	print("    yaw change steering left: %.1f deg" % rad_to_deg(dyaw))
	check(dyaw > deg_to_rad(10.0), "steering left increases yaw (turns left)")
	w.root.free()

func test_automatic_gearbox_upshifts() -> void:
	var w := _make_world("drag")
	var car: ZinoVehicle = w.car
	await _frames(120)
	car.throttle = 1.0
	var max_gear := 1
	for i in 720:
		await tree.physics_frame
		max_gear = maxi(max_gear, car.gear)
	print("    drag car: %.1f km/h after 6 s, top gear reached %d" % [car.speed_kmh, max_gear])
	check(max_gear >= 3, "gearbox shifted up to at least 3rd")
	w.root.free()
