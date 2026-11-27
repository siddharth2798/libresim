extends RefCounted
## Dawn checks for tests/debug_showcase.gd (merged into the scene list there): the same cockpit and outside view at
## VABB from 30 minutes before to 30 minutes after sunrise (07:10 IST on the default day 45, sun elevation about
## -7, -3.5, 0, +3.5 and +7 deg), plus a midday and a night reference. Names: dawn_<view>_<label>.
## The cockpit sits on runway 09 facing the sunrise; the outside view flies the 27 approach with the camera looking
## south-west over the city, the sun behind it.

const TIMES := {"m30": 6.67, "m15": 6.92, "rise": 7.17, "p15": 7.42, "p30": 7.67, "noon": 12.3, "night": 21.0}
const COCKPIT := {"weather": "Clear", "view": "cockpit", "prop_deg": 90.0,
	"setup": {"airport": "VABB", "runway": "09", "start": "runway", "visibility_m": 20000.0}}
const OUTSIDE := {"weather": "Clear", "view": "chase",
	"setup": {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 1500.0, "air_nm": 5.0, "visibility_m": 20000.0},
	"fly": {"secs": 1.0, "pitch": 0.0, "throttle": 0.6},
	"cam": [-24.0, -14.0, 6.0], "aim": [200.0, 60.0, -60.0], "fov": 70.0}


static func scenes() -> Dictionary:
	var out := {}
	for label in TIMES:
		for pair in [["cockpit", COCKPIT], ["outside", OUTSIDE]]:
			var d: Dictionary = (pair[1] as Dictionary).duplicate(true)
			d.setup.time_h = TIMES[label]
			out["dawn_%s_%s" % [pair[0], label]] = d
	return out
