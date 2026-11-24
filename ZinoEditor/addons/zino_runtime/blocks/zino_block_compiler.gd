@tool
class_name ZinoBlockCompiler
extends RefCounted
## Turns a block graph (*.zblocks) into a validated, typed intermediate representation (IR)
## that ZinoBlockRuntime executes, and renders readable Zino Script pseudocode for the code view.
##
## Graph format:
##   {format:"zino-blocks", formatVersion:1, name, variables:[{name, value}],
##    nodes:[{id, block, pos:[x,y], values:{input: literal}}],
##    links:[{from, out, to, in}]}      exec links: out = next/then/else/body, in = "exec"
##                                      value links: out = "value", in = <input name>
## IR:
##   {scripts:[{event, params, body:[stmt]}], functions:{name:{params, body}}, variables:{name: value}}
##   stmt: {op:"block", block, args:{name: expr}, node} | {op:"if", cond, then, else, node}
##         {op:"loop", kind, args, body, node} | {op:"break"} | {op:"stop"} | {op:"return", value}
##   expr: {k:"lit", v} | {k:"block", block, args:{}, node}

const FORMAT := "zino-blocks"
const FORMAT_VERSION := 1
const MAX_NODES := 5000

static func new_program(program_name: String = "Game Logic") -> Dictionary:
	return {"format": FORMAT, "formatVersion": FORMAT_VERSION, "name": program_name, "variables": [], "nodes": [], "links": []}

## The block program every new project starts with: race messages, final-lap warning,
## best-lap saving and results — a working example of events, conditions, variables and data.
static func starter_program() -> Dictionary:
	var p := new_program("Game Logic")
	p.variables = [{"name": "best", "value": 0}]
	var n: Array = []
	var L: Array = []
	var start := node("ev_race_start", Vector2(0, 0)); n.append(start)
	var msg := node("ui_message", Vector2(320, 0), {"text": "GO! GO! GO!", "seconds": 1.5}); n.append(msg)
	L.append(link(start.id, "next", msg.id))
	var lap := node("ev_lap", Vector2(0, 220)); n.append(lap)
	var cond := node("ctl_if", Vector2(320, 220)); n.append(cond)
	var cmp := node("log_compare", Vector2(0, 360), {"op": "="}); n.append(cmp)
	var cur := node("race_lap", Vector2(-320, 360)); n.append(cur)
	var tot := node("race_total_laps", Vector2(-320, 460)); n.append(tot)
	var big := node("ui_big", Vector2(640, 220), {"text": "FINAL LAP", "seconds": 2.5}); n.append(big)
	L.append(link(lap.id, "next", cond.id))
	L.append(link(cur.id, "value", cmp.id, "a"))
	L.append(link(tot.id, "value", cmp.id, "b"))
	L.append(link(cmp.id, "value", cond.id, "condition"))
	L.append(link(cond.id, "then", big.id))
	var fin := node("ev_race_finish", Vector2(0, 640)); n.append(fin)
	var load := node("data_load", Vector2(-320, 780), {"key": "best lap", "default": 0}); n.append(load)
	var setb := node("var_set", Vector2(320, 640), {"var": "best"}); n.append(setb)
	var mylap := node("race_best_lap", Vector2(-320, 900)); n.append(mylap)
	var better := node("log_compare", Vector2(0, 900), {"op": "<"}); n.append(better)
	var none := node("log_compare", Vector2(0, 1020), {"op": "=", "b": 0}); n.append(none)
	var best_get := node("var_get", Vector2(-320, 1020), {"var": "best"}); n.append(best_get)
	var best_get2 := node("var_get", Vector2(-320, 1120), {"var": "best"}); n.append(best_get2)
	var either := node("log_or", Vector2(320, 960)); n.append(either)
	var cond2 := node("ctl_if", Vector2(640, 640)); n.append(cond2)
	var save := node("data_save", Vector2(960, 640), {"key": "best lap"}); n.append(save)
	var mylap2 := node("race_best_lap", Vector2(640, 860)); n.append(mylap2)
	var rec := node("ui_message", Vector2(1280, 640), {"text": "New best lap!", "seconds": 3.0}); n.append(rec)
	var res := node("ui_results", Vector2(960, 780)); n.append(res)
	L.append(link(fin.id, "next", setb.id))
	L.append(link(load.id, "value", setb.id, "value"))
	L.append(link(setb.id, "next", cond2.id))
	L.append(link(mylap.id, "value", better.id, "a"))
	L.append(link(best_get.id, "value", better.id, "b"))
	L.append(link(best_get2.id, "value", none.id, "a"))
	L.append(link(better.id, "value", either.id, "a"))
	L.append(link(none.id, "value", either.id, "b"))
	L.append(link(either.id, "value", cond2.id, "condition"))
	L.append(link(cond2.id, "then", save.id))
	L.append(link(mylap2.id, "value", save.id, "value"))
	L.append(link(save.id, "next", rec.id))
	L.append(link(cond2.id, "next", res.id))
	p.nodes = n
	p.links = L
	return p

## Loads and compiles every program listed in a project. Returns {irs:[], errors:[text]}.
static func load_project_programs(project_root: String, manifest: Dictionary) -> Dictionary:
	var irs: Array = []
	var errors: Array = []
	for rel in manifest.get("blockScripts", []):
		var r := ZinoFormat.read_json_file(project_root.path_join(str(rel)))
		if not r.ok:
			errors.append("%s: %s" % [rel, r.error])
			continue
		var c := compile(r.data)
		if not c.ok:
			for e in c.errors:
				errors.append("%s: %s" % [rel, e.message])
			continue
		irs.append(c.ir)
	return {"irs": irs, "errors": errors}

static func node(block: String, pos: Vector2 = Vector2.ZERO, values: Dictionary = {}) -> Dictionary:
	var d := ZinoBlockLibrary.get_def(block)
	var vals := {}
	for inp in d.get("inputs", []):
		vals[inp[0]] = values.get(inp[0], inp[2])
	return {"id": "n_" + ZinoFormat.new_id().substr(2), "block": block, "pos": [pos.x, pos.y], "values": vals}

static func link(from_id: String, out: String, to_id: String, to_in: String = "exec") -> Dictionary:
	return {"from": from_id, "out": out, "to": to_id, "in": to_in}

## Compiles a program. Returns {ok, ir, errors:[{node, message}], warnings:[{node, message}]}.
static func compile(program: Dictionary) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	if program.get("format") != FORMAT:
		return {"ok": false, "ir": {}, "errors": [{"node": "", "message": "not a Zino block program"}], "warnings": []}
	if int(program.get("formatVersion", 0)) > FORMAT_VERSION:
		return {"ok": false, "ir": {}, "errors": [{"node": "", "message": "block program format is newer than this Zino"}], "warnings": []}
	var nodes := {}
	for n in program.get("nodes", []):
		if not (n is Dictionary) or not ZinoFormat.is_valid_id(n.get("id")):
			errors.append({"node": "", "message": "a block has an invalid id"})
			continue
		if nodes.has(n["id"]):
			errors.append({"node": n["id"], "message": "duplicate block id"})
			continue
		if not ZinoBlockLibrary.has(str(n.get("block", ""))):
			errors.append({"node": n["id"], "message": "unknown block '%s'" % str(n.get("block"))})
			continue
		nodes[n["id"]] = n
	if nodes.size() > MAX_NODES:
		errors.append({"node": "", "message": "program has more than %d blocks" % MAX_NODES})
	# Index links.
	var exec_next := {}     # "from|out" -> to node id
	var value_in := {}      # "to|in" -> from node id
	var incoming_exec := {}
	for l in program.get("links", []):
		if not (l is Dictionary) or not nodes.has(l.get("from")) or not nodes.has(l.get("to")):
			errors.append({"node": str(l.get("to", "")) if l is Dictionary else "", "message": "a connection points to a missing block"})
			continue
		var fdef := ZinoBlockLibrary.get_def(nodes[l.from].block)
		var tdef := ZinoBlockLibrary.get_def(nodes[l.to].block)
		if l.get("in") == "exec":
			if not l.get("out") in ZinoBlockLibrary.exec_outputs(fdef.id) or not ZinoBlockLibrary.has_exec_input(tdef.id):
				errors.append({"node": l.to, "message": "invalid flow connection from '%s'" % fdef.label})
				continue
			var key: String = l.from + "|" + str(l.out)
			if exec_next.has(key):
				errors.append({"node": l.from, "message": "output '%s' is connected twice" % l.out})
				continue
			exec_next[key] = l.to
			incoming_exec[l.to] = true
		else:
			if fdef.kind != "value":
				errors.append({"node": l.to, "message": "'%s' does not produce a value" % fdef.label})
				continue
			var inp := _input_def(tdef, str(l.get("in")))
			if inp.is_empty():
				errors.append({"node": l.to, "message": "'%s' has no input '%s'" % [tdef.label, l.get("in")]})
				continue
			if not ZinoBlockLibrary.compatible(fdef.output, inp[1]):
				errors.append({"node": l.to, "message": "type mismatch: '%s' gives %s but '%s' needs %s" % [fdef.label, fdef.output, inp[0], inp[1]]})
				continue
			var vkey: String = l.to + "|" + str(l.in)
			if value_in.has(vkey):
				errors.append({"node": l.to, "message": "input '%s' is connected twice" % l.in})
				continue
			value_in[vkey] = l.from

	var ctx := {"nodes": nodes, "exec_next": exec_next, "value_in": value_in, "errors": errors, "warnings": warnings, "used": {}}
	var ir := {"scripts": [], "functions": {}, "variables": {}}
	for v in program.get("variables", []):
		if v is Dictionary and str(v.get("name", "")) != "":
			ir.variables[str(v.name)] = v.get("value", 0)
	for id in nodes:
		var n: Dictionary = nodes[id]
		var d := ZinoBlockLibrary.get_def(n.block)
		if d.kind == "event":
			var params := _literal_args(n, d)
			var body := _chain(ctx, id, "next", [])
			ir.scripts.append({"event": n.block, "params": params, "body": body, "node": id})
			ctx.used[id] = true
		elif d.kind == "function":
			var fname := str(n.get("values", {}).get("name", "")).strip_edges()
			if fname == "":
				errors.append({"node": id, "message": "function needs a name"})
				continue
			if ir.functions.has(fname):
				errors.append({"node": id, "message": "function '%s' is defined twice" % fname})
				continue
			var params: Array = []
			for p in str(n.get("values", {}).get("params", "")).split(",", false):
				if p.strip_edges() != "":
					params.append(p.strip_edges())
			ir.functions[fname] = {"params": params, "body": _chain(ctx, id, "next", []), "node": id}
			ctx.used[id] = true
	# Calls to undefined functions.
	for id in nodes:
		var n: Dictionary = nodes[id]
		if n.block in ["fn_call", "fn_call_value"]:
			var fname := str(n.get("values", {}).get("name", "")).strip_edges()
			if not ir.functions.has(fname):
				errors.append({"node": id, "message": "function '%s' is not defined" % fname})
	# Blocks that can never run.
	for id in nodes:
		var d := ZinoBlockLibrary.get_def(nodes[id].block)
		if d.kind in ["stmt", "control"] and not ctx.used.has(id):
			warnings.append({"node": id, "message": "'%s' is not connected to an event and will never run" % d.label})
	if ir.scripts.is_empty() and not nodes.is_empty():
		warnings.append({"node": "", "message": "no event block: nothing will run"})
	return {"ok": errors.is_empty(), "ir": ir, "errors": errors, "warnings": warnings}

static func _input_def(d: Dictionary, name: String) -> Array:
	for inp in d.get("inputs", []):
		if inp[0] == name:
			return inp
	return []

static func _literal_args(n: Dictionary, d: Dictionary) -> Dictionary:
	var out := {}
	for inp in d.inputs:
		out[inp[0]] = n.get("values", {}).get(inp[0], inp[2])
	return out

## Follows an exec chain starting at node `from_id`'s output `out`. `stack` detects cycles.
static func _chain(ctx: Dictionary, from_id: String, out: String, stack: Array) -> Array:
	var body: Array = []
	var cur = ctx.exec_next.get(from_id + "|" + out)
	var seen := stack.duplicate()
	while cur != null:
		if cur in seen:
			ctx.errors.append({"node": cur, "message": "the flow loops back on itself; use a loop block instead"})
			break
		seen.append(cur)
		ctx.used[cur] = true
		var n: Dictionary = ctx.nodes[cur]
		var d := ZinoBlockLibrary.get_def(n.block)
		body.append(_stmt(ctx, cur, n, d, seen))
		cur = ctx.exec_next.get(cur + "|next")
	return body

static func _stmt(ctx: Dictionary, id: String, n: Dictionary, d: Dictionary, stack: Array) -> Dictionary:
	var args := _args(ctx, id, n, d, [])
	match n.block:
		"ctl_if":
			return {"op": "if", "cond": args.condition, "then": _chain(ctx, id, "then", stack), "else": [], "node": id}
		"ctl_if_else":
			return {"op": "if", "cond": args.condition, "then": _chain(ctx, id, "then", stack), "else": _chain(ctx, id, "else", stack), "node": id}
		"loop_repeat", "loop_forever", "loop_while", "loop_until", "loop_for", "loop_for_each":
			return {"op": "loop", "kind": n.block, "args": args, "body": _chain(ctx, id, "body", stack), "node": id}
		"loop_break":
			return {"op": "break", "node": id}
		"flow_stop":
			return {"op": "stop", "node": id}
		"fn_return":
			return {"op": "return", "value": args.value, "node": id}
	return {"op": "block", "block": n.block, "args": args, "node": id}

static func _args(ctx: Dictionary, id: String, n: Dictionary, d: Dictionary, value_stack: Array) -> Dictionary:
	var args := {}
	for inp in d.inputs:
		var src = ctx.value_in.get(id + "|" + inp[0])
		if src != null:
			if src in value_stack:
				ctx.errors.append({"node": id, "message": "value connections form a cycle"})
				args[inp[0]] = {"k": "lit", "v": inp[2]}
				continue
			var sn: Dictionary = ctx.nodes[src]
			var sd := ZinoBlockLibrary.get_def(sn.block)
			ctx.used[src] = true
			var vs := value_stack.duplicate()
			vs.append(id)
			args[inp[0]] = {"k": "block", "block": sn.block, "args": _args(ctx, src, sn, sd, vs), "node": src}
		else:
			var lit = n.get("values", {}).get(inp[0], inp[2])
			var problem := _check_literal(lit, inp[1])
			if problem != "":
				ctx.errors.append({"node": id, "message": "'%s': %s" % [inp[0], problem]})
			args[inp[0]] = {"k": "lit", "v": lit}
	return args

static func _check_literal(v, t: String) -> String:
	match t:
		"number":
			return "" if (v is float or v is int) and not is_nan(float(v)) and not is_inf(float(v)) else "must be a number"
		"bool":
			return "" if v is bool else "must be true or false"
		"vector":
			return "" if ZinoFormat.is_finite_array(v, 3) else "must be 3 numbers"
		"var":
			return "" if v is String and v.strip_edges() != "" else "needs a variable name"
		_:
			if t.begins_with("enum:"):
				return "" if str(v) in t.substr(5).split("|") else "must be one of " + t.substr(5).replace("|", ", ")
	return ""

# --- Code view ----------------------------------------------------------------------------------

## Readable Zino Script (GDScript-like pseudocode). It documents the program; the block runtime
## executes the IR directly — this text is not compiled.
static func to_script(program: Dictionary) -> String:
	var r := compile(program)
	var lines := PackedStringArray()
	lines.append("# Zino Script — readable pseudocode of \"%s\" (executed by the Zino block runtime)" % program.get("name", ""))
	for e in r.errors:
		lines.append("# ERROR: " + e.message)
	for v in r.ir.get("variables", {}):
		lines.append("var %s = %s" % [_ident(v), _lit(r.ir.variables[v])])
	for f in r.ir.get("functions", {}):
		var fn: Dictionary = r.ir.functions[f]
		lines.append("")
		lines.append("func %s(%s):" % [_ident(f), ", ".join(fn.params.map(func(p): return _ident(p)))])
		_emit(fn.body, 1, lines)
	for s in r.ir.get("scripts", []):
		lines.append("")
		var head := ZinoBlockLibrary.render_label(s.event, s.params)
		lines.append("on %s:   # %s" % [s.event.trim_prefix("ev_"), head])
		_emit(s.body, 1, lines)
	return "\n".join(lines)

static func _emit(body: Array, depth: int, lines: PackedStringArray) -> void:
	var ind := "    ".repeat(depth)
	if body.is_empty():
		lines.append(ind + "pass")
		return
	for s in body:
		match s.op:
			"if":
				lines.append("%sif %s:" % [ind, _expr(s.cond)])
				_emit(s.then, depth + 1, lines)
				if not s.else.is_empty():
					lines.append(ind + "else:")
					_emit(s.else, depth + 1, lines)
			"loop":
				var a: Dictionary = s.args
				match s.kind:
					"loop_repeat": lines.append("%sfor _i in %s:" % [ind, _expr(a.times)])
					"loop_forever": lines.append("%swhile true:   # yields every frame" % ind)
					"loop_while": lines.append("%swhile %s:" % [ind, _expr(a.condition)])
					"loop_until": lines.append("%swhile not (%s):" % [ind, _expr(a.condition)])
					"loop_for": lines.append("%sfor %s in range(%s, %s + 1):" % [ind, _ident(str(a["var"].v)), _expr(a["from"]), _expr(a.to)])
					"loop_for_each": lines.append("%sfor %s in %s:" % [ind, _ident(str(a["var"].v)), _ident(str(a.list.v))])
				_emit(s.body, depth + 1, lines)
			"break": lines.append(ind + "break")
			"stop": lines.append(ind + "return   # stop this script")
			"return": lines.append("%sreturn %s" % [ind, _expr(s.value)])
			_:
				lines.append(ind + _call(s.block, s.args))

static func _call(block: String, args: Dictionary) -> String:
	match block:
		"var_set": return "%s = %s" % [_ident(str(args["var"].v)), _expr(args.value)]
		"var_change": return "%s += %s" % [_ident(str(args["var"].v)), _expr(args.by)]
		"loop_wait": return "await wait(%s)" % _expr(args.seconds)
		"loop_wait_until": return "await wait_until(%s)" % _expr(args.condition)
		"fn_call": return "%s(%s)" % [_ident(str(args.name.v)), _fn_args(args)]
	var parts := PackedStringArray()
	for k in args:
		parts.append("%s=%s" % [k, _expr(args[k])])
	return "%s(%s)" % [block, ", ".join(parts)]

static func _fn_args(args: Dictionary) -> String:
	return ", ".join([_expr(args.arg1), _expr(args.arg2), _expr(args.arg3)])

static func _expr(e) -> String:
	if not (e is Dictionary):
		return str(e)
	if e.k == "lit":
		return _lit(e.v)
	var a: Dictionary = e.args
	match e.block:
		"m_num", "t_text", "log_bool": return _expr(a.value)
		"var_get": return _ident(str(a["var"].v))
		"m_op": return "(%s %s %s)" % [_expr(a.a), {"×": "*", "÷": "/", "mod": "%", "^": "**"}.get(str(a.op.v), str(a.op.v)), _expr(a.b)]
		"log_compare": return "(%s %s %s)" % [_expr(a.a), {"=": "==", "≠": "!=", "≤": "<=", "≥": ">="}.get(str(a.op.v), str(a.op.v)), _expr(a.b)]
		"log_and": return "(%s and %s)" % [_expr(a.a), _expr(a.b)]
		"log_or": return "(%s or %s)" % [_expr(a.a), _expr(a.b)]
		"log_not": return "not %s" % _expr(a.a)
		"fn_param": return _ident(str(a.name.v))
		"fn_call_value": return "%s(%s)" % [_ident(str(a.name.v)), _fn_args(a)]
	var parts := PackedStringArray()
	for k in a:
		parts.append(_expr(a[k]))
	return "%s(%s)" % [e.block, ", ".join(parts)]

static func _lit(v) -> String:
	if v is String:
		return "\"%s\"" % v.c_escape()
	if v is bool:
		return "true" if v else "false"
	if v is Array:
		return "Vector3(%s)" % ", ".join(v.map(func(x): return str(x)))
	return str(v)

static func _ident(s: String) -> String:
	var out := s.strip_edges().to_snake_case().replace(" ", "_")
	return out if out != "" else "_"
