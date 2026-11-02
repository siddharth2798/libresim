class_name LeverKeys
extends RefCounted
## Keyboard throttle / mixture / reverse for KeyboardControls: held keys move the levers, the
## detent keys jump to the next detent. Levers a joystick axis owns are left alone.
## One-engine aircraft without reverse take exactly the old path (controls/throttle += rate * dt).

const LEVER_RATE := 0.5  # lever travel per second
const REVERSE_RATE := 2.0

var kb: Node  # the KeyboardControls (its _k / _axis / put)
var _rev_drive := false  # reverse was selected by the reverse key


func _init(keyboard: Node) -> void:
	kb = keyboard


func _joy(name: String) -> bool:
	return Props.get_v("input/axis_owner/" + name, "") == "joy"


## Is lever i driven by a joystick axis (so the keyboard leaves it)?
func _owned(i: int) -> bool:
	return _joy("throttle" if i == 0 else "throttle_2")


func update(ctl: AircraftControls, dt: float) -> void:
	var lv := ctl.levers
	var thr_in: float = kb._axis("throttle_down", "throttle_up")
	if Props.get_b("ui/map_open"):  # the open map zooms with = / - / Num +/-: only Page Up/Down move the throttle
		thr_in = float(Input.is_physical_key_pressed(KEY_PAGEUP)) - float(Input.is_physical_key_pressed(KEY_PAGEDOWN))
	if lv.count == 1 and not lv.reverse:  # the single-engine path, unchanged
		if not _joy("throttle"):
			lv.write_pos(0, Props.get_f("controls/throttle") + thr_in * LEVER_RATE * dt)
	elif not _reverse_key(ctl, dt):
		_move_levers(ctl, thr_in, dt)
	if ctl.offers("mixture"):
		var delta: float = kb._axis("mixture_lean", "mixture_rich") * LEVER_RATE * dt
		if not _joy("mixture"):
			for i in lv.count:
				lv.write("mixture", i, clampf(lv.read("mixture", i, 1.0) + delta, 0.0, 1.0))


func _move_levers(ctl: AircraftControls, thr_in: float, dt: float) -> void:
	var lv := ctl.levers
	for i in lv.count:
		if _owned(i) or (not lv.separate and i > 0):
			continue
		var d := thr_in
		if lv.separate and i < 2 and ctl.offers("throttle_1_up"):  # the per-lever keys
			d += kb._axis("throttle_%d_down" % (i + 1), "throttle_%d_up" % (i + 1))
		var old := lv.pos(i)
		# held keys never cross idle: in reverse they only come back to idle, forward they stop at idle
		var p := clampf(old + d * LEVER_RATE * dt, -1.0 if old < 0.0 else 0.0, 0.0 if old < 0.0 else 1.0)
		lv.write_pos(i, p)


## Reverse key: levers at idle go back to REV MAX while it is held and return to idle on release
## (only a reverse we selected ourselves returns; a lever put in reverse by a detent key stays).
## True when it moved a lever this frame, so the throttle keys wait.
func _reverse_key(ctl: AircraftControls, dt: float) -> bool:
	var lv := ctl.levers
	if not lv.reverse:
		return false
	var held: bool = kb._k("reverse")
	var driven := false
	for i in lv.count:
		var p := lv.pos(i)
		if _owned(i):
			continue
		if held and p <= 0.001:  # reverse can only be selected from idle
			lv.write_pos(i, move_toward(p, -1.0, REVERSE_RATE * dt))
			driven = true
		elif not held and _rev_drive and p < 0.0:
			lv.write_pos(i, move_toward(p, 0.0, REVERSE_RATE * dt))
			driven = true
	_rev_drive = driven
	return driven


## Detent keys: all levers (the ones a joystick does not own) jump to the next detent.
func detent_key(ctl: AircraftControls, action: String) -> bool:
	if action != "throttle_detent_up" and action != "throttle_detent_down":
		return false
	var lv := ctl.levers
	var dir := 1 if action == "throttle_detent_up" else -1
	for i in (lv.count if lv.separate else 1):
		if not _owned(i):
			lv.write_pos(i, LeverDetents.step(lv.pos(i), lv.detents, dir, lv.reverse))
	return true
