class_name CaptainDetect
extends RefCounted
## Is a Thrustmaster Captain Pack plugged in, and does the saved joystick table already carry its profile?
## Pure rules (present / applied / should_offer / resolve_state) over plain data, so tests need no hardware,
## plus the stored answer (UserOptions "captain_pack": "" = not asked, "applied", "declined") and the two
## test seams: `pads_provider` (a Callable returning [{id, name, guid}], invalid = the real pads) and
## `bindings_path` (the table the offer reads and writes). The prompt is ui/menu/captain_offer.gd, the polling
## on the start screen ui/menu/captain_watch.gd. Device names come from InputProfiles.PROFILES, never typed again.

const OPTION := "captain_pack"
const APPLIED := "applied"
const DECLINED := "declined"
## The actions whose binding names prove the profile is in the table (roll = sidestick, the rest = quadrant).
const FINGERPRINT := ["roll", "throttle", "flaps_lever", "speedbrake"]

static var pads_provider := Callable()
static var bindings_path := InputBindings.PATH


## Names (lower-case substrings) of the profile's devices: "sidestick", "q-eng".
static func device_names() -> Array[String]:
	var out: Array[String] = []
	for dev in InputProfiles.PROFILES[InputProfiles.CAPTAIN_PACK].values():
		out.append(str(dev.name).to_lower())
	return out


## action -> device name the profile gives it, for FINGERPRINT.
static func fingerprint() -> Dictionary:
	var out := {}
	for dev in InputProfiles.PROFILES[InputProfiles.CAPTAIN_PACK].values():
		for a in FINGERPRINT:
			if dev.axes.has(a):
				out[a] = str(dev.name)
	return out


## True when at least one pad's name matches a Captain Pack device (pads = [{id, name, guid}]).
static func present(pads: Array) -> bool:
	for p in pads:
		var n := str(p.get("name", "")).to_lower()
		for want in device_names():
			if n.contains(want):
				return true
	return false


## True when the table already carries the profile: every fingerprint action is an axis bound by the profile's device name.
## Deadzones, curves and calibration may differ.
static func applied(table: Dictionary) -> bool:
	var fp := fingerprint()
	for a in fp:
		var b = table.get(a)
		if not b is Dictionary or int(b.get("axis", -1)) < 0 or str(b.get("name", "")).to_lower() != str(fp[a]).to_lower():
			return false
	return not fp.is_empty()


## The stored answer after the silent upgrade: a table that already has the profile counts as "applied".
static func resolve_state(table: Dictionary, state: String) -> String:
	return APPLIED if state == "" and applied(table) else state


## Ask only when the pack is plugged in, nothing was answered yet and the table does not have the profile.
static func should_offer(pads: Array, table: Dictionary, state: String) -> bool:
	return present(pads) and resolve_state(table, state) == ""


# ---- with the game's own data -------------------------------------------------------------------

static func connected_pads() -> Array:
	if pads_provider.is_valid():
		return pads_provider.call()
	var pads := []
	for d in Input.get_connected_joypads():
		pads.append({"id": d, "name": Input.get_joy_name(d), "guid": Input.get_joy_guid(d)})
	return pads


static func state() -> String:
	return str(UserOptions.get_v(OPTION))


static func set_state(value: String) -> void:
	UserOptions.set_v(OPTION, value)


## Should the prompt appear now? Also stores the silent "applied" when the table already has the profile.
static func offer_now() -> bool:
	var st := state()
	if st != "":
		return false  # answered: no file read
	var table := InputBindings.load_from(bindings_path)
	var resolved := resolve_state(table, st)
	if resolved != st:
		set_state(resolved)
	return should_offer(connected_pads(), table, resolved)


## Writes the Captain Pack table to `path` through the same code as the Controls page's reset button
## (InputProfiles.apply_to, InputBindings.save_bump) and remembers "applied".
static func apply_profile(path := bindings_path) -> bool:
	var table := InputBindings.load_from(path)
	InputProfiles.apply_to(table, InputProfiles.CAPTAIN_PACK)
	set_state(APPLIED)
	return InputBindings.save_bump(table, path)
