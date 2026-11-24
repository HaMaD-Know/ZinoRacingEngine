extends SceneTree
## Creates the sample projects shipped with a release:
##   godot --headless --path ZinoEditor -s res://tools/make_samples.gd -- <output dir>
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	for s in [["Sample Circuit Race", "circuit", "day"], ["Sample Drift Sunset", "drift", "sunset"], ["Sample Open World", "openWorld", "day"], ["Sample Kart Cup", "kart", "day"]]:
		var o := ZinoProjectService.default_options()
		o.name = s[0]
		o.location = out
		o.template = s[1]
		o.environment = s[2]
		var r := ZinoProjectService.create_project(o)
		print("%s: %s" % [s[0], "ok" if r.ok else r.error])
	quit()
