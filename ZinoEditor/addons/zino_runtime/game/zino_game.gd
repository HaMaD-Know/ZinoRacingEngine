extends Node3D
## Runtime entry point for games made with Zino (the exported game's main scene).
## Loads project.zino, builds the start scene with the same ZinoSceneBuilder the editor uses,
## and hands control to the player vehicle.

var builder: ZinoSceneBuilder
var context: ZinoGameContext

func _ready() -> void:
	ZinoInput.ensure_actions()
	var manifest_r := ZinoFormat.read_json_file("res://project.zino")
	if not manifest_r.ok:
		_fatal("Cannot read project.zino: " + manifest_r.error)
		return
	var manifest: Dictionary = manifest_r.data
	var start: String = manifest.get("startScene", "Scenes/Main.zscene")
	var preset: String = manifest.get("graphics", {}).get("gameOutput", ZinoGraphics.DEFAULT_PRESET)
	var r := ZinoFormat.load_scene_file("res://" + start)
	if not r.ok:
		_fatal("Cannot load %s: %s" % [start, r.error])
		return
	ZinoGraphics.apply_viewport(get_viewport(), preset)
	for w in ZinoGraphics.capability_warnings(preset):
		push_warning("Zino graphics: " + w)
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	builder = ZinoSceneBuilder.new(world, ZinoSceneBuilder.MODE_PLAY, preset)
	builder.build(r.scene)
	var cam := builder.play_camera()
	if cam:
		cam.current = true
	var progs := ZinoBlockCompiler.load_project_programs("res://", manifest)
	for e in progs.errors:
		push_error("Zino blocks: " + e)
	context = ZinoGameContext.new()
	add_child(context)
	context.start(builder, "res://", progs.irs, {"save_key": str(manifest.get("project", {}).get("name", "game"))})
	context.quit_requested.connect(func(): get_tree().quit())

func _fatal(message: String) -> void:
	push_error("Zino: " + message)
	var l := Label.new()
	l.text = "Zino could not start the game:\n" + message
	l.position = Vector2(40, 40)
	var layer := CanvasLayer.new()
	layer.add_child(l)
	add_child(layer)
