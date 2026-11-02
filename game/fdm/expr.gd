class_name Expr
extends RefCounted
## Evaluator for the JSBSim-derived expression trees of aero.json / config.json (tools/jsb_expr.py):
##   number | {"p": property} | {"table": {...}} (Table) | {"op": name, "args": [...]}
## Operators: sum product min max avg and or (n-ary), difference (a - b - ...), quotient pow atan2 mod
## lt le gt ge eq ne (comparisons give 1 / 0), abs sqrt exp ln log2 log10 sin cos tan asin acos atan
## floor ceil fraction not neg toradians todegrees, ifthen (cond, then, else), interpolate1d (x, x0, y0,
## x1, y1, ...). Not converted (so not here): integral derivative lag switch clipto random.
## Properties are read from a context Dictionary (JSBSim name -> value). A name that is not in it reads
## 0.0, as the C172 always did; with Expr.strict set (tests, aircraft that opt in) it is also an error:
## recorded in Expr.unknown and pushed with push_error, so a converter / context mismatch is noticed.

static var strict := false
static var unknown := {}  # property / operator name -> true, filled in strict mode
static var quiet := false  # tests that provoke a miss on purpose: record it, no push_error


static func read(ctx: Dictionary, name: String) -> float:
	var v: Variant = ctx.get(name)
	if v != null:
		return v
	if strict:
		_miss("unknown property '%s'" % name)
	return 0.0


static func _miss(msg: String) -> void:
	if not unknown.has(msg):
		unknown[msg] = true
		if not quiet:
			push_error("Expr: " + msg)


static func eval(e: Variant, ctx: Dictionary) -> float:
	if e is float or e is int:
		return e
	if e.has("p"):
		return read(ctx, e.p)
	if e.has("op"):
		return _op(e.op, e.args, ctx)
	return Table.lookup(e.table, ctx)


static func _op(op: String, a: Array, ctx: Dictionary) -> float:
	match op:
		"product":
			var r := 1.0
			for x in a:
				r *= eval(x, ctx)
			return r
		"sum":
			var r := 0.0
			for x in a:
				r += eval(x, ctx)
			return r
		"difference":
			var r := eval(a[0], ctx)
			for i in range(1, a.size()):
				r -= eval(a[i], ctx)
			return r
		"quotient":
			return eval(a[0], ctx) / eval(a[1], ctx)
		"min":
			var r := eval(a[0], ctx)
			for i in range(1, a.size()):
				r = minf(r, eval(a[i], ctx))
			return r
		"max":
			var r := eval(a[0], ctx)
			for i in range(1, a.size()):
				r = maxf(r, eval(a[i], ctx))
			return r
		"avg":
			var r := 0.0
			for x in a:
				r += eval(x, ctx)
			return r / a.size()
		"and":
			for x in a:
				if eval(x, ctx) == 0.0:
					return 0.0
			return 1.0
		"or":
			for x in a:
				if eval(x, ctx) != 0.0:
					return 1.0
			return 0.0
		"ifthen":
			return eval(a[1], ctx) if eval(a[0], ctx) != 0.0 else eval(a[2], ctx)
		"interpolate1d":
			return _interp(a, ctx)
		"pow":
			return pow(eval(a[0], ctx), eval(a[1], ctx))
		"atan2":
			return atan2(eval(a[0], ctx), eval(a[1], ctx))
		"mod":
			return fmod(eval(a[0], ctx), eval(a[1], ctx))
		"lt", "le", "gt", "ge", "eq", "ne":
			return _compare(op, eval(a[0], ctx), eval(a[1], ctx))
	return _unary(op, eval(a[0], ctx))


static func _compare(op: String, x: float, y: float) -> float:
	var r := false
	match op:
		"lt": r = x < y
		"le": r = x <= y
		"gt": r = x > y
		"ge": r = x >= y
		"eq": r = x == y
		"ne": r = x != y
	return 1.0 if r else 0.0


static func _unary(op: String, x: float) -> float:
	match op:
		"abs": return absf(x)
		"sqrt": return sqrt(x)
		"exp": return exp(x)
		"ln": return log(x)
		"log2": return log(x) / log(2.0)
		"log10": return log(x) / log(10.0)
		"sin": return sin(x)
		"cos": return cos(x)
		"tan": return tan(x)
		"asin": return asin(clampf(x, -1.0, 1.0))
		"acos": return acos(clampf(x, -1.0, 1.0))
		"atan": return atan(x)
		"floor": return floor(x)
		"ceil": return ceil(x)
		"fraction": return x - (floorf(x) if x >= 0.0 else ceilf(x))
		"not": return 1.0 if x == 0.0 else 0.0
		"neg": return -x
		"toradians": return deg_to_rad(x)
		"todegrees": return rad_to_deg(x)
	_miss("unsupported operator '%s'" % op)
	return 0.0


## interpolate1d(x, x0, y0, x1, y1, ...): linear between the pairs, end values outside.
static func _interp(a: Array, ctx: Dictionary) -> float:
	var x := eval(a[0], ctx)
	var n := (a.size() - 1) / 2
	var x0 := eval(a[1], ctx)
	var y0 := eval(a[2], ctx)
	if x <= x0:
		return y0
	for i in range(1, n):
		var x1 := eval(a[1 + 2 * i], ctx)
		var y1 := eval(a[2 + 2 * i], ctx)
		if x <= x1:
			return lerpf(y0, y1, (x - x0) / (x1 - x0))
		x0 = x1
		y0 = y1
	return y0
