class_name FdmHarness
extends RefCounted
## Test helpers: builds an FDM at a given weight and flies it with a simple
## autopilot (pitch/roll attitude loops with altitude or speed outer loops).

const DT := 1.0 / 240.0
const KT := 0.514444
const FT := 0.3048
const LB := 0.45359237

var f: FDM
var mode := "alt"  # "alt" holds altitude, "speed" holds CAS with pitch, "none" = hands off
var target_alt := 0.0
var target_cas := 0.0
var target_pitch := 0.0
var _i_pitch := 0.0
var _i_speed := 0.0


func _init(gross_lb := 2550.0) -> void:
	f = FDM.new()
	set_gross(gross_lb)


## Fill tanks to 1/2 and spread people over the four seats to reach the gross weight.
func set_gross(lb: float) -> void:
	for t in f.mb.tanks:
		t.contents_kg = t.capacity_kg * 0.5
	for p in f.mb.point_masses:
		p.kg = 0.0
	f.mb.update()
	var each := maxf(lb * LB - f.mb.mass, 0.0) / 4.0
	for i in 4:
		f.mb.point_masses[i].kg = each
	f.mb.update()


func run(seconds: float, each: Callable = Callable()) -> void:
	var n := int(seconds / DT)
	for i in n:
		_autopilot()
		f.step(DT)
		if each.is_valid() and each.call() == true:
			return


func _autopilot() -> void:
	if mode == "none":
		return
	var e := f.euler()
	if mode == "alt":
		var vs := -f.velocity_ned().z
		target_pitch = clampf(0.004 * (target_alt - f.altitude()) - 0.02 * vs + f.alpha, -0.25, 0.3)
	elif mode == "speed":
		_i_speed = clampf(_i_speed + (f.cas - target_cas) * DT, -100.0, 100.0)
		target_pitch = clampf(0.03 * (f.cas - target_cas) + 0.006 * _i_speed, -0.3, 0.35)
	var err := target_pitch - e.y
	_i_pitch = clampf(_i_pitch + err * DT, -2.0, 2.0)
	f.fcs.pitch = clampf(3.0 * err + 1.5 * _i_pitch - 0.6 * f.w_b.y, -1.0, 1.0)
	f.fcs.roll = clampf(-2.0 * e.x - 0.5 * f.w_b.x, -1.0, 1.0)
	f.fcs.yaw = clampf(2.0 * f.beta - 0.3 * f.w_b.z, -1.0, 1.0)


func kcas() -> float:
	return f.cas / KT


func ktas() -> float:
	return f.vt / KT


func fpm() -> float:
	return -f.velocity_ned().z / FT * 60.0
