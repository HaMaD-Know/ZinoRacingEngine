class_name ZinoAssetStore
extends HSplitContainer
## Asset Store: browse and download free CC0 assets (Poly Haven textures, HDRIs and models) and
## apply Zino built-in content. With a project open, downloads go into its Assets/ folder and can be
## applied directly (material maps, HDRI sky, model props). From the Home screen it browses only.

var session: ZinoEditorSession = null      # null on the Home screen
var client: ZinoStoreClient
var kind := "builtin"
var _items := {}                           # kind -> Array
var _grid: GridContainer
var _search: LineEdit
var _cat: OptionButton
var _res := "1k"
var _status: Label
var _detail: VBoxContainer
var _thumbs := {}                          # id -> TextureRect (cards)
var _thumb_cache := {}                     # id -> Texture2D
var _selected: Dictionary = {}
var _shown := 60
var _kind_buttons := {}
var _downloaded := {}                      # id -> result

func setup(s) -> void:
	session = s
	client = ZinoStoreClient.new()
	add_child(client)
	client.catalog_loaded.connect(_on_catalog)
	client.catalog_failed.connect(func(k, msg): if k == kind: _status.text = "Could not load the catalogue: " + msg)
	client.thumbnail_ready.connect(_on_thumb)
	client.download_progress.connect(func(id, d, t): _status.text = "Downloading %s… %d/%d files" % [id, d, t])
	client.download_finished.connect(_on_downloaded)
	var main := ZinoUI.vbox(8)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(main)
	var bar := ZinoUI.hbox(6)
	for k in [["builtin", "Zino Built-in"], ["textures", "Textures"], ["hdris", "HDRI Skies"], ["models", "Models"]]:
		var b := ZinoUI.toggle(k[1], k[0] == kind, func(_on): set_kind(k[0]))
		_kind_buttons[k[0]] = b
		bar.add_child(b)
	bar.add_child(VSeparator.new())
	_search = LineEdit.new()
	_search.placeholder_text = "Search assets…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _shown = 60; _refresh())
	bar.add_child(_search)
	_cat = OptionButton.new()
	_cat.custom_minimum_size.x = 150
	_cat.item_selected.connect(func(_i): _shown = 60; _refresh())
	bar.add_child(_cat)
	var res_opt := ZinoUI.option([["1k", "1K"], ["2k", "2K"], ["4k", "4K"]], _res, func(r): _res = r)
	res_opt.size_flags_horizontal = Control.SIZE_SHRINK_END
	res_opt.custom_minimum_size.x = 80
	bar.add_child(res_opt)
	main.add_child(bar)
	_status = ZinoUI.dim("", 12)
	main.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	main.add_child(scroll)
	var right := PanelContainer.new()
	right.custom_minimum_size.x = 320
	right.add_theme_stylebox_override("panel", ZinoTheme.box(ZinoTheme.BG_2, 10, Color.TRANSPARENT, 0, 14))
	_detail = ZinoUI.vbox(8)
	right.add_child(_detail)
	add_child(right)
	set_kind("builtin")

func set_kind(k: String) -> void:
	kind = k
	for key in _kind_buttons:
		_kind_buttons[key].set_pressed_no_signal(key == k)
	_selected = {}
	_shown = 60
	_show_detail()
	if k == "builtin":
		_status.text = "Built into Zino — works offline."
		_refresh()
		return
	if _items.has(k):
		_refresh()
	else:
		_status.text = "Loading the %s catalogue from Poly Haven (CC0)…" % ZinoStoreClient.KINDS[k]
		_clear_grid()
		client.load_catalog(k)

func _on_catalog(k: String, items: Array) -> void:
	_items[k] = items
	if k == kind:
		_cat.clear()
		_cat.add_item("All categories")
		_cat.set_item_metadata(0, "")
		for c in ZinoStoreClient.categories(items):
			_cat.add_item(str(c).capitalize())
			_cat.set_item_metadata(_cat.item_count - 1, c)
		_refresh()

func visible_items() -> Array:
	if kind == "builtin":
		return _builtin().filter(func(b): return _search.text.strip_edges() == "" or str(b.name).to_lower().contains(_search.text.strip_edges().to_lower()))
	var cat: String = _cat.get_item_metadata(_cat.selected) if _cat.item_count > 0 and _cat.selected >= 0 else ""
	return ZinoStoreClient.filter(_items.get(kind, []), _search.text, cat)

func _clear_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_thumbs.clear()

func _refresh() -> void:
	_clear_grid()
	var items := visible_items()
	if kind != "builtin":
		_status.text = "%d assets · free CC0 licence from polyhaven.com%s" % [items.size(), "" if session else " · open a project to download"]
	for it in items.slice(0, _shown):
		_grid.add_child(_card(it))
	if items.size() > _shown:
		_grid.add_child(ZinoUI.button("Show more (%d)" % (items.size() - _shown), func():
			_shown += 60
			_refresh()))

func _card(it: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 200)
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", ZinoTheme.box(ZinoTheme.PANEL, 10, ZinoTheme.BORDER, 1, 8))
	b.add_theme_stylebox_override("hover", ZinoTheme.box(ZinoTheme.PANEL, 10, ZinoTheme.ACCENT, 2, 8))
	var v := ZinoUI.vbox(4)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8; v.offset_top = 8; v.offset_right = -8; v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(154, 140)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tr)
	if it.has("swatch"):
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(it.swatch)
		tr.texture = ImageTexture.create_from_image(img)
	elif _thumb_cache.has(it.id):
		tr.texture = _thumb_cache[it.id]
	else:
		_thumbs[it.id] = tr
		client.request_thumbnail(it.id)
	var name_l := ZinoUI.label(str(it.name), 13, ZinoTheme.TEXT)
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var sub := ZinoUI.dim(str(it.get("subtitle", ", ".join(it.get("authors", [])))), 11)
	sub.clip_text = true
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sub)
	b.add_child(v)
	b.pressed.connect(func():
		_selected = it
		_show_detail())
	return b

func _on_thumb(id: String, tex: Texture2D) -> void:
	_thumb_cache[id] = tex
	if _thumbs.has(id) and is_instance_valid(_thumbs[id]):
		_thumbs[id].texture = tex
	if _selected.get("id") == id:
		_show_detail()

func _show_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _selected.is_empty():
		_detail.add_child(ZinoUI.heading("Asset Store", 18))
		_detail.add_child(ZinoUI.dim("Pick an asset to see details. Poly Haven assets are CC0: free for any use, no attribution required (Zino records the author anyway).", 12))
		return
	var it := _selected
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(290, 200)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture = _thumb_cache.get(it.get("id", ""))
	_detail.add_child(tr)
	_detail.add_child(ZinoUI.heading(str(it.name), 18))
	if it.has("description"):
		var d := ZinoUI.dim(str(it.description), 12)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(d)
	if it.has("action"):
		var btn := ZinoUI.accent_button("  Apply  ", func(): _apply_builtin(it))
		btn.disabled = session == null
		_detail.add_child(btn)
		if session == null:
			_detail.add_child(ZinoUI.dim("Open a project to use built-in content.", 11))
		return
	_detail.add_child(ZinoUI.dim("By %s · %d downloads" % [", ".join(it.authors), it.downloads], 12))
	_detail.add_child(ZinoUI.dim("Categories: " + ", ".join(it.categories), 11))
	_detail.add_child(ZinoUI.pill("CC0 · Public domain", ZinoTheme.OK))
	if session == null:
		_detail.add_child(ZinoUI.dim("Open a project to download this asset into it.", 12))
		return
	var res: Dictionary = _downloaded.get(it.id, {})
	if res.is_empty():
		_detail.add_child(ZinoUI.accent_button("  Download (%s)  " % _res.to_upper(), func():
			_status.text = "Preparing %s…" % it.id
			client.download(it, session.project_dir, _res)))
	else:
		_detail.add_child(ZinoUI.label("✓ In your project: " + str(res.main), 12, ZinoTheme.OK))
		match it.kind:
			"textures": _detail.add_child(ZinoUI.button("Apply to selected objects", func(): apply_texture(res.maps)))
			"hdris": _detail.add_child(ZinoUI.button("Use as sky", func(): use_hdri(res.main)))
			"models": _detail.add_child(ZinoUI.button("Place in scene", func(): place_model(res.main, it.name)))

func _on_downloaded(id: String, result: Dictionary) -> void:
	if not result.ok:
		_status.text = "Download failed: " + str(result.error)
		ZinoAppLog.error("Store", "%s: %s" % [id, result.error])
		return
	_downloaded[id] = result
	_status.text = "Downloaded %s (%d files) into Assets/" % [id, result.files.size()]
	ZinoAppLog.info("Store", "Downloaded %s → %s" % [id, result.main])
	if _selected.get("id") == id:
		_show_detail()

# --- Applying content (undoable scene commands) --------------------------------------------------

func apply_texture(maps: Dictionary) -> int:
	var ids: Array = session.selection.filter(func(id): return ZinoFormat.find_entity(session.scene(), id).get("type") == ZinoEntities.TYPE_PRIMITIVE)
	if ids.is_empty():
		ZinoAppLog.warn("Store", "Select one or more objects (cubes, planes, …) to apply the material.")
		return 0
	session.execute(ZinoSceneEdits.modify(session.scene(), ids, func(e):
		var m: Dictionary = e.mesh.get("material", {})
		m["albedoTexture"] = maps.get("diff", "")
		m["normalTexture"] = maps.get("nor_gl", "")
		m["roughnessTexture"] = maps.get("rough", "")
		m["preset"] = "default"
		m["color"] = [1, 1, 1, 1]
		e.mesh["material"] = m, "Apply Store Material"))
	ZinoMaterials.clear_cache()
	return ids.size()

func use_hdri(rel: String) -> void:
	var st: Dictionary = session.scene().settings.duplicate(true)
	st["skyHdri"] = rel
	session.execute(ZinoSceneEdits.settings(session.scene(), st, "HDRI Sky"))

func place_model(rel: String, model_name: String) -> void:
	var e := ZinoEntities.model(rel, model_name)
	var p: Vector3 = session.placement_provider.call()
	ZinoEntities.set_pos(e, p)
	session.execute(ZinoSceneEdits.create(session.scene(), [e], "Place Model"))
	session.select([e.id])

func _builtin() -> Array:
	var out: Array = []
	var swatches := {"asphalt": Color(0.15, 0.15, 0.16), "concrete": Color(0.55, 0.55, 0.53), "grass": Color(0.3, 0.5, 0.2), "dirt": Color(0.42, 0.33, 0.24), "gravel": Color(0.5, 0.48, 0.45), "carPaint": Color(0.75, 0.05, 0.04), "metal": Color(0.8, 0.8, 0.82), "rubber": Color(0.06, 0.06, 0.07), "glass": Color(0.5, 0.6, 0.7), "default": Color(0.8, 0.8, 0.8)}
	for p in ZinoEntities.MATERIAL_PRESETS:
		out.append({"id": "mat_" + p, "name": p.capitalize() + " material", "subtitle": "Material preset", "swatch": swatches.get(p, Color.GRAY), "action": "material", "value": p, "description": "Applies the procedural %s PBR preset to the selected objects." % p})
	for p in ZinoEntities.PROFILES:
		out.append({"id": "veh_" + p, "name": p.capitalize() + " car", "subtitle": "Vehicle", "swatch": Color(0.04, 0.52, 1.0), "action": "vehicle", "value": p, "description": "Adds a car tuned with the %s physics profile." % p})
	for t in [["Speedway oval", {"seed": 4, "corners": 6, "irregularity": 0.05, "radius": 120}], ["Technical circuit", {"seed": 21, "corners": 16, "irregularity": 0.5, "radius": 90}], ["Hill circuit", {"seed": 33, "corners": 12, "irregularity": 0.35, "radius": 110, "elevation": 18, "banking": 6}]]:
		out.append({"id": "trk_" + t[0], "name": t[0], "subtitle": "Track", "swatch": Color(0.35, 0.35, 0.38), "action": "track", "value": t[1], "description": "Generates a complete circuit with checkpoints, grid and guardrails."})
	for e in [["day", "Clear day", 14.0, "clear"], ["sunset", "Golden sunset", 19.3, "clear"], ["night", "Night race", 23.0, "clear"], ["storm", "Storm", 16.0, "storm"], ["rain", "Wet race", 13.0, "rain"]]:
		out.append({"id": "env_" + e[0], "name": e[1], "subtitle": "Environment", "swatch": Color(0.4, 0.6, 0.9) if e[0] == "day" else Color(0.9, 0.55, 0.3) if e[0] == "sunset" else Color(0.1, 0.12, 0.2), "action": "environment", "value": {"timeOfDay": e[2], "weather": e[3]}, "description": "Sets time of day and weather for the scene."})
	return out

func _apply_builtin(it: Dictionary) -> void:
	match it.action:
		"material":
			var ids: Array = session.selection.filter(func(id): return ZinoFormat.find_entity(session.scene(), id).get("type") == ZinoEntities.TYPE_PRIMITIVE)
			session.execute(ZinoSceneEdits.modify(session.scene(), ids, func(e): e.mesh.material["preset"] = it.value, "Material Preset"))
		"vehicle":
			var v := ZinoEntities.vehicle(it.name, it.value)
			var p: Vector3 = session.placement_provider.call()
			var y := ZinoFormat.v3(v.transform.position).y
			ZinoEntities.set_pos(v, Vector3(p.x, y + 0.1, p.z))
			session.execute(ZinoSceneEdits.create(session.scene(), [v], "Add " + str(it.name)))
		"track":
			var params: Dictionary = {"width": 12.0, "elevation": 0.0, "banking": 3.0}
			params.merge(it.value, true)
			var ents := ZinoTrackTools.generate_circuit(params)
			ents.append_array(ZinoTrackTools.checkpoints(ents[0].road, Transform3D.IDENTITY, 4))
			ents.append_array(ZinoTrackTools.grid(ents[0].road, Transform3D.IDENTITY, 6))
			ents.append(ZinoTrackTools.barrier(ents[0].id, "both", "guardrail"))
			session.execute(ZinoSceneEdits.create(session.scene(), ents, "Add " + str(it.name)))
		"environment":
			var st: Dictionary = session.scene().settings.duplicate(true)
			st.merge(it.value, true)
			session.execute(ZinoSceneEdits.settings(session.scene(), st, it.name))
	ZinoAppLog.info("Store", "Applied " + str(it.name))
