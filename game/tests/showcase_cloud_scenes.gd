extends RefCounted
## In-cloud presentation scenes for tests/debug_showcase.gd (merged into the scene list there): an A320 and a
## C172 inside an Overcast deck (base 3000 ft, tops ~5950 ft AMSL, aircraft at 3800 ft) seen from outside views,
## the cockpit, plus a clear-air shot and a cloud-edge shot that must not change with the in-cloud work.
## Chase / orbit / wing / tail use the camera rig's own placement (no "cam"), so the real camera distance is tested.

const IN_CLOUD := {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 3800.0, "air_nm": 6.0, "air_kt": 200.0,
	"time_h": 11.0, "cloud_base_ft": 3000.0}

const SCENES := {
	"cloud_a320_chase": {"weather": "Overcast", "view": "chase", "setup": {"aircraft": "a320"}, "merge_setup": IN_CLOUD},
	"cloud_c172_chase": {"weather": "Overcast", "view": "chase", "merge_setup": IN_CLOUD},
	"cloud_a320_orbit": {"weather": "Overcast", "view": "orbit", "setup": {"aircraft": "a320"}, "merge_setup": IN_CLOUD, "look": [0.6, 0.0]},
	"cloud_c172_orbit": {"weather": "Overcast", "view": "orbit", "merge_setup": IN_CLOUD, "look": [0.6, 0.0]},
	"cloud_a320_wing": {"weather": "Overcast", "view": "wing", "setup": {"aircraft": "a320"}, "merge_setup": IN_CLOUD},
	"cloud_c172_tail": {"weather": "Overcast", "view": "tail", "merge_setup": IN_CLOUD},
	"cloud_c172_cockpit": {"weather": "Overcast", "view": "cockpit", "prop_deg": 90.0, "merge_setup": IN_CLOUD},
	"cloud_a320_cockpit": {"weather": "Overcast", "view": "cockpit", "setup": {"aircraft": "a320"}, "merge_setup": IN_CLOUD},
	# unchanged-by-design controls: clear air, and the edge of a broken layer (aircraft just under the base)
	"cloud_clear_a320": {"weather": "Clear", "view": "chase", "setup": {"aircraft": "a320"},
		"merge_setup": {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 3800.0, "air_nm": 6.0, "air_kt": 200.0, "time_h": 11.0}},
	"cloud_edge_in": {"weather": "Broken", "view": "chase", "setup": {"aircraft": "a320"},
		"merge_setup": {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 3300.0, "air_nm": 6.0, "air_kt": 200.0, "time_h": 11.0, "cloud_base_ft": 3000.0}},
	"cloud_edge_a320": {"weather": "Scattered", "view": "chase", "setup": {"aircraft": "a320"},
		"merge_setup": {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 2900.0, "air_nm": 6.0, "air_kt": 200.0, "time_h": 11.0}},
}


## Scenes with "merge_setup" folded into "setup" (so the shared constants stay in one place).
static func scenes() -> Dictionary:
	var out := {}
	for k in SCENES:
		var d: Dictionary = SCENES[k].duplicate(true)
		var s: Dictionary = d.get("merge_setup", {}).duplicate()
		s.merge(d.get("setup", {}), true)
		d.erase("merge_setup")
		d.setup = s
		out[k] = d
	return out
