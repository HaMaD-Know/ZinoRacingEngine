extends SceneTree
## Measures average FPS of the racing test scene for every graphics preset on this machine.
##   Godot.exe --path ZinoEditor -s res://tools/benchmark_presets.gd [-- --seconds=4]
## Prints one line per preset and writes user://benchmark.json.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var seconds := 4.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			seconds = float(a.substr(10))
	root.size = Vector2i(1600, 900)
	var results := {}
	for preset in ZinoGraphics.ORDER:
		var world := Node3D.new()
		root.add_child(world)
		var b := ZinoSceneBuilder.new(world, ZinoSceneBuilder.MODE_PLAY, preset)
		b.build(ZinoTemplates.racing_test_scene())
		ZinoGraphics.apply_viewport(root, preset)
		var cam := b.play_camera()
		if cam:
			cam.current = true
		var car := b.player_vehicle()
		car.input_enabled = false
		car.throttle = 0.6
		for i in 30:
			await process_frame   # warm-up (shader compilation, SDFGI first bounce)
		var frames := 0
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < int(seconds * 1000000.0):
			await process_frame
			frames += 1
		var fps := frames / ((Time.get_ticks_usec() - t0) / 1000000.0)
		results[preset] = snappedf(fps, 0.1)
		print("%-12s %6.1f FPS  (1600x900, %s)" % [ZinoGraphics.label(preset), fps, RenderingServer.get_video_adapter_name()])
		world.free()
		await process_frame
	var f := FileAccess.open("user://benchmark.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "resolution": "1600x900", "fps": results}, "\t"))
	quit()
