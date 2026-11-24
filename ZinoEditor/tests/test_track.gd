extends ZinoTest
## Track Studio algorithms and a full AI lap on a procedurally generated circuit with guardrails.

func _generated_scene(seed: int) -> Dictionary:
	var scene := ZinoTemplates.empty("Gen")
	scene.settings.race.enabled = true
	scene.settings.race.laps = 1
	scene.settings.race.countdown = 0.0
	var road: Dictionary = ZinoTrackTools.generate_circuit({"seed": seed, "radius": 90, "corners": 10, "width": 12, "banking": 4})[0]
	scene.entities.append(road)
	scene.entities.append_array(ZinoTrackTools.checkpoints(road.road, Transform3D.IDENTITY, 4))
	var grid := ZinoTrackTools.grid(road.road, Transform3D.IDENTITY, 2)
	scene.entities.append_array(grid)
	scene.entities.append(ZinoTrackTools.barrier(road.id, "both", "guardrail"))
	var car := ZinoEntities.vehicle()
	var ride: float = float(car.vehicle.spec.wheelRadius) + float(car.vehicle.spec.suspensionRestLength) + ZinoFormat.v3(car.vehicle.spec.bodySize).y * 0.5
	ZinoEntities.set_pos(car, ZinoFormat.v3(grid[0].transform.position) + Vector3.UP * ride)
	ZinoEntities.set_rot(car, ZinoFormat.v3(grid[0].transform.rotation))
	scene.entities.append(car)
	scene.entities.append(ZinoEntities.camera("Chase", "chase", car.id))
	return scene

func test_generator_lines_checkpoints_and_grid() -> void:
	for seed in [1, 2, 3, 42, 777]:
		var scene := _generated_scene(seed)
		check(ZinoFormat.validate_scene(scene).is_empty(), "generated scene %d valid" % seed)
		var road: Dictionary = scene.entities.filter(func(e): return e.type == "road")[0]
		var st := ZinoTrackTools.stats(road.road, Transform3D.IDENTITY)
		check(st.closed and st.length > 300.0 and st.length < 1400.0, "seed %d: plausible length %.0f m" % [seed, st.length])
		check(st.minRadius > 8.0, "seed %d: no hairpin tighter than 8 m (%.1f m)" % [seed, st.minRadius])
		var center := ZinoTrackTools.world_centerline(road.road, Transform3D.IDENTITY)
		var line := ZinoTrackTools.racing_line(road.road, Transform3D.IDENTITY)
		var max_off := 0.0
		for i in line.size():
			var d := line[i] - center[i]
			d.y = 0
			max_off = maxf(max_off, d.length())
		check(max_off <= 12.0 * 0.5, "seed %d: racing line stays on the road (max offset %.2f m)" % [seed, max_off])
		check(ZinoTrackTools._length(line, true) <= ZinoTrackTools._length(center, true) + 0.01, "seed %d: racing line is not longer than the centreline" % seed)
	var scene := _generated_scene(5)
	check_eq(scene.entities.filter(func(e): return e.type == "startFinish").size(), 1, "one start/finish")
	check_eq(scene.entities.filter(func(e): return e.type == "checkpoint").size(), 3, "three sector checkpoints")
	check_eq(scene.entities.filter(func(e): return e.type == "spawnPoint").size(), 2, "two grid slots")

func test_barriers_block_cars_and_ai_laps_generated_track() -> void:
	var root := Node3D.new()
	tree.root.add_child(root)
	var scene := _generated_scene(11)
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "performance")
	b.build(scene)
	var barrier_id: String = scene.entities.filter(func(e): return e.type == "barrier")[0].id
	var bn := b.node_for(barrier_id)
	check(bn.get_node_or_null("BarrierMesh") != null and bn.get_node_or_null("BarrierCollision") != null, "guardrail mesh and collision built")
	await tree.physics_frame
	var road: Dictionary = scene.entities.filter(func(e): return e.type == "road")[0]
	var pts := ZinoTrackTools.world_centerline(road.road, Transform3D.IDENTITY)
	var dir := (pts[1] - pts[0]).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pts[0] + Vector3.UP * 0.5, pts[0] + Vector3.UP * 0.5 + right * 30.0)
	var hit := space.intersect_ray(q)
	check(not hit.is_empty(), "a ray across the road hits the guardrail")
	if not hit.is_empty():
		check_near(hit.position.distance_to(pts[0] + Vector3.UP * 0.5), 12.0 * 0.5 + 1.2 + 2.0, 1.5, "guardrail sits just outside the shoulder")
	var ctx := ZinoGameContext.new()
	tree.root.add_child(ctx)
	ctx.start(b, "res://", [], {"ai_count": 0, "save_key": "test", "start_race": false})
	var car := b.player_vehicle()
	car.input_enabled = false
	var d := ZinoAIDriver.new()
	ctx.add_child(d)
	d.setup(car, ctx.track_points(), true)
	ctx.race.start()
	var done := {"v": false}
	ctx.race.race_finished.connect(func(): done.v = true)
	var frames := 0
	while not done.v and frames < 120 * 120:
		await tree.physics_frame
		frames += 1
	var r = ctx.race.racers[0]
	print("    generated track lap: finished=%s in %.1f s, checkpoints %d" % [done.v, frames / 120.0, r.checkpoints_passed])
	check(done.v, "AI completed a lap of the generated circuit (with banking and guardrails)")
	ctx.stop()
	ctx.free()
	root.free()
