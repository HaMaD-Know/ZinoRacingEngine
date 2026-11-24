extends ZinoTest
## Block coding: compiler validation, interpreter semantics, async waits, loop safety, functions.

var C = ZinoBlockCompiler

func _prog(nodes: Array, links: Array, vars: Array = []) -> Dictionary:
	var p := C.new_program("test")
	p.nodes = nodes
	p.links = links
	p.variables = vars
	return p

func _run(p: Dictionary, frames: int = 3) -> ZinoBlockRuntime:
	var c := C.compile(p)
	check(c.ok, "program compiles: %s" % str(c.errors))
	var rt := ZinoBlockRuntime.new()
	tree.root.add_child(rt)
	rt.set_process(false)
	rt.load_programs([c.ir])
	rt.fire("ev_game_start")
	for i in frames:
		rt.step_all()
	return rt

func test_starter_program_compiles_and_renders() -> void:
	var p := C.starter_program()
	var c := C.compile(p)
	check(c.ok, "starter program compiles: %s" % str(c.errors))
	check_eq(c.ir.scripts.size(), 3, "three event scripts")
	var code := C.to_script(p)
	check(code.contains("on race_start") and code.contains("if ") and code.contains("pseudocode"), "code view renders the program")
	check(ZinoBlockLibrary.DEFS.size() >= 140, "library has %d blocks" % ZinoBlockLibrary.DEFS.size())

func test_variables_loops_and_conditions() -> void:
	var ev := C.node("ev_game_start")
	var set0 := C.node("var_set", Vector2.ZERO, {"var": "x", "value": 0})
	var rep := C.node("loop_repeat", Vector2.ZERO, {"times": 10})
	var inc := C.node("var_change", Vector2.ZERO, {"var": "x", "by": 2})
	var cond := C.node("ctl_if_else")
	var cmp := C.node("log_compare", Vector2.ZERO, {"op": "="})
	var getx := C.node("var_get", Vector2.ZERO, {"var": "x"})
	var twenty := C.node("m_num", Vector2.ZERO, {"value": 20})
	var yes := C.node("var_set", Vector2.ZERO, {"var": "result", "value": "yes"})
	var no := C.node("var_set", Vector2.ZERO, {"var": "result", "value": "no"})
	var links := [C.link(ev.id, "next", set0.id), C.link(set0.id, "next", rep.id), C.link(rep.id, "body", inc.id),
		C.link(rep.id, "next", cond.id), C.link(getx.id, "value", cmp.id, "a"), C.link(twenty.id, "value", cmp.id, "b"),
		C.link(cmp.id, "value", cond.id, "condition"), C.link(cond.id, "then", yes.id), C.link(cond.id, "else", no.id)]
	var rt := _run(_prog([ev, set0, rep, inc, cond, cmp, getx, twenty, yes, no], links))
	check_eq(rt.globals.get("x"), 20.0, "repeat 10 × change by 2")
	check_eq(rt.globals.get("result"), "yes", "if/else took the right branch")
	rt.free()

func test_recursive_function_returns_value() -> void:
	# fact(n) = n <= 1 ? 1 : n * fact(n - 1)
	var def := C.node("fn_define", Vector2.ZERO, {"name": "fact", "params": "n"})
	var cond := C.node("ctl_if_else")
	var le := C.node("log_compare", Vector2.ZERO, {"op": "≤", "b": 1})
	var pn := C.node("fn_param", Vector2.ZERO, {"name": "n"})
	var ret1 := C.node("fn_return", Vector2.ZERO, {"value": 1})
	var ret2 := C.node("fn_return")
	var mul := C.node("m_op", Vector2.ZERO, {"op": "×"})
	var pn2 := C.node("fn_param", Vector2.ZERO, {"name": "n"})
	var call := C.node("fn_call_value", Vector2.ZERO, {"name": "fact"})
	var sub := C.node("m_op", Vector2.ZERO, {"op": "-", "b": 1})
	var pn3 := C.node("fn_param", Vector2.ZERO, {"name": "n"})
	var ev := C.node("ev_game_start")
	var setr := C.node("var_set", Vector2.ZERO, {"var": "result"})
	var call5 := C.node("fn_call_value", Vector2.ZERO, {"name": "fact", "arg1": 5})
	var links := [C.link(def.id, "next", cond.id), C.link(pn.id, "value", le.id, "a"), C.link(le.id, "value", cond.id, "condition"),
		C.link(cond.id, "then", ret1.id), C.link(cond.id, "else", ret2.id), C.link(mul.id, "value", ret2.id, "value"),
		C.link(pn2.id, "value", mul.id, "a"), C.link(call.id, "value", mul.id, "b"), C.link(sub.id, "value", call.id, "arg1"),
		C.link(pn3.id, "value", sub.id, "a"), C.link(ev.id, "next", setr.id), C.link(call5.id, "value", setr.id, "value")]
	var rt := _run(_prog([def, cond, le, pn, ret1, ret2, mul, pn2, call, sub, pn3, ev, setr, call5], links))
	check_eq(rt.globals.get("result"), 120.0, "fact(5) = 120 via recursion")
	rt.free()

func test_infinite_loops_never_freeze() -> void:
	var ev := C.node("ev_game_start")
	var loop := C.node("loop_while", Vector2.ZERO, {"condition": true})
	var inc := C.node("var_change", Vector2.ZERO, {"var": "n", "by": 1})
	var ev2 := C.node("ev_game_start")
	var forever := C.node("loop_forever")
	var inc2 := C.node("var_change", Vector2.ZERO, {"var": "f", "by": 1})
	var p := _prog([ev, loop, inc, ev2, forever, inc2], [C.link(ev.id, "next", loop.id), C.link(loop.id, "body", inc.id),
		C.link(ev2.id, "next", forever.id), C.link(forever.id, "body", inc2.id)])
	var t0 := Time.get_ticks_msec()
	var rt := _run(p, 3)
	check(Time.get_ticks_msec() - t0 < 2000, "three frames of an endless while loop finish quickly")
	var n: float = rt.globals.get("n", 0.0)
	check(n > 100 and n <= 3 * ZinoBlockRuntime.STEP_BUDGET, "while(true) runs a bounded amount per frame (%d)" % int(n))
	check(float(rt.globals.get("f", 0.0)) <= 4.0, "forever loop yields every iteration (%d)" % int(rt.globals.get("f", 0.0)))
	check_eq(rt.threads.size(), 2, "both loops keep running across frames")
	rt.free()

func test_wait_is_asynchronous() -> void:
	var ev := C.node("ev_game_start")
	var a1 := C.node("var_set", Vector2.ZERO, {"var": "a", "value": 1})
	var w := C.node("loop_wait", Vector2.ZERO, {"seconds": 0.5})
	var a2 := C.node("var_set", Vector2.ZERO, {"var": "a", "value": 2})
	var rt := _run(_prog([ev, a1, w, a2], [C.link(ev.id, "next", a1.id), C.link(a1.id, "next", w.id), C.link(w.id, "next", a2.id)]), 1)
	check_eq(rt.globals.get("a"), 1, "paused at the wait")
	rt.time_since_start += 0.6
	rt.step_all()
	check_eq(rt.globals.get("a"), 2, "continued after the wait")
	check(rt.threads.is_empty(), "thread finished")
	rt.free()

func test_lists_text_and_messages() -> void:
	var ev := C.node("ev_game_start")
	var mk := C.node("list_new", Vector2.ZERO, {"var": "laps"})
	var add1 := C.node("list_add", Vector2.ZERO, {"item": 81.5, "var": "laps"})
	var add2 := C.node("list_add", Vector2.ZERO, {"item": 79.25, "var": "laps"})
	var sum0 := C.node("var_set", Vector2.ZERO, {"var": "sum", "value": 0})
	var each := C.node("loop_for_each", Vector2.ZERO, {"var": "t", "list": "laps"})
	var acc := C.node("var_change", Vector2.ZERO, {"var": "sum"})
	var gt := C.node("var_get", Vector2.ZERO, {"var": "t"})
	var fmt := C.node("var_set", Vector2.ZERO, {"var": "text"})
	var tt := C.node("t_time", Vector2.ZERO, {"seconds": 83.456})
	var bc := C.node("msg_broadcast", Vector2.ZERO, {"message": "go"})
	var on := C.node("ev_message", Vector2.ZERO, {"message": "go"})
	var got := C.node("var_set", Vector2.ZERO, {"var": "got", "value": true})
	var links := [C.link(ev.id, "next", mk.id), C.link(mk.id, "next", add1.id), C.link(add1.id, "next", add2.id), C.link(add2.id, "next", sum0.id),
		C.link(sum0.id, "next", each.id), C.link(each.id, "body", acc.id), C.link(gt.id, "value", acc.id, "by"), C.link(each.id, "next", fmt.id),
		C.link(tt.id, "value", fmt.id, "value"), C.link(fmt.id, "next", bc.id), C.link(on.id, "next", got.id)]
	var rt := _run(_prog([ev, mk, add1, add2, sum0, each, acc, gt, fmt, tt, bc, on, got], links))
	check_near(float(rt.globals.get("sum", 0)), 160.75, 0.001, "for-each sums the list")
	check_eq(rt.globals.get("text"), "1:23.456", "lap time formatting")
	check_eq(rt.globals.get("got"), true, "broadcast reached the receiver")
	rt.free()

func test_validation_reports_errors() -> void:
	var ev := C.node("ev_game_start")
	var cond := C.node("ctl_if")
	var speed := C.node("veh_speed")
	var c := C.compile(_prog([ev, cond, speed], [C.link(ev.id, "next", cond.id), C.link(speed.id, "value", cond.id, "condition")]))
	check(not c.ok and str(c.errors).contains("type mismatch"), "number into a condition is rejected")
	var a := C.node("dbg_log")
	var b := C.node("dbg_log")
	c = C.compile(_prog([ev, a, b], [C.link(ev.id, "next", a.id), C.link(a.id, "next", b.id), C.link(b.id, "next", a.id)]))
	check(not c.ok and str(c.errors).contains("loops back"), "flow cycle detected")
	var call := C.node("fn_call", Vector2.ZERO, {"name": "missing"})
	c = C.compile(_prog([ev, call], [C.link(ev.id, "next", call.id)]))
	check(not c.ok and str(c.errors).contains("not defined"), "undefined function detected")
	var w := C.node("env_weather", Vector2.ZERO, {"weather": "snowstorm"})
	c = C.compile(_prog([ev, w], [C.link(ev.id, "next", w.id)]))
	check(not c.ok and str(c.errors).contains("must be one of"), "invalid enum literal detected")
	var orphan := C.node("dbg_log")
	c = C.compile(_prog([ev, orphan], []))
	check(c.ok and str(c.warnings).contains("never run"), "unconnected blocks produce a warning")
	var l1 := C.node("dbg_log")
	var l2 := C.node("dbg_log")
	c = C.compile(_prog([ev, l1, l2], [C.link(ev.id, "next", l1.id), C.link(ev.id, "next", l2.id)]))
	check(not c.ok and str(c.errors).contains("connected twice"), "one output cannot fan out")
	c = C.compile({"format": "zino-blocks", "formatVersion": 99})
	check(not c.ok, "future format rejected")

func test_runtime_error_stops_only_that_script() -> void:
	var ev := C.node("ev_game_start")
	var mk := C.node("list_new", Vector2.ZERO, {"var": "l"})
	var bad := C.node("list_remove", Vector2.ZERO, {"index": 5, "var": "l"})
	var after := C.node("var_set", Vector2.ZERO, {"var": "after", "value": 1})
	var ev2 := C.node("ev_game_start")
	var ok := C.node("var_set", Vector2.ZERO, {"var": "other", "value": 1})
	var p := _prog([ev, mk, bad, after, ev2, ok], [C.link(ev.id, "next", mk.id), C.link(mk.id, "next", bad.id), C.link(bad.id, "next", after.id), C.link(ev2.id, "next", ok.id)])
	var c := C.compile(p)
	var rt := ZinoBlockRuntime.new()
	tree.root.add_child(rt)
	rt.set_process(false)
	var errors: Array = []
	rt.runtime_error.connect(func(node_id, msg): errors.append([node_id, msg]))
	rt.load_programs([c.ir])
	rt.fire("ev_game_start")
	rt.step_all()
	check_eq(errors.size(), 1, "one runtime error reported")
	check(errors.size() == 1 and errors[0][0] == bad.id, "error points at the failing block")
	check(not rt.globals.has("after"), "failing script stopped")
	check_eq(rt.globals.get("other"), 1, "other scripts keep running")
	rt.free()
