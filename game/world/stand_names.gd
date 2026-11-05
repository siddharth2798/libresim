class_name StandNames
extends RefCounted
## Names of the parking stands of an airport (airport_ops.json "stands"), worked out at run time: a pure function of the
## stand list, so the same data always gives the same names.
##   - a stand with a real OSM ref keeps it ("12", "Bay 40", "GA3");
##   - any other stand gets a stable made-up name: "Gate n" (jetbridge, or kind "gate") or "Bay n" (remote / apron),
##     numbered per airport in position order (west to east, then south to north, then data order), skipping numbers a
##     real ref already uses;
##   - two stands with the same real ref: the first keeps it, the next get "ref (2)", "ref (3)";
##   - the nearest terminal (terminals/<ICAO>.json, within TERMINAL_RADIUS_M) gives a hint: "near Terminal 1".
## Session.setup.stand holds the name. AirportOps.find_stand resolves a made-up name through find_index().
## Natural order ("Bay 2" before "Bay 10"): natural_less().

const TERMINAL_RADIUS_M := 2500.0


## "gate" for a jetbridge / gate stand, else "bay".
static func kind_of(st: Dictionary) -> String:
	return "gate" if st.get("jetbridge", false) or str(st.get("kind", "")) == "gate" else "bay"


static func _norm(name: String) -> String:
	return name.to_lower().replace(" ", "")


## How a stand name reads in a sentence, on screen or spoken: a plain ref is "stand 12", a name that already says
## what it is ("Bay 3", "Gate 4", "Stand B") stays as it is; "" = no name. One rule for the rail, chips, summaries,
## the taxi banner and ATC.
static func label(name: String) -> String:
	var t := name.strip_edges()
	if t == "":
		return ""
	var low := t.to_lower()
	return t if low.begins_with("bay") or low.begins_with("stand") or low.begins_with("gate") else "stand " + t


## The debug property "ops/stand" for a stand start: "VABB Bay 3 (jetbridge)". `shown` = display name (falls back to `ref`).
static func prop_text(icao: String, shown: String, ref: String, jetbridge: bool) -> String:
	return "%s %s%s" % [icao, shown if shown != "" else ref, " (jetbridge)" if jetbridge else ""]


## The display name of one stand `st` of `stands` (the real ref, else the made-up name); "" when it is not in the list.
static func name_of(stands: Array, st: Dictionary) -> String:
	var at := -1
	for i in stands.size():
		if is_same(stands[i], st):
			at = i
			break
	if at < 0:
		for i in stands.size():
			if stands[i].get("x", 0.0) == st.get("x", 1e9) and stands[i].get("y", 0.0) == st.get("y", 1e9):
				at = i
				break
	return "" if at < 0 else str(assign(stands)[at])


## One unique name per stand, same order as `stands`.
static func assign(stands: Array) -> Array:
	var names := []
	names.resize(stands.size())
	var used := {}  # normalised names in use
	var unnamed := []
	for i in stands.size():
		var ref := str(stands[i].get("ref", "")).strip_edges()
		if ref == "":
			unnamed.append(i)
			continue
		var name := ref
		var n := 2
		while used.has(_norm(name)):
			name = "%s (%d)" % [ref, n]
			n += 1
		used[_norm(name)] = true
		names[i] = name
	unnamed.sort_custom(func(a, b): return _before(stands[a], a, stands[b], b))
	var count := {"gate": 0, "bay": 0}
	for i in unnamed:
		var kind := kind_of(stands[i])
		var name := ""
		while name == "" or used.has(_norm(name)):
			count[kind] += 1
			name = "%s %d" % ["Gate" if kind == "gate" else "Bay", count[kind]]
		used[_norm(name)] = true
		names[i] = name
	return names


static func _before(a: Dictionary, ia: int, b: Dictionary, ib: int) -> bool:
	var ax := roundi(float(a.get("x", 0.0)))
	var bx := roundi(float(b.get("x", 0.0)))
	if ax != bx:
		return ax < bx
	var ay := roundi(float(a.get("y", 0.0)))
	var by := roundi(float(b.get("y", 0.0)))
	if ay != by:
		return ay < by
	return ia < ib  # sort_custom is not stable: the data order breaks ties


## Per stand: {name, made (true when the name is made up), kind "gate" | "bay", hint ("near Terminal 1" or ""), hint_m}.
## `terminals`: [{name, x, y}] (terminals_of()); none = no hint.
static func describe(stands: Array, terminals: Array = []) -> Array:
	var names := assign(stands)
	var out := []
	for i in stands.size():
		var st: Dictionary = stands[i]
		var near := _nearest(Vector2(float(st.get("x", 0.0)), float(st.get("y", 0.0))), terminals)
		out.append({"name": names[i], "made": str(st.get("ref", "")).strip_edges() == "", "kind": kind_of(st),
			"hint": ("near " + near.name) if not near.is_empty() else "", "hint_m": near.get("dist", 0.0)})
	return out


static func _nearest(p: Vector2, terminals: Array) -> Dictionary:
	var best := {}
	var best_d := TERMINAL_RADIUS_M
	for t in terminals:
		var d := p.distance_to(Vector2(float(t.x), float(t.y)))
		if d < best_d:
			best_d = d
			best = {"name": str(t.name), "dist": d}
	return best


## Indices (into `stands`) of the stands to offer an aircraft of `stand_class` (ground.stand_class), best first:
## GroundChoice.suits() keeps the suitable ones (all when none is), then the class order (airliner: gates, remote bays,
## GA; light aircraft: GA, remote bays, gates; "any": bays then gates), then natural order of the name. `names` = assign().
static func offered_indices(stands: Array, names: Array, stand_class: String) -> Array:
	var keep := []
	var any_ok := stands.any(func(s): return GroundChoice.suits(s, stand_class))
	for i in stands.size():
		if not any_ok or GroundChoice.suits(stands[i], stand_class):
			keep.append(i)
	var rank := func(i: int) -> int:
		if stand_class == "gate" or stand_class == "ga":
			return GroundChoice.rank(stands[i], stand_class)
		return 1 if kind_of(stands[i]) == "gate" else 0
	keep.sort_custom(func(a, b):
		var ra: int = rank.call(a)
		var rb: int = rank.call(b)
		if ra != rb:
			return ra < rb
		var c := natural_cmp(str(names[a]), str(names[b]))
		return c < 0 if c != 0 else a < b)
	return keep


## Index of the stand called `name` (a real ref, a made-up name or a "ref (2)"), compared without case and spaces;
## -1 when none.
static func find_index(stands: Array, name: String) -> int:
	if name.strip_edges() == "":
		return -1
	var want := _norm(name)
	var names := assign(stands)
	for i in names.size():
		if _norm(names[i]) == want:
			return i
	return -1


## The terminals of an airport as [{name, x, y}] from data/processed/terminals/<ICAO>.json (centroids, local ENU
## metres); a terminal without a name is "main terminal". [] when the airport has no file.
static func terminals_of(icao: String) -> Array:
	var rel := "terminals/%s.json" % icao
	if icao == "" or not FileAccess.file_exists(Paths.data(rel)):
		return []
	var d = Paths.load_json(rel)
	var out := []
	if d is Dictionary:
		for t in d.get("terminals", []):
			var c = t.get("centroid", [])
			if c is Array and c.size() >= 2:
				var tags = t.get("tags", {})
				out.append({"name": str(tags.get("name", "")) if str(tags.get("name", "")) != "" else "main terminal",
					"x": float(c[0]), "y": float(c[1])})
	return out


## Natural order: digit runs compare as numbers, the rest as lower-case text ("Bay 2" < "Bay 10" < "Bay A1").
static func natural_less(a: String, b: String) -> bool:
	return natural_cmp(a, b) < 0


static func natural_cmp(a: String, b: String) -> int:
	var x := _chunks(a)
	var y := _chunks(b)
	for i in mini(x.size(), y.size()):
		var p: String = x[i]
		var q: String = y[i]
		var pn := p.is_valid_int()
		var qn := q.is_valid_int()
		if pn and qn:
			var d := p.to_int() - q.to_int()
			if d != 0:
				return signi(d)
		elif pn != qn:
			return -1 if pn else 1  # a number sorts before text
		elif p != q:
			return -1 if p < q else 1
	return signi(x.size() - y.size())


static func _chunks(s: String) -> Array:
	var out := []
	var cur := ""
	var digit := false
	for ch in s.to_lower():
		var d: bool = ch >= "0" and ch <= "9"
		if cur != "" and d != digit:
			out.append(cur)
			cur = ""
		digit = d
		cur += ch
	if cur != "":
		out.append(cur)
	return out
