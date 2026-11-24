extends SceneTree
## Headless test runner:
##   Godot_console.exe --headless --path ZinoEditor -s res://tests/run_tests.gd [-- --filter=name]
## Exit code 0 = all passed, 1 = failures.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var files: Array[String] = []
	var d := DirAccess.open("res://tests")
	for f in d.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append("res://tests/" + f)
	files.sort()
	var total := 0
	var failed := 0
	var total_checks := 0
	var started := Time.get_ticks_msec()
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("LOAD FAIL  ", path)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if filter != "" and not (path.contains(filter) or mname.contains(filter)):
				continue
			var t: ZinoTest = script.new()
			t.tree = self
			total += 1
			var t0 := Time.get_ticks_msec()
			await t.call(mname)
			total_checks += t.checks
			var ms := Time.get_ticks_msec() - t0
			if t.checks == 0:
				t.failures.append("test made no checks (it probably hit a script error; see output above)")
			if t.failures.is_empty():
				print("PASS  %s::%s (%d checks, %d ms)" % [path.get_file(), mname, t.checks, ms])
			else:
				failed += 1
				print("FAIL  %s::%s" % [path.get_file(), mname])
				for f in t.failures:
					print("        - ", f)
	print("\n%d tests, %d failed, %d checks, %.1f s" % [total, failed, total_checks, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failed > 0 or total == 0 else 0)
