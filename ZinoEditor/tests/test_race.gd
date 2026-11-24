extends ZinoTest
## Race manager + AI on the real circuit with real physics: everyone is AI-driven, 1 lap.

func test_ai_race_completes_with_laps_positions_and_results() -> void:
	var root := Node3D.new()
	tree.root.add_child(root)
	var scene := ZinoTemplates.racing_test_scene("arcade")
	scene["settings"]["race"]["laps"] = 1
	scene["settings"]["race"]["countdown"] = 0.5
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "performance")
	b.build(scene)
	var ctx := ZinoGameContext.new()
	tree.root.add_child(ctx)
	ctx.start(b, "res://", [], {"ai_count": 2, "save_key": "test"})
	check_eq(ctx.ai_vehicles.size(), 2, "two AI opponents spawned on the grid")
	check_eq(ctx.race.racers.size(), 3, "three racers")
	check_eq(ctx.race.mode, "circuit", "closed road → circuit race")
	# Let an AI drive the player's car too.
	var player := b.player_vehicle()
	player.input_enabled = false
	var pd := ZinoAIDriver.new()
	pd.active = false
	ctx.add_child(pd)
	pd.setup(player, ctx.track_points(), true)
	ctx.ai_drivers.append(pd)
	pd.others = ctx.all_vehicles()
	var events := {"start": 0, "laps": 0, "cps": 0, "finished": 0}
	ctx.race.race_started.connect(func(): events.start += 1; pd.active = true)
	ctx.race.lap_completed.connect(func(_r, _l, _t): events.laps += 1)
	ctx.race.checkpoint_passed.connect(func(_r, _i): events.cps += 1)
	var done := {"v": false}
	ctx.race.race_finished.connect(func(): done.v = true)
	var max_jump := 0.0
	var last := {}
	for v in ctx.all_vehicles():
		last[v] = v.global_position
	var frames := 0
	while not done.v and frames < 120 * 90:
		await tree.physics_frame
		frames += 1
		for v in ctx.all_vehicles():
			max_jump = maxf(max_jump, v.global_position.distance_to(last[v]))
			last[v] = v.global_position
	print("    race finished=%s after %.1f s simulated; checkpoints %d, laps %d" % [done.v, frames / 120.0, events.cps, events.laps])
	check_eq(events.start, 1, "race started after the countdown")
	check(done.v, "all three cars finished one lap within 90 s")
	check(events.cps >= 9, "checkpoints passed in order (%d)" % events.cps)
	check_eq(events.laps, 3, "each racer completed its lap")
	var rows := ctx.race.results()
	check_eq(rows.map(func(r): return r.position), [1, 2, 3], "positions 1..3 in results")
	check(rows.all(func(r): return r.finished and r.best_lap > 10.0), "every racer has a lap time")
	print("    results: ", rows.map(func(r): return "%d %s %s" % [r.position, r.name, ZinoBlockRuntime.format_lap_time(r.time)]))
	check(max_jump < 1.5, "AI cars drove continuously, never teleported (max step %.2f m)" % max_jump)
	ctx.stop()
	ctx.free()
	root.free()

func test_checkpoints_must_be_taken_in_order() -> void:
	var root := Node3D.new()
	tree.root.add_child(root)
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "performance")
	b.build(ZinoTemplates.racing_test_scene())
	var rm := ZinoRaceManager.new()
	root.add_child(rm)
	rm.setup(b, [b.player_vehicle()], {"laps": 2, "countdown": 0})
	rm.start()
	var r: ZinoRaceManager.Racer = rm.racers[0]
	var car := b.player_vehicle()
	rm._on_area_entered(car, 2)
	check_eq(r.checkpoints_passed, 0, "skipping checkpoint 1 is ignored")
	rm._on_area_entered(car, 0)
	check_eq(r.lap, 1, "crossing the line before the checkpoints does not count a lap")
	for i in [1, 2, 3, 0]:
		rm._on_area_entered(car, i)
	check_eq(r.lap, 2, "full lap counted")
	for i in [1, 2, 3, 0]:
		rm._on_area_entered(car, i)
	check(r.finished, "finished after the final lap")
	check_eq(rm.state, "finished", "single racer → race finished")
	root.free()

func test_elimination_and_time_trial_rules() -> void:
	var root := Node3D.new()
	tree.root.add_child(root)
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "performance")
	b.build(ZinoTemplates.racing_test_scene())
	var player := b.player_vehicle()
	var cars: Array = [player]
	for i in 2:
		var v := ZinoVehicle.new()
		v.name = "Bot%d" % i
		v.configure(player.spec)
		root.add_child(v)
		v.global_position = player.global_position + Vector3(0, 0, 6 * (i + 1))
		cars.append(v)
	var rm := ZinoRaceManager.new()
	root.add_child(rm)
	rm.setup(b, cars, {"laps": 5, "countdown": 0, "mode": "elimination"})
	check_eq(rm.mode, "elimination", "elimination mode selected")
	rm.start()
	var eliminated: Array = []
	rm.racer_eliminated.connect(func(r): eliminated.append(r.name))
	# The player leads: complete a lap with the player only.
	for i in [1, 2, 3, 0]:
		rm._on_area_entered(player, i)
	check_eq(eliminated.size(), 1, "leader's lap eliminates the last car")
	for i in [1, 2, 3, 0]:
		rm._on_area_entered(player, i)
	check_eq(eliminated.size(), 2, "second lap eliminates the next car")
	check_eq(rm.state, "finished", "last car standing wins")
	var rows := rm.results()
	check(rows[0].player and rows[0].finished, "player classified first")
	check(rows[1].eliminated and rows[2].eliminated, "others classified as eliminated")
	root.free()

	var root2 := Node3D.new()
	tree.root.add_child(root2)
	var scene := ZinoTemplates.racing_test_scene()
	scene.settings.race.mode = "timeTrial"
	var b2 := ZinoSceneBuilder.new(root2, ZinoSceneBuilder.MODE_PLAY, "performance")
	b2.build(scene)
	var ctx := ZinoGameContext.new()
	tree.root.add_child(ctx)
	ctx.start(b2, "res://", [], {"save_key": "test"})
	check_eq(ctx.ai_vehicles.size(), 0, "time trial runs without AI opponents")
	check_eq(ctx.race.mode, "timeTrial", "time trial mode")
	ctx.stop()
	ctx.free()
	root2.free()

func test_replay_records_and_plays_back() -> void:
	var root := Node3D.new()
	tree.root.add_child(root)
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "performance")
	b.build(ZinoTemplates.racing_test_scene())
	var car := b.player_vehicle()
	car.input_enabled = false
	var rep := ZinoReplay.new()
	root.add_child(rep)
	rep.start_recording([car])
	await tree.physics_frame
	car.throttle = 1.0
	var mid_pose := Transform3D()
	for i in 240:
		await tree.physics_frame
		if i == 120:
			mid_pose = car.global_transform
	rep.stop_recording()
	check(rep.frames.size() > 50, "recorded %d frames" % rep.frames.size())
	var t_mid: float = rep.frames[0].t + 121.0 / 120.0
	check(rep.pose_at(0, t_mid).origin.distance_to(mid_pose.origin) < 0.6, "replay pose matches the recorded drive")
	var end_pos := car.global_position
	rep.play(root)
	check(car.freeze, "cars are frozen during the replay")
	await tree.process_frame
	await tree.process_frame
	check(car.global_position.distance_to(end_pos) > 3.0, "replay moved the car back to the start of the recording")
	rep.stop()
	root.free()
