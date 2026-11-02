class_name AudioCurves
extends RefCounted
## The pure part of the data-driven layer sound engine (audio_layers.gd): curves, gates, edge triggers
## and the per-engine expansion of the aircraft.json "audio.layers" list. No audio server, no Props:
## everything takes plain values, so it is unit-testable headless (tests/test_audio_layers.gd).
##
## A layer (all keys optional but "file"):
##   file       sound file, relative to the aircraft sounds/ folder, or a res:// path (reuse another aircraft's)
##   bus        Engine | Environment | Cockpit (core/audio_settings.gd), default Cockpit
##   loop       true: plays always, volume / pitch follow the drive; false: a one-shot played on "trigger"
##   drive      number source: a Props key ("engines/{n}/n1"), a number, or [op, args...] with op in
##              sum mul sub div max min abs; {n} is the engine number when per_engine is set
##   volume     [[x, gain], ...] gain over the drive (linear interpolation, clamped at the ends)
##   pitch      [[x, pitch_scale], ...] over the drive
##   gain       fixed multiplier (default 1)
##   view       {"cockpit": f, "outside": f} extra volume factor per camera view (default 1 and 1)
##   muffle_hz  low-pass cut-off heard in the cockpit view (outside views are not filtered)
##   per_engine true: one copy per engine n = 1..count, panned from pan_spread (left) to +pan_spread (right)
##   gate       conditions, all must hold: view "cockpit" | "outside"; ground true | false (fdm/wow);
##              props [keys true]; not_props [keys false]; min {key: v}; max {key: v}; between {key: [lo, hi]}
##              (exclusive: "in transit"); moving {keys: [...], rate_min: per second}
##   trigger    one-shots: {prop, edge: rising | falling | change, threshold (numeric rising / falling,
##              default 0.5), to: [values] (change only: new value must be one of them)}; the volume is
##              gain * the volume curve of the drive at that moment

const BUSES := ["Engine", "Environment", "Cockpit"]


## Linear interpolation in [[x, y], ...] (sorted by x), clamped at both ends; an empty table gives `default`.
static func interp(table: Array, x: float, default := 1.0) -> float:
	if table.is_empty():
		return default
	if x <= table[0][0]:
		return table[0][1]
	for i in range(1, table.size()):
		if x <= table[i][0]:
			var x0: float = table[i - 1][0]
			var x1: float = table[i][0]
			var t := 0.0 if x1 <= x0 else (x - x0) / (x1 - x0)
			return lerpf(table[i - 1][1], table[i][1], t)
	return table[table.size() - 1][1]


## Left / right pan (-1..1) of engine n (1-based) out of count: one engine centred, two at -spread / +spread.
static func pan_for(n: int, count: int, spread: float) -> float:
	if count <= 1:
		return 0.0
	return lerpf(-spread, spread, float(n - 1) / float(count - 1))


## The layer list with per_engine layers expanded: one copy per engine, "{n}" replaced in every string
## (drive, trigger prop, gate keys), "n" and "pan" set, "id" made unique. Other layers get n = 0.
static func expand(layers: Array, engine_count: int) -> Array:
	var out := []
	for l in layers:
		if not l is Dictionary or not l.has("file"):
			continue
		if not l.get("per_engine", false):
			var c: Dictionary = l.duplicate(true)
			c["n"] = 0
			c["pan"] = 0.0
			c["id"] = l.get("id", str(l.file).get_file().get_basename())
			out.append(c)
			continue
		for n in range(1, engine_count + 1):
			var c: Dictionary = _subst(l.duplicate(true), str(n))
			c["n"] = n
			c["pan"] = pan_for(n, engine_count, float(l.get("pan_spread", 0.6)))
			c["id"] = "%s_%d" % [l.get("id", str(l.file).get_file().get_basename()), n]
			out.append(c)
	return out


static func _subst(v: Variant, n: String) -> Variant:
	if v is String:
		return v.replace("{n}", n)
	if v is Array:
		return v.map(func(e): return _subst(e, n))
	if v is Dictionary:
		var d := {}
		for k in v:
			d[_subst(k, n)] = _subst(v[k], n)
		return d
	return v


## Value of a drive spec; `values` maps Props key -> number (bool counts as 0 / 1).
static func drive_value(spec: Variant, values: Dictionary) -> float:
	if spec == null:
		return 0.0
	if spec is float or spec is int:
		return float(spec)
	if spec is String:
		return _num(values.get(spec, 0.0))
	if spec is Array and not spec.is_empty():
		var a: Array = spec.slice(1).map(func(e): return drive_value(e, values))
		match str(spec[0]):
			"sum":
				return a.reduce(func(s, e): return s + e, 0.0)
			"mul":
				return a.reduce(func(s, e): return s * e, 1.0)
			"sub":
				return a[0] - a.slice(1).reduce(func(s, e): return s + e, 0.0) if not a.is_empty() else 0.0
			"div":
				return a[0] / a[1] if a.size() > 1 and a[1] != 0.0 else 0.0
			"max":
				return a.max() if not a.is_empty() else 0.0
			"min":
				return a.min() if not a.is_empty() else 0.0
			"abs":
				return absf(a[0]) if not a.is_empty() else 0.0
	return 0.0


static func _num(v: Variant) -> float:
	if v is bool:
		return 1.0 if v else 0.0
	return float(v) if (v is float or v is int) else 0.0


## All Props keys a layer reads (drive, gate, trigger), so the node can sample them once per frame.
static func watched(layer: Dictionary) -> Array:
	var keys := {}
	_drive_keys(layer.get("drive"), keys)
	var g: Dictionary = layer.get("gate", {})
	for k in ["props", "not_props"]:
		for p in g.get(k, []):
			keys[p] = true
	for k in ["min", "max", "between"]:
		for p in g.get(k, {}):
			keys[p] = true
	for p in g.get("moving", {}).get("keys", []):
		keys[p] = true
	if g.has("ground"):
		keys["fdm/wow"] = true
	if layer.has("trigger"):
		keys[layer.trigger.get("prop", "")] = true
	keys.erase("")
	return keys.keys()


static func _drive_keys(spec: Variant, keys: Dictionary) -> void:
	if spec is String:
		keys[spec] = true
	elif spec is Array:
		for e in spec.slice(1):
			_drive_keys(e, keys)


## Gate check. ctx = {"view": "cockpit" | "outside", "values": {key: v}, "rates": {key: change per second}}.
static func gate_ok(gate: Dictionary, ctx: Dictionary) -> bool:
	var vals: Dictionary = ctx.get("values", {})
	if gate.has("view") and gate.view != ctx.get("view", "outside"):
		return false
	if gate.has("ground") and bool(vals.get("fdm/wow", false)) != bool(gate.ground):
		return false
	for k in gate.get("props", []):
		if _num(vals.get(k, 0.0)) <= 0.5:
			return false
	for k in gate.get("not_props", []):
		if _num(vals.get(k, 0.0)) > 0.5:
			return false
	for k in gate.get("min", {}):
		if _num(vals.get(k, 0.0)) < float(gate.min[k]):
			return false
	for k in gate.get("max", {}):
		if _num(vals.get(k, 0.0)) > float(gate.max[k]):
			return false
	for k in gate.get("between", {}):
		var v := _num(vals.get(k, 0.0))
		if v <= float(gate.between[k][0]) or v >= float(gate.between[k][1]):
			return false
	if gate.has("moving"):
		var rates: Dictionary = ctx.get("rates", {})
		var any := false
		for k in gate.moving.get("keys", []):
			any = any or absf(_num(rates.get(k, 0.0))) >= float(gate.moving.get("rate_min", 0.01))
		if not any:
			return false
	return true


## Did this trigger fire between two samples? prev == null means "no previous sample": never fires.
static func edge(trig: Dictionary, prev: Variant, cur: Variant) -> bool:
	if prev == null:
		return false
	var p := _num(prev)
	var c := _num(cur)
	var th := float(trig.get("threshold", 0.5))
	match str(trig.get("edge", "rising")):
		"rising":
			return p < th and c >= th
		"falling":
			return p >= th and c < th
		"change":
			if absf(p - c) < 1e-6:
				return false
			var to: Array = trig.get("to", [])
			return to.is_empty() or to.any(func(t): return absf(_num(t) - c) < 1e-6)
	return false


## {"on": gate passes, "vol": linear volume 0.., "pitch": pitch scale} of a loop layer now.
static func layer_state(layer: Dictionary, ctx: Dictionary) -> Dictionary:
	var on := gate_ok(layer.get("gate", {}), ctx)
	var d := drive_value(layer.get("drive"), ctx.get("values", {}))
	var vol := float(layer.get("gain", 1.0)) * interp(layer.get("volume", []), d) * view_factor(layer, str(ctx.get("view", "outside")))
	return {"on": on, "vol": vol if on else 0.0, "pitch": clampf(interp(layer.get("pitch", []), d), 0.05, 4.0)}


## Volume of a one-shot fired now (0 when its gate fails).
static func shot_volume(layer: Dictionary, ctx: Dictionary) -> float:
	if not gate_ok(layer.get("gate", {}), ctx):
		return 0.0
	var d := drive_value(layer.get("drive"), ctx.get("values", {}))
	return float(layer.get("gain", 1.0)) * interp(layer.get("volume", []), d) * view_factor(layer, str(ctx.get("view", "outside")))


static func view_factor(layer: Dictionary, view: String) -> float:
	return float(layer.get("view", {}).get(view, 1.0))


## Low-pass cut-off for a layer in this view (the interior filter): 0 = none.
static func muffle_for(layer: Dictionary, view: String) -> float:
	return float(layer.get("muffle_hz", 0.0)) if view == "cockpit" else 0.0
