extends ZinoTest
## "Make a Game": every combination produces a valid, playable project.

func test_every_game_type_creates_a_playable_project() -> void:
	var dir := temp_dir("quick")
	for gt in ZinoQuickGame.GAME_TYPES:
		var c := ZinoQuickGame.default_choices()
		c.gameType = gt.id
		c.location = dir
		c.name = "Quick " + gt.id
		c.track = "oval" if ZinoQuickGame.uses_track(gt.id) else "classic"
		c.world = "night"
		c.opponents = 4
		c.difficulty = "hard"
		var r := ZinoQuickGame.create(c)
		check(r.ok, "%s created: %s" % [gt.id, r.error])
		if not r.ok:
			continue
		var op := ZinoProjectService.open_project(r.path)
		check(op.ok and op.warnings.is_empty(), "%s opens cleanly" % gt.id)
		var scene: Dictionary = ZinoFormat.load_scene_file(r.path.path_join("Scenes/Main.zscene")).scene
		check(ZinoFormat.validate_scene(scene).is_empty(), "%s scene valid" % gt.id)
		check_eq(scene.entities.filter(func(e): return e.type == "vehicle").size(), 1, "%s has the player car" % gt.id)
		check_near(float(scene.settings.timeOfDay), 23.0, 0.01, "%s night chosen" % gt.id)
		check(op.manifest.get("coach", {}).get("enabled", false), "%s starts with the coach" % gt.id)
		if gt.id == "timeTrial":
			check_eq(int(scene.settings.race.aiOpponents), 0, "time trial has no opponents")
		elif gt.id == "drag":
			check_eq(scene.settings.race.mode, "sprint", "drag is a sprint")
		elif gt.id != "openWorld":
			check_eq(int(scene.settings.race.aiOpponents), 4, "%s opponents applied" % gt.id)
			check_eq(scene.entities.filter(func(e): return e.type == "barrier").size(), 1, "%s generated track has guardrails" % gt.id)
	remove_dir_recursive(dir)

func test_quick_game_actually_races() -> void:
	var c := ZinoQuickGame.default_choices()
	c.track = "technical"
	c.opponents = 2
	c.laps = 1
	var scene := ZinoTemplates.racing_test_scene()
	ZinoQuickGame.apply(scene, c)
	scene.settings.race.countdown = 0.0
	var root := Node3D.new()
	tree.root.add_child(root)
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "performance")
	b.build(scene)
	var ctx := ZinoGameContext.new()
	tree.root.add_child(ctx)
	ctx.start(b, "res://", [], {"save_key": "test"})
	check_eq(ctx.ai_vehicles.size(), 2, "two opponents on the grid")
	var player := b.player_vehicle()
	player.input_enabled = false
	for i in 240:
		await tree.physics_frame
	check(player.grounded_wheels() >= 3, "player car sits on the generated track")
	var start: Vector3 = ctx.ai_vehicles[0].global_position
	for i in 480:
		await tree.physics_frame
	check(ctx.race.state == "racing" and ctx.ai_vehicles[0].global_position.distance_to(start) > 30.0, "opponents are racing")
	ctx.stop()
	ctx.free()
	root.free()
