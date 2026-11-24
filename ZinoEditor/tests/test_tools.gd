extends ZinoTest
## Phase 9 tools: store planning/filtering, textured materials, HDRI sky, model props, engine audio
## synthesis, touch controls and HUD layouts.

func test_store_plan_and_filter() -> void:
	var tex_files := {"Diffuse": {"1k": {"jpg": {"url": "https://x/a_diff_1k.jpg", "md5": "1"}}},
		"nor_gl": {"1k": {"jpg": {"url": "https://x/a_nor_gl_1k.jpg", "md5": "2"}}}, "Rough": {"1k": {"jpg": {"url": "https://x/a_rough_1k.jpg", "md5": "3"}}}}
	var plan := ZinoStoreClient.plan_files("textures", "asphalt_02", tex_files, "1k")
	check_eq(plan.size(), 3, "three texture maps planned")
	check(plan.all(func(p): return p.rel.begins_with("Assets/Textures/asphalt_02/")), "textures go to Assets/Textures/<id>")
	check(ZinoStoreClient.plan_files("textures", "x", tex_files, "4k").is_empty(), "missing resolution yields no plan")
	var hdri := ZinoStoreClient.plan_files("hdris", "sky", {"hdri": {"1k": {"hdr": {"url": "https://x/sky_1k.hdr", "md5": ""}}}}, "1k")
	check(hdri.size() == 1 and hdri[0].rel == "Assets/Environment/sky_1k.hdr", "HDRI planned")
	var model := ZinoStoreClient.plan_files("models", "Barrel_01", {"gltf": {"1k": {"gltf": {"url": "https://x/Barrel_01_1k.gltf", "include": {"textures/b.jpg": {"url": "https://x/b.jpg"}, "../evil.bin": {"url": "https://x/e"}}}}}}, "1k")
	check_eq(model.size(), 2, "model + safe include planned, path traversal skipped")
	var items := [{"id": "a", "name": "Red Brick", "categories": ["brick", "wall"], "tags": ["red"], "downloads": 5},
		{"id": "b", "name": "Asphalt", "categories": ["road"], "tags": ["street"], "downloads": 9}]
	check_eq(ZinoStoreClient.filter(items, "street", "").size(), 1, "search by tag")
	check_eq(ZinoStoreClient.filter(items, "", "road").size(), 1, "filter by category")
	check(ZinoStoreClient.categories(items).has("brick"), "categories listed")

func test_textured_material_hdri_and_model_prop() -> void:
	var dir := temp_dir("tools")
	DirAccess.make_dir_recursive_absolute(dir.path_join("Assets/Textures/t"))
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.6, 0.3))
	img.save_png(dir.path_join("Assets/Textures/t/diff.png"))
	var hdr := Image.create(32, 16, false, Image.FORMAT_RGBF)
	hdr.fill(Color(0.5, 0.6, 0.9))
	hdr.save_exr(dir.path_join("Assets/Environment_sky.exr"))
	ZinoModelLoader.project_root = dir
	ZinoAssets.clear_cache()
	ZinoMaterials.clear_cache()
	var m := ZinoMaterials.get_material({"preset": "default", "color": [1, 1, 1, 1], "albedoTexture": "Assets/Textures/t/diff.png"})
	check(m.albedo_texture != null and m.albedo_texture.get_width() == 16, "material uses the project texture")
	check(ZinoAssets.load_texture("../outside.png") == null, "paths outside the project refused")
	var env := ZinoGraphics.build_environment({"skyHdri": "Assets/Environment_sky.exr"}, "performance")
	check(env.sky.sky_material is PanoramaSkyMaterial, "HDRI sky uses a panorama")
	var glb := dir.path_join("Assets/Environment/prop.glb")
	DirAccess.make_dir_recursive_absolute(glb.get_base_dir())
	preload("res://tests/test_vehicle_model.gd").make_car_glb(glb)
	var root := Node3D.new()
	tree.root.add_child(root)
	var scene := ZinoTemplates.empty()
	var prop := ZinoEntities.model("Assets/Environment/prop.glb", "Prop")
	scene.entities.append(prop)
	var b := ZinoSceneBuilder.new(root, ZinoSceneBuilder.MODE_PLAY, "performance")
	b.build(scene)
	var pn := b.node_for(prop.id)
	check(pn.get_node_or_null("ModelCollision") != null, "model prop has collision")
	await tree.physics_frame
	await tree.physics_frame
	var hit := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 10, 0), Vector3(0, 0.05, 0)))
	check(not hit.is_empty() and hit.position.y > 0.5, "the prop blocks a ray from above")
	root.free()
	ZinoModelLoader.project_root = ""
	ZinoAssets.clear_cache()
	ZinoMaterials.clear_cache()
	remove_dir_recursive(dir)

func test_engine_synthesis_touch_and_hud_layouts() -> void:
	var voice := {"phase": 0.0, "sub": 0.0, "noise": 0.0, "rpm": 3000.0}
	var quiet := ZinoAudio.render(voice, 3000.0, 0.0, 0.0, {}, 2048)
	var loud := ZinoAudio.render(voice, 3000.0, 1.0, 0.0, {}, 2048)
	check_eq(loud.size(), 2048, "rendered the requested frames")
	var e0 := 0.0
	var e1 := 0.0
	for i in 2048:
		e0 += absf(quiet[i].x)
		e1 += absf(loud[i].x)
	check(e1 > e0 * 1.5, "full throttle is louder than idle (%.1f vs %.1f)" % [e1, e0])
	check(Array(ZinoAudio.render(voice, 3000.0, 1.0, 0.0, {}, 64, false)).all(func(s): return absf(s.x) < 0.01), "engine off is silent")
	var tc := ZinoTouchControls.new()
	tc.always_visible = true
	tree.root.add_child(tc)
	var layout := ZinoTouchControls.default_layout()
	layout.accelerate.offset = [-300, -300]
	layout.nitro.visible = false
	tc.apply_layout(layout)
	check(tc.control_rect("accelerate").size.x > 50, "accelerate pedal placed")
	check(tc.control_rect("nitro").size == Vector2.ZERO, "hidden control not shown")
	tc.free()
	var hud := ZinoHud.new()
	tree.root.add_child(hud)
	hud.apply_layout({"timer": {"visible": false}, "laps": {"offset": [100, 100], "scale": 1.5}})
	check(not hud._panels.timer.visible, "HUD element hidden by layout")
	check_near(hud._panels.laps.scale.x, 1.5, 0.001, "HUD element scaled")
	hud.free()
