class_name CaptainAssign
extends RefCounted
## Binds a physical Captain Pack control to an action in the joystick binding table (the table of core/input_bindings.gd, the same one the
## Controls page edits), for the Captain Pack map (ui/menu/captain_map_panel.gd). Pure over the table: the caller saves it.
## A control is a pad axis / button number of a device ({"axis": n, "button": n} as CaptainMap.effective returns).
## Assigning replaces what the control did for the chosen aircraft (actions of other aircraft on the same control stay, as in the profile,
## where one lever is both the A320's speed brake and the C172's mixture) and moves the action off whatever control had it.

const SWITCHES := "Switches (stay down)"
const PRETTY := {"fcu": "Autopilot (FCU)", "efis": "EFIS", "elec": "Electrical", "hyd": "Hydraulics", "fuel_pumps": "Fuel pumps",
	"bleed": "Air", "signs": "Signs", "ext_lights": "Exterior lights", "anti_ice": "Anti-ice", "thrust_levers": "Thrust levers",
	"engine_master": "Engine masters", "engine_mode": "Engine mode", "rudder_trim": "Rudder trim", "parking_brake": "Parking brake"}


static func kind_of(e: Dictionary) -> String:
	return "axis" if int(e.get("axis", -1)) >= 0 else ("button" if int(e.get("button", -1)) >= 0 else "")


## Actions an aircraft offers for a control of this kind, as sections [[title, [actions]]]: a latching switch lists its switch actions
## first, then the rest by action group, ground operations last.
static func choices(controls: AircraftControls, kind: String, latching := false) -> Array:
	var offered: Array = controls.axes() if kind == "axis" else controls.buttons()
	var order: Array[String] = []
	var sec := {}
	for a in offered:
		var title := section(a, latching)
		if not sec.has(title):
			sec[title] = []
			order.append(title)
		sec[title].append(a)
	if SWITCHES in order:
		order.erase(SWITCHES)
		order.push_front(SWITCHES)
	if "Ground operations" in order:
		order.erase("Ground operations")
		order.append("Ground operations")
	return order.map(func(t): return [t, sec[t]])


static func section(action: String, latching: bool) -> String:
	if latching and (ControlActions.LEVELS.has(action) or ControlActions.in_selector(action)):
		return SWITCHES
	if action in ControlActions.GROUND:
		return "Ground operations"
	var g := ControlActions.group_of(action)
	return "General" if g == "" else str(PRETTY.get(g, g.replace("_", " ").capitalize()))


## Binds `action` to the control `e` of `device`. Returns {"ok", "error", "cleared" (actions this aircraft had on the control),
## "from" (the binding the action had, when it was on another control, else {})}.
static func assign(table: Dictionary, device: String, e: Dictionary, action: String, controls: AircraftControls, pads: Array = []) -> Dictionary:
	var kind := kind_of(e)
	if kind == "":
		return {"ok": false, "error": "The pad number of this control is not known yet. Press it with Identify on."}
	if (kind == "axis") != InputBindings.is_axis(action) or not table.has(action):
		return {"ok": false, "error": "%s needs a%s control." % [InputBindings.LABELS.get(action, action), "n axis" if InputBindings.is_axis(action) else " button"]}
	var prev: Dictionary = table[action].duplicate(true)
	var cleared := clear(table, device, e, controls, pads)
	cleared.erase(action)
	var b: Dictionary = table[action]
	var prof: Dictionary = InputProfiles.captain_pack(OS.get_name()).get(action, {})
	b.clear()
	if int(prof.get(kind, -1)) == int(e[kind]) and CaptainMap.on_device(prof, device, []):
		b.merge(prof)  # the profile's own binding of this control: calibration, detents and invert stay
	else:
		b.merge(InputBindings.unbound(action))
		b[kind] = int(e[kind])
		b.name = CaptainMap.pad_name(device)
	var from := {}
	if (int(prev.get("axis", -1)) >= 0 or int(prev.get("button", -1)) >= 0) and not CaptainMap.binds(prev, e, device, pads):
		from = prev
	return {"ok": true, "error": "", "cleared": cleared, "from": from}


## Unbinds what the aircraft has on the control; returns the actions.
static func clear(table: Dictionary, device: String, e: Dictionary, controls: AircraftControls, pads: Array = []) -> Array:
	var out := []
	for a in table:
		if controls.offers(a) and CaptainMap.binds(table[a], e, device, pads):
			unbind(table[a])
			out.append(a)
	return out


static func unbind(b: Dictionary) -> void:
	var axis := b.has("axis")  # an axis binding has an `axis` key (-1 when unbound), a button binding a `button` key
	b["axis" if axis else "button"] = -1
	b.guid = ""
	b.name = ""
	for k in InputBindings.CAL_KEYS:
		b.erase(k)
	if not axis:
		b.erase("invert")


## Does `action` have an invert option on this control? (a latching switch bound to a switch action)
static func has_invert(action: String) -> bool:
	return ControlActions.LEVELS.has(action)


## Where a moved action came from ("Base wheel", or "Pad 2 · button 7" for a control that is not on the map). `from` is the old binding.
static func describe_from(from: Dictionary, pads: Array = []) -> String:
	for dev in CaptainMap.devices():
		for m in CaptainMap.markers(dev):
			for p in m.get("parts", []):
				if CaptainMap.binds(from, CaptainMap.effective(dev, m, p), dev, pads):
					return str(p.label)
	return InputBindings.describe(from)
