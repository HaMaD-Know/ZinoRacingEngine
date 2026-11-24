extends ZinoTest
## Imported car models: GLB export → asset import (no overwrite) → wheel detection → physics drive.

## Writes a simple car GLB (body + four named wheels) and returns its path.
static func make_car_glb(path: String) -> Error:
	var root := Node3D.new()
	root.name = "TestCar"
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.9, 0.7, 4.4)
	body.mesh = bm
	body.position = Vector3(0, 0.75, 0)
	root.add_child(body)
	body.owner = root
	for w in [["Wheel_FL", Vector3(-0.85, 0.36, -1.35)], ["Wheel_FR", Vector3(0.85, 0.36, -1.35)], ["Wheel_RL", Vector3(-0.85, 0.36, 1.35)], ["Wheel_RR", Vector3(0.85, 0.36, 1.35)]]:
		var mi := MeshInstance3D.new()
		mi.name = w[0]
		var cm := CylinderMesh.new()
		cm.top_radius = 0.36
		cm.bottom_radius = 0.36
		cm.height = 0.28
		mi.mesh = cm
		mi.rotation_degrees = Vector3(0, 0, 90)
		mi.position = w[1]
		root.add_child(mi)
		mi.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	root.free()
	return err

func test_import_detect_and_drive_model() -> void:
	var tmp := temp_dir("model")
	var glb := tmp.path_join("my car.glb")
	check_eq(make_car_glb(glb), OK, "test GLB written")
	var o := ZinoProjectService.default_options()
	o["name"] = "ModelGame"
	o["location"] = tmp
	var proj: String = ZinoProjectService.create_project(o).path
	var r1 := ZinoAssetImporter.import_file(proj, glb)
	check(r1.has("rel") and r1.rel == "Assets/Vehicles/my car.glb", "imported into Assets/Vehicles: %s" % str(r1))
	var r2 := ZinoAssetImporter.import_file(proj, glb)
	check(r2.has("rel") and r2.rel == "Assets/Vehicles/my car_2.glb", "second import does not overwrite (%s)" % str(r2.get("rel")))
	check(ZinoAssetImporter.read_index(proj).has(r1.rel), "import recorded in the asset index")
	check(not ZinoAssetImporter.import_file(proj, tmp.path_join("nope.exe")).has("rel"), "unsupported/missing file refused")

	ZinoModelLoader.project_root = proj
	ZinoModelLoader.clear_cache()
	var inst := ZinoModelLoader.instantiate(r1.rel)
	check(inst.has("node"), "runtime glTF load: %s" % str(inst.get("error", "")))
	if not inst.has("node"):
		return
	var found := ZinoModelLoader.detect_wheels(inst.node)
	check_eq(found.size(), 4, "four wheel meshes detected: %s" % str(found))
	inst.node.free()
	check(ZinoModelLoader.instantiate("../../evil.glb").has("error"), "paths outside the project refused")

	var scene := ZinoTemplates.racing_test_scene()
	for e in scene.entities:
		if e.type == "vehicle":
			e.vehicle.spec["model"] = {"path": r1.rel, "scale": 1.0, "offset": [0, -0.75, 0], "rotation": [0, 0, 0], "wheelNodes": found, "hideProceduralBody": true}
	var root := Node3D.new()
	tree.root.add_child(root)
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "performance")
	b.build(scene)
	var car := b.player_vehicle()
	check(car.get_node_or_null("Model") != null, "model attached to the vehicle")
	check(not (car.get_node("Body") as Node3D).visible, "procedural body hidden")
	var wheel_meshes := 0
	for w in car.wheels():
		if w.get_node_or_null("ModelWheel") != null:
			wheel_meshes += 1
	check_eq(wheel_meshes, 4, "model wheel meshes moved onto the physics wheels")
	car.input_enabled = false
	for i in 120:
		await tree.physics_frame
	car.throttle = 1.0
	for i in 240:
		await tree.physics_frame
	check(car.speed_kmh > 30.0, "imported car drives (%.1f km/h)" % car.speed_kmh)
	root.free()
	ZinoModelLoader.project_root = ""
	remove_dir_recursive(tmp)
