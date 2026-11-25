class_name TickTwin
extends RefCounted
## Test helper for the tick-rate equivalence tests (tests/test_tick_*.gd): runs one system node through the same scripted
## Props twice, once at the old 120 Hz (a call every physics tick, its `_tick` replaced by TickRate.new(120.0)) and once at its
## new rate, and returns what each pass published, to compare with stated tolerances. The passes run one after the other,
## because both would write the same Props.

const DT := 1.0 / 120.0


## `inputs` is called every tick with the time (set the Props the node reads), `setup` once with the new node (def, _ready, db ...).
## `keys` are Props paths (or "@name" for a property of the node). Samples are taken `every` seconds from `first`.
static func pass_of(cls: GDScript, ref: bool, seconds: float, inputs: Callable, setup: Callable, keys: Array, every := 1.0, first := 0.5) -> Array:
	var n: Node = cls.new()
	if ref:
		n._tick = TickRate.new(120.0)
	if setup.is_valid():
		setup.call(n)
	var out := []
	var next := first
	var t := 0.0
	for i in int(seconds / DT):
		t += DT
		inputs.call(t)
		n._physics_process(DT)
		if t >= next - 1e-9:
			next += every
			var row := {"t": t}
			for k in keys:
				row[k] = n.get(str(k).substr(1)) if str(k).begins_with("@") else Props.get_v(k)
			out.append(row)
	n.free()
	return out


## [reference at 120 Hz, new rate]
static func twin(cls: GDScript, seconds: float, inputs: Callable, setup: Callable, keys: Array, every := 1.0, first := 0.5) -> Array:
	return [pass_of(cls, true, seconds, inputs, setup, keys, every, first), pass_of(cls, false, seconds, inputs, setup, keys, every, first)]


## The largest |a - b| per key over all samples ({key: worst}); bools and strings count 1 when they differ.
static func worst(pair: Array) -> Dictionary:
	var w := {}
	for i in mini(pair[0].size(), pair[1].size()):
		for k in pair[0][i]:
			if k == "t":
				continue
			var a: Variant = pair[0][i][k]
			var b: Variant = pair[1][i][k]
			var d := 0.0
			if a is float or a is int:
				d = absf(float(a) - float(b))
			elif a is Vector3:
				d = (a - b).length()
			elif a is Array and a.size() == b.size():  # numbers per element (tanks, engines); anything else counts 1 when it differs
				for j in a.size():
					d = maxf(d, absf(float(a[j]) - float(b[j])) if (a[j] is float or a[j] is int) else (0.0 if a[j] == b[j] else 1.0))
			elif a != b:
				d = 1.0
			w[k] = maxf(w.get(k, 0.0), d)
	return w


## "" when every key's worst difference is within tol[key] (a missing key must be 0), else the first miss, with all of them printed.
static func check(label: String, pair: Array, tol: Dictionary) -> String:
	if pair[0].is_empty() or pair[0].size() != pair[1].size():
		return "%s: no samples" % label
	var w := worst(pair)
	var line := []
	var err := ""
	for k in w:
		var lim: float = tol.get(k, 0.0)
		line.append("%s %s (tol %s)" % [k, String.num(w[k], 7), String.num(lim, 7)])
		if w[k] > lim and err == "":
			err = "%s: %s differs by %s between 120 Hz and the new rate, tolerance %s" % [label, k, String.num(w[k], 6), String.num(lim, 6)]
	print("    %s, worst difference over %d samples: %s" % [label, pair[0].size(), ", ".join(line)])
	return err
