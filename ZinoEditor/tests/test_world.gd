extends ZinoTest

func test_open_world_builds_and_is_drivable() -> void:
	var scene := ZinoTemplates.open_world()
	check(ZinoFormat.validate_scene(scene).is_empty(), "open world scene valid")
	var root := Node3D.new()
	tree.root.add_child(root)
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "performance")
	var t0 := Time.get_ticks_msec()
	b.build(scene)
	print("    open world build: %d ms" % (Time.get_ticks_msec() - t0))
	var terrain_e: Dictionary = scene.entities.filter(func(e): return e.type == "terrain")[0]
	var tn := b.node_for(terrain_e.id)
	var chunks := tn.get_children().filter(func(c): return str(c.name).begins_with("TerrainChunk"))
	check_eq(chunks.size(), ZinoWorld.CHUNKS * ZinoWorld.CHUNKS, "terrain split into streamable chunks")
	check(chunks.all(func(c): return c.visibility_range_end > 0.0), "chunks have streaming distances")
	check(tn.get_node_or_null("TerrainCollision") != null, "heightmap collision")
	var veg_e: Dictionary = scene.entities.filter(func(e): return e.type == "vegetation")[0]
	var counts: Dictionary = b.node_for(veg_e.id).get_meta("counts")
	print("    vegetation: ", counts)
	check(counts.get("trees", 0) > 300 and counts.get("grass", 0) > 500, "vegetation scattered")
	check_eq(scene.entities.filter(func(e): return e.type == "building").size(), 6, "six buildings")
	check(b.node_for(scene.entities.filter(func(e): return e.type == "water")[0].id).get_node_or_null("WaterSurface") != null, "water surface")
	# Roads are flattened into the terrain.
	var road: Dictionary = scene.entities.filter(func(e): return e.type == "road")[0]
	var pts := ZinoTrackTools.world_centerline(road.road, ZinoFormat.transform_from_entity(road))
	var worst := 0.0
	for i in range(5, pts.size() - 5, 7):
		worst = maxf(worst, absf(b.terrain_height(pts[i].x, pts[i].z) - (pts[i].y - 0.15)))
	check(worst < 0.6, "terrain meets the road surface (worst gap %.2f m)" % worst)
	# Trees keep clear of roads.
	# Tree collision shapes mirror the tree positions (MultiMesh data is not readable with the headless renderer).
	var trees: Array = b.node_for(veg_e.id).get_node("TreeCollision").get_children()
	check_eq(trees.size(), counts.trees, "every tree has collision")
	var too_close := 0
	for c in trees:
		var p: Vector3 = c.global_position
		for q in pts:
			if Vector2(p.x - q.x, p.z - q.z).length() < float(road.road.width) * 0.5:
				too_close += 1
				break
	check_eq(too_close, 0, "no tree stands on the highway")
	# The car lands on the road.
	var car := b.player_vehicle()
	car.input_enabled = false
	for i in 240:
		await tree.physics_frame
	check_eq(car.grounded_wheels(), 4, "car resting on the highway")
	check(car.global_position.y > 1.5, "car did not fall through the world (y %.2f)" % car.global_position.y)
	# Traffic.
	var ctx := ZinoGameContext.new()
	tree.root.add_child(ctx)
	ctx.start(b, "res://", [], {"save_key": "test"})
	check_eq(ctx.traffic.size(), 6, "six traffic cars")
	var start: Array = ctx.traffic.map(func(v): return v.global_position)
	for i in 600:
		await tree.physics_frame
	var moved := 0
	for k in ctx.traffic.size():
		if ctx.traffic[k].global_position.distance_to(start[k]) > 20.0:
			moved += 1
	check(moved >= 5, "traffic is driving (%d/6 moved > 20 m in 5 s)" % moved)
	ctx.stop()
	ctx.free()
	root.free()

func test_sculpted_heights_round_trip() -> void:
	var t := ZinoWorld.default_terrain()
	t.resolution = 33
	var h := ZinoWorld.terrain_heights(t)
	h[16 * 33 + 16] += 25.0
	t.heights = ZinoWorld.encode_heights(h)
	var h2 := ZinoWorld.terrain_heights(t)
	check_eq(h2.size(), 33 * 33, "decoded size")
	check_near(h2[16 * 33 + 16], h[16 * 33 + 16], 0.001, "sculpted height preserved")
	check_near(ZinoWorld.sample(h2, 33, float(t.size), 0.0, 0.0), h[16 * 33 + 16], 0.01, "sampling at the centre returns the sculpted peak")
	var tunnel := ZinoTrackTools.barrier("e_x", "both", "tunnel")
	check_eq(tunnel.barrier.style, "tunnel", "tunnel barrier style")
