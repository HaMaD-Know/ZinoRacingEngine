extends SceneTree
## Packs the engine add-ons into res://engine_addons.zip before the iPhone/iPad export, so the app can
## copy them into new game projects (an iOS app has no engine folder beside it).
## godot --headless --path ZinoEditor -s res://tools/pack_engine_addons.gd

func _init() -> void:
	var out := ProjectSettings.globalize_path(ZinoProjectService.BUNDLED_ADDONS)
	var err := ZinoProjectService.pack_engine_addons(out)
	print("engine_addons.zip: %s (%d bytes)" % ["ok" if err == OK else "error %d" % err, FileAccess.get_file_as_bytes(out).size()])
	quit(0 if err == OK else 1)
