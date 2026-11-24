class_name ZinoBlockRuntime
extends Node
## Executes compiled block programs (see ZinoBlockCompiler) inside a running game.
##
## Each triggered event starts a "thread": an explicit stack of frames, stepped every frame.
## Threads yield on wait blocks and also automatically after STEP_BUDGET steps, so a `forever` or
## runaway `while` loop can never freeze the game; it just continues next frame. Runtime errors stop
## only the failing thread and are reported with the block that caused them.

signal block_executed(node_id: String)
signal runtime_error(node_id: String, message: String)
signal log_message(level: String, text: String)

const STEP_BUDGET := 4000          # statements per thread per frame before an automatic yield
const MAX_THREADS := 256
const MAX_CALL_DEPTH := 64
const RUNAWAY_FRAMES := 600        # frames a thread may run without waiting before a warning

var context: ZinoGameContext
var trace_enabled := false
var programs: Array = []           # compiled IR dictionaries
var globals := {}                  # variable name -> value
var threads: Array = []
var time_since_start := 0.0
var frame_delta := 0.0
var _timers: Array = []            # [{script, program, interval, next}]
var _stats := {"steps": 0, "errors": 0, "started": 0}

class Frame:
	var body: Array
	var pc := 0
	var loop := ""                 # loop kind while this frame is a loop body
	var args := {}                 # evaluated loop arguments
	var counter := 0
	var items: Array = []
	var is_function := false
	var locals := {}

class ScriptThread:
	var frames: Array = []
	var program: Dictionary
	var wait_until := 0.0
	var wait_cond = null           # expression to wait for
	var done := false
	var busy_frames := 0
	var warned := false
	var event := ""

func load_programs(irs: Array) -> void:
	programs = irs
	globals.clear()
	for ir in programs:
		for v in ir.get("variables", {}):
			globals[v] = ir.variables[v]
	_timers.clear()
	for ir in programs:
		for s in ir.get("scripts", []):
			if s.event == "ev_timer":
				var every := maxf(0.05, float(s.params.get("seconds", 1.0)))
				_timers.append({"script": s, "program": ir, "interval": every, "next": every})

func stats() -> Dictionary:
	return _stats.duplicate()

## Starts every script listening to `event`. Params filter events that carry one (keys, areas, messages).
func fire(event: String, filter: Dictionary = {}) -> int:
	var started := 0
	for ir in programs:
		for s in ir.get("scripts", []):
			if s.event != event:
				continue
			var ok := true
			for k in filter:
				if str(s.params.get(k, "")) != str(filter[k]):
					ok = false
			if ok:
				_start(ir, s.body, event)
				started += 1
	return started

func _start(ir: Dictionary, body: Array, event: String) -> void:
	if threads.size() >= MAX_THREADS:
		_report("", "too many running scripts (%d); '%s' was not started" % [MAX_THREADS, event])
		return
	var t := ScriptThread.new()
	t.program = ir
	t.event = event
	var f := Frame.new()
	f.body = body
	t.frames.append(f)
	threads.append(t)
	_stats.started += 1

func _process(delta: float) -> void:
	frame_delta = delta
	time_since_start += delta
	for tm in _timers:
		tm.next -= delta
		if tm.next <= 0.0:
			tm.next += tm.interval
			_start(tm.program, tm.script.body, "ev_timer")
	fire("ev_every_frame")
	step_all()

## Advances every thread by up to one frame of work.
func step_all() -> void:
	for t in threads.duplicate():
		_run_thread(t)
	threads = threads.filter(func(t): return not t.done)

func _run_thread(t: ScriptThread) -> void:
	if t.wait_until > time_since_start:
		return
	if t.wait_cond != null:
		if not _truthy(_eval(t, t.wait_cond)):
			return
		t.wait_cond = null
	var budget := STEP_BUDGET
	while budget > 0:
		budget -= 1
		_stats.steps += 1
		if t.frames.is_empty():
			t.done = true
			return
		var f: Frame = t.frames.back()
		if f.pc >= f.body.size():
			if not _loop_continue(t, f):
				t.frames.pop_back()
			elif t.wait_until > time_since_start:
				t.busy_frames = 0
				return   # forever loops yield once per iteration
			continue
		var s: Dictionary = f.body[f.pc]
		f.pc += 1
		if trace_enabled and s.has("node"):
			block_executed.emit(s.node)
		var r = _exec(t, s)
		if r is String:
			match r:
				"yield":
					t.busy_frames = 0
					return
				"error", "stop":
					t.done = true
					return
	# Budget exhausted without waiting: yield to keep the game responsive.
	t.busy_frames += 1
	if t.busy_frames > RUNAWAY_FRAMES and not t.warned:
		t.warned = true
		log_message.emit("warning", "A '%s' script has run for %d frames without waiting. Add a Wait block inside long loops." % [t.event, RUNAWAY_FRAMES])

func _loop_continue(t: ScriptThread, f: Frame) -> bool:
	match f.loop:
		"loop_repeat":
			f.counter += 1
			if f.counter < int(f.args.times):
				f.pc = 0
				return true
		"loop_forever":
			f.pc = 0
			# A forever loop yields once per iteration so it naturally runs once per frame.
			t.wait_until = time_since_start + 0.0001
			return true
		"loop_while":
			if _truthy(_eval(t, f.args.cond_expr)):
				f.pc = 0
				return true
		"loop_until":
			if not _truthy(_eval(t, f.args.cond_expr)):
				f.pc = 0
				return true
		"loop_for":
			var next := float(_get_var(t, f.args.var_name)) + 1.0
			if next <= float(f.args.to):
				_set_var(t, f.args.var_name, next)
				f.pc = 0
				return true
		"loop_for_each":
			f.counter += 1
			if f.counter < f.items.size():
				_set_var(t, f.args.var_name, f.items[f.counter])
				f.pc = 0
				return true
	return false

func _exec(t: ScriptThread, s: Dictionary):
	match s.op:
		"if":
			var c = _eval(t, s.cond)
			if c is String and c == "__error":
				return "error"
			var f := Frame.new()
			f.body = s.then if _truthy(c) else s.else
			_inherit_locals(t, f)
			t.frames.append(f)
			return null
		"loop":
			return _begin_loop(t, s)
		"break":
			while not t.frames.is_empty():
				var f: Frame = t.frames.pop_back()
				if f.loop != "":
					return null
				if f.is_function:
					_report(s.node, "Break used outside a loop")
					return "error"
			return "stop"
		"stop":
			return "stop"
		"return":
			var v = _eval(t, s.value)
			while not t.frames.is_empty():
				var f: Frame = t.frames.pop_back()
				if f.is_function:
					return null   # statement calls ignore the value; value calls use _eval_function
			return "stop"
		"block":
			return _exec_block(t, s)
	return null

func _begin_loop(t: ScriptThread, s: Dictionary):
	var f := Frame.new()
	f.body = s.body
	f.loop = s.kind
	_inherit_locals(t, f)
	var a: Dictionary = s.args
	match s.kind:
		"loop_repeat":
			f.args = {"times": maxi(0, int(_num(t, a.times)))}
			if f.args.times <= 0:
				return null
		"loop_forever":
			pass
		"loop_while":
			f.args = {"cond_expr": a.condition}
			if not _truthy(_eval(t, a.condition)):
				return null
		"loop_until":
			f.args = {"cond_expr": a.condition}
			if _truthy(_eval(t, a.condition)):
				return null
		"loop_for":
			var vname := str(a["var"].v)
			var from := _num(t, a["from"])
			var to := _num(t, a.to)
			f.args = {"var_name": vname, "to": to}
			if from > to:
				return null
			_set_var(t, vname, from)
		"loop_for_each":
			var vname := str(a["var"].v)
			var list = _get_var(t, str(a.list.v))
			if not (list is Array):
				_report(s.node, "'%s' is not a list" % str(a.list.v))
				return "error"
			f.items = list.duplicate()
			f.args = {"var_name": vname}
			if f.items.is_empty():
				return null
			_set_var(t, vname, f.items[0])
	t.frames.append(f)
	return null

# --- Variables (function locals shadow globals) ----------------------------------------------

func _inherit_locals(t: ScriptThread, f: Frame) -> void:
	for i in range(t.frames.size() - 1, -1, -1):
		var p: Frame = t.frames[i]
		if p.is_function:
			f.locals = p.locals    # same dictionary: locals are shared within one call
			return

func _get_var(t: ScriptThread, name: String):
	if not t.frames.is_empty():
		var f: Frame = t.frames.back()
		if f.locals.has(name):
			return f.locals[name]
	return globals.get(name, 0)

func _set_var(t: ScriptThread, name: String, value) -> void:
	if not t.frames.is_empty():
		var f: Frame = t.frames.back()
		if f.locals.has(name):
			f.locals[name] = value
			return
	globals[name] = value

# --- Functions ----------------------------------------------------------------------------------

func _call_function(t: ScriptThread, s_node: String, fname: String, args: Array) -> bool:
	var fn := _find_function(fname)
	if fn.is_empty():
		_report(s_node, "function '%s' does not exist" % fname)
		return false
	var depth: int = t.frames.filter(func(f): return f.is_function).size()
	if depth >= MAX_CALL_DEPTH:
		_report(s_node, "function '%s' called itself too deeply (limit %d)" % [fname, MAX_CALL_DEPTH])
		return false
	var f := Frame.new()
	f.body = fn.body
	f.is_function = true
	for i in fn.params.size():
		f.locals[fn.params[i]] = args[i] if i < args.size() else 0
	t.frames.append(f)
	return true

func _find_function(fname: String) -> Dictionary:
	for ir in programs:
		if ir.get("functions", {}).has(fname):
			return ir.functions[fname]
	return {}

## Runs a function to completion synchronously for use inside an expression (no waits allowed).
func _eval_function(t: ScriptThread, node_id: String, fname: String, args: Array):
	var fn := _find_function(fname)
	if fn.is_empty():
		_report(node_id, "function '%s' does not exist" % fname)
		return "__error"
	var sub := ScriptThread.new()
	sub.program = t.program
	var depth: int = t.frames.filter(func(f): return f.is_function).size()
	if depth >= MAX_CALL_DEPTH:
		_report(node_id, "function '%s' called itself too deeply" % fname)
		return "__error"
	for f in t.frames:
		if f.is_function:
			var marker := Frame.new()
			marker.is_function = true
			marker.body = []
			marker.pc = 1
			sub.frames.append(marker)    # keeps recursion depth accounting
	var f := Frame.new()
	f.body = fn.body
	f.is_function = true
	for i in fn.params.size():
		f.locals[fn.params[i]] = args[i] if i < args.size() else 0
	sub.frames.append(f)
	var base := sub.frames.size() - 1
	var steps := 0
	while sub.frames.size() > base and steps < 200000:
		steps += 1
		var cur: Frame = sub.frames.back()
		if cur.pc >= cur.body.size():
			if not _loop_continue(sub, cur):
				sub.frames.pop_back()
			continue
		var s: Dictionary = cur.body[cur.pc]
		cur.pc += 1
		if s.op == "return":
			return _eval(sub, s.value)
		var r = _exec(sub, s)
		if r is String and r == "yield":
			_report(s.get("node", node_id), "Wait blocks cannot be used in a function whose result is used as a value")
			return "__error"
		if r is String and r in ["error", "stop"]:
			return "__error" if r == "error" else null
		if sub.wait_until > time_since_start:
			sub.wait_until = 0.0   # forever loops inside value functions just continue
	if steps >= 200000:
		_report(node_id, "function '%s' did not finish (possible infinite loop)" % fname)
		return "__error"
	return null

# --- Expressions ------------------------------------------------------------------------------

func _eval(t: ScriptThread, e):
	if not (e is Dictionary):
		return e
	if e.k == "lit":
		var v = e.v
		if v is Array and v.size() == 3:
			return ZinoFormat.v3(v)
		return v
	return _eval_block(t, e)

func _num(t: ScriptThread, e) -> float:
	var v = _eval(t, e)
	if v is bool:
		return 1.0 if v else 0.0
	if v is float or v is int:
		return float(v)
	if v is String and v.is_valid_float():
		return float(v)
	return 0.0

func _vec(t: ScriptThread, e) -> Vector3:
	var v = _eval(t, e)
	return v if v is Vector3 else ZinoFormat.v3(v)

func _str(t: ScriptThread, e) -> String:
	return _to_text(_eval(t, e))

static func _to_text(v) -> String:
	if v is float:
		return str(int(v)) if v == floorf(v) and absf(v) < 1e15 else str(snappedf(v, 0.001))
	if v is Vector3:
		return "(%s, %s, %s)" % [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
	return str(v)

static func _truthy(v) -> bool:
	if v is bool:
		return v
	if v is float or v is int:
		return v != 0
	if v is String:
		return v != "" and v != "__error"
	return v != null

func _eval_block(t: ScriptThread, e: Dictionary):
	var a: Dictionary = e.args
	var c := context
	match e.block:
		"m_num", "t_text", "log_bool":
			return _eval(t, a.value)
		"var_get": return _get_var(t, str(a["var"].v))
		"fn_param": return _get_var(t, str(a.name.v))
		"fn_call_value":
			return _eval_function(t, e.node, str(a.name.v), [_eval(t, a.arg1), _eval(t, a.arg2), _eval(t, a.arg3)])
		"log_compare":
			var x = _eval(t, a.a)
			var y = _eval(t, a.b)
			var op := str(a.op.v)
			if (x is float or x is int) and (y is float or y is int):
				match op:
					"=": return is_equal_approx(float(x), float(y))
					"≠": return not is_equal_approx(float(x), float(y))
					"<": return float(x) < float(y)
					">": return float(x) > float(y)
					"≤": return float(x) <= float(y)
					"≥": return float(x) >= float(y)
			var xs := _to_text(x)
			var ys := _to_text(y)
			match op:
				"=": return xs == ys
				"≠": return xs != ys
				"<": return xs < ys
				">": return xs > ys
				"≤": return xs <= ys
				"≥": return xs >= ys
			return false
		"log_and": return _truthy(_eval(t, a.a)) and _truthy(_eval(t, a.b))
		"log_or": return _truthy(_eval(t, a.a)) or _truthy(_eval(t, a.b))
		"log_not": return not _truthy(_eval(t, a.a))
		"m_op":
			var x := _num(t, a.a)
			var y := _num(t, a.b)
			match str(a.op.v):
				"+": return x + y
				"-": return x - y
				"×": return x * y
				"÷":
					if y == 0.0:
						_report(e.node, "division by zero")
						return 0.0
					return x / y
				"mod": return fposmod(x, y) if y != 0.0 else 0.0
				"^": return pow(x, y)
		"m_fn":
			var x := _num(t, a.a)
			match str(a.fn.v):
				"abs": return absf(x)
				"round": return roundf(x)
				"floor": return floorf(x)
				"ceil": return ceilf(x)
				"sqrt": return sqrt(maxf(0.0, x))
				"sin": return sin(deg_to_rad(x))
				"cos": return cos(deg_to_rad(x))
				"tan": return tan(deg_to_rad(x))
				"ln": return log(x) if x > 0.0 else 0.0
				"exp": return exp(x)
				"sign": return signf(x)
		"m_minmax":
			return minf(_num(t, a.a), _num(t, a.b)) if str(a.fn.v) == "min" else maxf(_num(t, a.a), _num(t, a.b))
		"m_clamp": return clampf(_num(t, a.value), _num(t, a.min), _num(t, a.max))
		"m_lerp": return lerpf(_num(t, a.a), _num(t, a.b), _num(t, a.t))
		"m_random":
			var lo := _num(t, a.min)
			var hi := _num(t, a.max)
			if lo == floorf(lo) and hi == floorf(hi):
				return float(randi_range(int(lo), int(hi)))
			return randf_range(lo, hi)
		"m_vec": return Vector3(_num(t, a.x), _num(t, a.y), _num(t, a.z))
		"m_vec_part":
			var v := _vec(t, a.v)
			match str(a.axis.v):
				"x": return v.x
				"y": return v.y
				"z": return v.z
				_: return v.length()
		"m_vec_op": return _vec(t, a.a) + _vec(t, a.b) if str(a.op.v) == "+" else _vec(t, a.a) - _vec(t, a.b)
		"m_vec_scale": return _vec(t, a.v) * _num(t, a.s)
		"m_distance": return _vec(t, a.a).distance_to(_vec(t, a.b))
		"m_delta": return frame_delta
		"m_time": return time_since_start
		"t_join": return _str(t, a.a) + _str(t, a.b)
		"t_length": return float(_str(t, a.a).length())
		"t_contains": return _str(t, a.a).contains(_str(t, a.b))
		"t_time": return format_lap_time(_num(t, a.seconds))
		"t_number": return String.num(_num(t, a.value), clampi(int(_num(t, a.decimals)), 0, 6))
		"t_to_number":
			var s := _str(t, a.text)
			return float(s) if s.is_valid_float() else 0.0
		"list_get":
			var list = _get_var(t, str(a["var"].v))
			var i := int(_num(t, a.index)) - 1
			if not (list is Array) or i < 0 or i >= list.size():
				_report(e.node, "item %d does not exist in '%s'" % [i + 1, str(a["var"].v)])
				return 0
			return list[i]
		"list_length":
			var list = _get_var(t, str(a["var"].v))
			return float(list.size()) if list is Array else 0.0
		"list_contains":
			var list = _get_var(t, str(a["var"].v))
			return list is Array and list.has(_eval(t, a.item))
		"data_load": return c.data_load(_str(t, a.key), _eval(t, a["default"]))
		"data_has": return c.data_has(_str(t, a.key))
	# Everything else is game state provided by the context.
	if c == null:
		_report(e.node, "no game is running")
		return 0
	var r = c.value_block(e.block, _eval_args(t, a), self)
	if r is Dictionary and r.has("__error"):
		_report(e.node, r.__error)
		return 0
	return r

func _eval_args(t: ScriptThread, a: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = _eval(t, a[k])
	return out

static func format_lap_time(seconds: float) -> String:
	if seconds <= 0.0 or is_inf(seconds):
		return "--:--.---"
	var m := int(seconds / 60.0)
	var s := seconds - m * 60.0
	return "%d:%06.3f" % [m, s]

# --- Statements ---------------------------------------------------------------------------------

func _exec_block(t: ScriptThread, s: Dictionary):
	var a: Dictionary = s.args
	match s.block:
		"var_set":
			_set_var(t, str(a["var"].v), _eval(t, a.value))
			return null
		"var_change":
			var name := str(a["var"].v)
			_set_var(t, name, float(_get_var(t, name) if (_get_var(t, name) is float or _get_var(t, name) is int) else 0.0) + _num(t, a.by))
			return null
		"list_new":
			_set_var(t, str(a["var"].v), [])
			return null
		"list_add", "list_remove", "list_clear":
			var name := str(a["var"].v)
			var list = _get_var(t, name)
			if not (list is Array):
				list = []
				_set_var(t, name, list)
			match s.block:
				"list_add": list.append(_eval(t, a.item))
				"list_clear": list.clear()
				"list_remove":
					var i := int(_num(t, a.index)) - 1
					if i < 0 or i >= list.size():
						_report(s.node, "item %d does not exist in '%s'" % [i + 1, name])
						return "error"
					list.remove_at(i)
			return null
		"loop_wait":
			t.wait_until = time_since_start + maxf(0.0, _num(t, a.seconds))
			return "yield"
		"loop_wait_until":
			if _truthy(_eval(t, a.condition)):
				return null
			t.wait_cond = a.condition
			return "yield"
		"fn_call":
			return null if _call_function(t, s.node, str(a.name.v), [_eval(t, a.arg1), _eval(t, a.arg2), _eval(t, a.arg3)]) else "error"
		"msg_broadcast":
			fire("ev_message", {"message": _str(t, a.message)})
			return null
		"dbg_log":
			log_message.emit("info", _str(t, a.value))
			return null
		"dbg_warn":
			log_message.emit("warning", _str(t, a.value))
			return null
		"data_save":
			if context:
				context.data_save(_str(t, a.key), _eval(t, a.value))
			return null
	if context == null:
		_report(s.node, "no game is running")
		return "error"
	var r = context.stmt_block(s.block, _eval_args(t, a), self)
	if r is Dictionary and r.has("__error"):
		_report(s.node, r.__error)
		return "error"
	return null

func _report(node_id: String, message: String) -> void:
	_stats.errors += 1
	runtime_error.emit(node_id, message)
	log_message.emit("error", message)
