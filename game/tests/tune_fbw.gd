extends Node
# temporary tuning harness (deleted at the end)
const KT := 0.514444
const FT := 0.3048
const DATA := {
	"limits": {"vne_kias": 350.0, "g_pos": 2.5, "g_neg": -1.0},
	"damage": {"hard_landing_ms": 2.5, "collapse_ms": 4.0, "nose_collapse_ms": 3.0, "main_load_w": 2.5, "nose_load_w": 1.6},
	"fcs": {"law": "airbus_fbw"},
}

func mk(over := {}) -> FDM:
	var d := DATA.duplicate(true)
	d.fcs.merge(over, true)
	return FDM.new(AircraftDef.make("a320", d, "res://aircraft/a320"))

func cruise(kcas: float, alt_ft: float, flap := 0, gear := false, over := {}) -> FDM:
	var f := mk(over)
	var alt := alt_ft * FT
	f.atmo.update(alt)
	f.fcs.flap_cmd = flap
	var tas := kcas * KT
	f.set_airborne(0.0, 0.0, alt, 0.0, tas)
	for u in f.units:
		u.warm_start(true)
	f.fcs.gear_cmd = 1 if gear else 0
	f.gear.gear_pos = 1.0 if gear else 0.0
	f.fcs.settle()
	f.trim_level(f.atmo.sound_speed * 0.0 + kcas * KT * sqrt(1.225 / f.atmo.density))
	return f

func run(f: FDM, sec: float, every := 0.5, tag := "") -> void:
	var n := int(sec * 60.0)
	for i in n:
		f.step(1.0 / 60.0)
		if i % int(every * 60.0) == 0:
			var e := f.euler()
			print("%s t=%.1f nz=%.3f q=%.2f p=%.1f phi=%.1f th=%.1f a=%.2f cas=%.0f alt=%.0f el=%.2f ths=%.2f ail=%.2f rud=%.2f I=%.2f pd=%.1f hold=%s ref=%.1f" % [tag, i / 60.0, f.flight_load_factor, rad_to_deg(f.w_b.y), rad_to_deg(f.w_b.x), rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(f.alpha), f.cas / KT, f.altitude() / FT, f.fcs.surface("elevator-l"), f.fcs.surface("stabilizer"), f.fcs.surface("aileron-l"), f.fcs.surface("rudder"), f.fcs.law.pitch.i_deg, rad_to_deg(f.fcs.law.roll.p_demand), f.fcs.law.roll.hold, rad_to_deg(f.fcs.law.roll.phi_ref)])

func _ready() -> void:
	var what := OS.get_cmdline_user_args()
	var f := cruise(250, 10000)
	print("trim ths %.2f el %.2f" % [f.fcs.surface("stabilizer"), f.fcs.surface("elevator-l")])
	if "hands" in what:
		run(f, 30, 2.0, "hands")
	if "pitch" in what:
		run(f, 3, 1.0, "pre")
		f.fcs.pitch = 0.3
		run(f, 5, 0.25, "step")
		f.fcs.pitch = 0.0
		run(f, 12, 1.0, "rel")
	if "roll" in what:
		f.fcs.roll = 1.0
		run(f, 3, 0.25, "roll")
		f.fcs.roll = 0.0
		run(f, 8, 0.5, "rel")
	get_tree().quit()
