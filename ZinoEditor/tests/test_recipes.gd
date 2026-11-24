extends ZinoTest
## Block recipes: every recipe is a valid, compilable group of blocks that also fits into an existing program.

func test_every_recipe_compiles() -> void:
	check(ZinoBlockRecipes.RECIPES.size() >= 10, "%d recipes" % ZinoBlockRecipes.RECIPES.size())
	var ids := {}
	for r in ZinoBlockRecipes.RECIPES:
		check(not ids.has(r.id), "recipe id %s is unique" % r.id)
		ids[r.id] = true
		for d in r.n:
			check(not ZinoBlockLibrary.get_def(str(d[1])).is_empty(), "%s: block %s exists" % [r.id, d[1]])
		var built := ZinoBlockRecipes.build(r.id, Vector2(100, 200))
		check_eq(built.nodes.size(), r.n.size(), "%s builds every block" % r.id)
		var p := ZinoBlockCompiler.new_program(r.id)
		p.nodes = built.nodes
		p.links = built.links
		var c := ZinoBlockCompiler.compile(p)
		check(c.ok, "%s compiles: %s" % [r.id, str(c.errors)])
		if c.ok:
			check_eq(c.ir.scripts.size(), r.n.filter(func(d): return ZinoBlockLibrary.get_def(str(d[1])).kind == "event").size(), "%s: one script per event" % r.id)
		# Every link must land on a real input of the target block.
		var by_id := {}
		for n in built.nodes:
			by_id[n.id] = n
		for l in built.links:
			var target: Dictionary = by_id[l.to]
			check(l["in"] == "exec" or target["values"].has(l["in"]), "%s: %s has input %s" % [r.id, target.block, l["in"]])
	check(ZinoBlockRecipes.build("nope").is_empty(), "unknown recipe builds nothing")

func test_recipes_combine_with_the_starter_program() -> void:
	var p := ZinoBlockCompiler.starter_program()
	var before: int = ZinoBlockCompiler.compile(p).ir.scripts.size()
	var y := 1400.0
	for r in ZinoBlockRecipes.RECIPES:
		var built := ZinoBlockRecipes.build(r.id, Vector2(700, y))
		p.nodes.append_array(built.nodes)
		p.links.append_array(built.links)
		y += 600.0
	var c := ZinoBlockCompiler.compile(p)
	check(c.ok, "starter + all recipes compiles: %s" % str(c.errors))
	check(c.ir.scripts.size() > before + 9, "recipes add their scripts (%d)" % c.ir.scripts.size())
	check(ZinoBlockCompiler.to_script(p).contains("FINAL LAP"), "code view shows recipe blocks")

func test_recipe_runs_in_the_interpreter() -> void:
	var built := ZinoBlockRecipes.build("night_race")
	var p := ZinoBlockCompiler.new_program("night")
	p.nodes = built.nodes
	p.links = built.links
	var c := ZinoBlockCompiler.compile(p)
	check(c.ok, "night race compiles")
	var rt := ZinoBlockRuntime.new()
	tree.root.add_child(rt)
	rt.set_process(false)
	var ran: Array = []
	rt.trace_enabled = true
	rt.block_executed.connect(func(id): ran.append(id))
	rt.load_programs([c.ir])
	rt.fire("ev_game_start")
	for i in 3:
		rt.step_all()
	var time_node: String = built.nodes.filter(func(n): return n.block == "env_time")[0].id
	check(time_node in ran, "night race runs its time-of-day block (%s)" % str(ran))
	rt.queue_free()
