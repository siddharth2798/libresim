class_name CaptainMap
extends RefCounted
## Data and rules of the Captain Pack map (ui/menu/captain_map_panel.gd): the markers of ui/menu/captain_map/map.json, the raw pad
## axis / button each part of a marker stands for, which actions the saved joystick table binds to it right now, and the live reading.
## Pure over plain data (a binding table, a pad list [{id, name, guid}], a reader) so tests need no hardware.
## A marker is one physical control with one or more parts (the five positions of the auto brake dial, the four hat directions). A part's
## pad number comes from its `key` (a default action of InputProfiles.captain_pack), or `axis` / `button` in the file, or is unknown
## (unconfirmed). The owner's corrections made with Identify (`learn`) are kept in user://captain_map_learned.json and win over the file.
## The label of a control is what the table binds to its numbers, so a re-bound control shows its new action.

const PATH := "res://ui/menu/captain_map/map.json"
const CONF_RANK := {"measured": 0, "documented": 1, "unconfirmed": 2}

static var learned_path := "user://captain_map_learned.json"  # tests point it at a scratch file
static var _data := {}
static var _learned := {}
static var _learned_loaded := false


## The parsed map.json (read once).
static func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = d if d is Dictionary else {"devices": {}}
	return _data


## "sidestick" | "quadrant" in the order the file lists them.
static func devices() -> Array:
	return data().get("devices", {}).keys()


static func markers(device: String) -> Array:
	return data().get("devices", {}).get(device, {}).get("markers", [])


static func marker(device: String, id: String) -> Dictionary:
	for m in markers(device):
		if m.id == id:
			return m
	return {}


## The unique id of a part inside its device: "<marker>.<part>".
static func uid(m: Dictionary, p: Dictionary) -> String:
	return "%s.%s" % [m.id, p.id]


static func pad_name(device: String) -> String:
	return str(InputProfiles.PROFILES[InputProfiles.CAPTAIN_PACK].get(device, {}).get("name", device)).to_lower()


## The pad id of a device in `pads`, or -1.
static func pad_id(device: String, pads: Array) -> int:
	var want := pad_name(device)
	for p in pads:
		if str(p.get("name", "")).to_lower().contains(want):
			return int(p.id)
	return -1


## device name -> pad id of the pack devices found in `pads`.
static func connected(pads: Array) -> Dictionary:
	var out := {}
	for dev in devices():
		var pid := pad_id(dev, pads)
		if pid >= 0:
			out[dev] = pid
	return out


# ---- the owner's corrections ---------------------------------------------------------------------

## device -> part uid -> {"axis": n} or {"button": n}.
static func learned() -> Dictionary:
	if not _learned_loaded:
		_learned_loaded = true
		_learned = {}
		if FileAccess.file_exists(learned_path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(learned_path))
			if d is Dictionary and d.get("parts") is Dictionary:
				_learned = d.parts
	return _learned


## Forget the cache (a test changed the path, or the file).
static func reload_learned() -> void:
	_learned_loaded = false


## "This is <part>": remembers that the part is pad axis / button `idx` (kind "axis" | "button"). Another part that had the
## number loses it. Returns true when the file was written.
static func learn(device: String, part_uid: String, kind: String, idx: int) -> bool:
	var dev: Dictionary = learned().get(device, {})
	for k in dev.keys():
		if dev[k].get(kind, -1) == idx:
			dev.erase(k)
	dev[part_uid] = {kind: idx}
	learned()[device] = dev
	var f := FileAccess.open(learned_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": 1, "parts": learned()}, "  "))
	return true


# ---- pad numbers of the parts --------------------------------------------------------------------

## {"axis": n, "button": n} of a part for `os_name` (-1 = none, number unknown). Learned numbers win; a number the owner gave to
## another part is taken away from this one.
static func effective(device: String, m: Dictionary, p: Dictionary, os_name := "", profile := {}) -> Dictionary:
	var mine: Dictionary = learned().get(device, {}).get(uid(m, p), {})
	if mine.has("axis") or mine.has("button"):
		return {"axis": int(mine.get("axis", -1)), "button": int(mine.get("button", -1))}
	var out := {"axis": int(p.get("axis", -1)), "button": int(p.get("button", -1))}
	if p.has("key"):
		var prof := profile if not profile.is_empty() else InputProfiles.captain_pack(os_name if os_name != "" else OS.get_name())
		var b: Dictionary = prof.get(p.key, {})
		out.axis = int(b.get("axis", -1))
		out.button = int(b.get("button", -1))
	for k in learned().get(device, {}):
		for kind in ["axis", "button"]:
			if k != uid(m, p) and learned()[device][k].get(kind, -2) == out[kind]:
				out[kind] = -1
	return out


## {"axes": [...], "buttons": [...], "flip": bool} of all parts of a marker.
static func hw(device: String, m: Dictionary, os_name := "") -> Dictionary:
	var out := {"axes": [], "buttons": [], "flip": false}
	var prof := InputProfiles.captain_pack(os_name if os_name != "" else OS.get_name())
	for p in m.get("parts", []):
		var e := effective(device, m, p, os_name, prof)
		if e.axis >= 0:
			out.axes.append(e.axis)
			out.flip = out.flip or bool(p.get("flip", false))
		if e.button >= 0:
			out.buttons.append(e.button)
	return out


## The marker and part that stand for pad `kind` ("axis" | "button") number `idx` of `device`: {"marker", "part"} or {}.
static func find_part(device: String, kind: String, idx: int, os_name := "") -> Dictionary:
	var prof := InputProfiles.captain_pack(os_name if os_name != "" else OS.get_name())
	for m in markers(device):
		for p in m.get("parts", []):
			if effective(device, m, p, os_name, prof)[kind] == idx:
				return {"marker": m, "part": p}
	return {}


## "axis" for a marker that is an axis or a lever, else "button" (what kind of pad number its parts are).
static func part_kind(m: Dictionary, _p: Dictionary) -> String:
	return "axis" if str(m.get("kind", "")) in ["axis", "lever"] else "button"


## Confidence of one part: its `conf` in the file, "measured" once the owner has taught the number with Identify.
static func part_conf(device: String, m: Dictionary, p: Dictionary) -> String:
	if learned().get(device, {}).has(uid(m, p)):
		return "measured"
	return str(p.get("conf", "unconfirmed"))


## Worst confidence of a marker's parts: "measured" | "documented" | "unconfirmed".
static func confidence(device: String, m: Dictionary) -> String:
	var worst := "measured"
	for p in m.get("parts", []):
		var c := part_conf(device, m, p)
		if CONF_RANK.get(c, 2) > CONF_RANK[worst]:
			worst = c
	return worst


# ---- what the table binds -----------------------------------------------------------------------

## Is this binding read from `device`'s pad? By profile name first, then guid, then pad index (as InputBindings.pick_device).
static func on_device(b: Dictionary, device: String, pads: Array) -> bool:
	var want := pad_name(device)
	var bname := str(b.get("name", "")).to_lower()
	if bname != "":
		return bname.contains(want) or want.contains(bname)
	var guid := str(b.get("guid", ""))
	for p in pads:
		var hit: bool = (guid != "" and p.guid == guid) or (guid == "" and int(p.id) == int(b.get("device", 0)))
		if hit:
			return str(p.name).to_lower().contains(want)
	return false


## Does the table's binding of `action` read pad number `e` ({"axis", "button"} of a part) on `device`?
static func binds(b: Dictionary, e: Dictionary, device: String, pads: Array) -> bool:
	var hit := false
	if int(b.get("axis", -1)) >= 0:
		hit = int(b.axis) == e.axis
	elif int(b.get("button", -1)) >= 0:
		hit = int(b.button) == e.button
	return hit and on_device(b, device, pads)


## Actions the table binds to one part, split into {"now": offered by `controls` (all when null), "other": bound but not offered}.
static func part_actions(device: String, m: Dictionary, p: Dictionary, table: Dictionary, pads: Array, controls: AircraftControls = null, os_name := "") -> Dictionary:
	var e := effective(device, m, p, os_name)
	var out := {"now": [], "other": []}
	if e.axis < 0 and e.button < 0:
		return out
	for a in table:
		if binds(table[a], e, device, pads):
			(out.now if controls == null or controls.offers(a) else out.other).append(a)
	return out


## The same for a whole marker (the parts' actions together).
static func actions_for(device: String, m: Dictionary, table: Dictionary, pads: Array, controls: AircraftControls = null, os_name := "") -> Dictionary:
	var out := {"now": [], "other": []}
	for p in m.get("parts", []):
		var a := part_actions(device, m, p, table, pads, controls, os_name)
		for k in ["now", "other"]:
			for x in a[k]:
				if not x in out[k]:
					out[k].append(x)
	return out


## Short action name for the legend: the page's label without its bracket ("Engine 1 master (switch)" -> "Engine 1 master").
static func action_name(a: String) -> String:
	return str(InputBindings.LABELS.get(a, a)).split(" (")[0]


## The legend text of a marker and its state: {"text", "unbound" (nothing bound at all), "unused" (bound, but not on this aircraft)}.
static func describe(acts: Dictionary, aircraft_name := "") -> Dictionary:
	var names: PackedStringArray = []
	for a in acts.now:
		names.append(action_name(a))
	if not names.is_empty():
		return {"text": compact(names), "unbound": false, "unused": false}
	if not acts.other.is_empty():
		return {"text": "not used on %s" % (aircraft_name if aircraft_name != "" else "this aircraft"), "unbound": false, "unused": true}
	return {"text": "unbound", "unbound": true, "unused": false}


## Joins action names, folding a shared first words once: ["Auto brake BTV", "Auto brake LOW"] -> "Auto brake BTV / LOW".
static func compact(names: PackedStringArray) -> String:
	if names.size() < 2:
		return "" if names.is_empty() else names[0]
	var words: Array = []
	for n in names:
		words.append(n.split(" "))
	var p := 0
	while true:
		var ok := true
		for w in words:
			ok = ok and w.size() > p + 1 and w[p] == words[0][p]
		if not ok:
			break
		p += 1
	if p == 0:
		return ", ".join(names)
	var tails: PackedStringArray = []
	for w in words:
		tails.append(" ".join(w.slice(p)))
	return " ".join(words[0].slice(0, p)) + " " + " / ".join(tails)


## What to move to test a marker, from the hardware checklist (CaptainCheck.GROUPS), "" for a control it does not list.
static func test_hint(m: Dictionary) -> String:
	var group := str(m.get("check", ""))
	for g in CaptainCheck.GROUPS:
		if g[0] == group:
			var out: PackedStringArray = []
			for it in g[1]:
				out.append(it[1].split("  (")[0])
			return " · ".join(out)
	return ""


## Live reading of a marker. `read_axis(pad, axis) -> float`, `read_button(pad, button) -> bool`; `h` = hw().
## Returns {"axis": raw of the first axis or null, "down": any button held, "bar": 0..1 lever fill or -1..1 stick value or null}.
static func read(m: Dictionary, h: Dictionary, pad: int, read_axis: Callable, read_button: Callable) -> Dictionary:
	var out := {"axis": null, "down": false, "bar": null}
	if pad < 0:
		return out
	if not h.axes.is_empty():
		var raw: float = read_axis.call(pad, h.axes[0])
		out.axis = raw
		if str(m.get("kind", "")) == "axis":
			out.bar = raw
		else:
			out.bar = (1.0 - raw) * 0.5 if h.flip else (raw + 1.0) * 0.5
	for b in h.buttons:
		if read_button.call(pad, b):
			out.down = true
	return out
