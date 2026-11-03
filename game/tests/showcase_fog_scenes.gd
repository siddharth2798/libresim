extends RefCounted
## Volumetric fog scenes (G5, world/volumetric_fog.gd) for tests/debug_showcase.gd (merged into its scene list).
## Run with --quality=ultra (or high / max) on Forward+; add --no-vfog for the "before" image.

const SCENES := {
	# storm cells with rain curtains under a monsoon base, seen from 5-10 km in the clear air between them (showers
	# only, so the camera is dry; storms 1: a cell in every 10 km square)
	"fog_storm_curtain": {"weather": "Monsoon", "view": "chase",
		"setup": {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 900.0, "air_nm": 8.0, "air_kt": 120.0, "time_h": 15.5,
			"storms": 1.0, "precip": 0.25, "cloud_base_ft": 2500.0, "visibility_m": 30000.0},
		"cam": [-30.0, -8.0, 6.0], "aim": [600.0, 0.0, 10.0], "fov": 75.0},
	# dawn mist pooled in the Ghats valleys: calm, hazy, the sun just up
	"fog_dawn_mist": {"weather": "Winter haze", "view": "chase",
		"setup": {"airport": "VAAV", "start": "air", "air_ft": 3800.0, "air_nm": 5.0, "air_kt": 100.0, "time_h": 7.6,
			"wind_kt": 2.0, "visibility_m": 6000.0},
		"cam": [-30.0, -10.0, 8.0], "aim": [400.0, 0.0, -120.0], "fov": 70.0},
	# light shafts under a broken deck in the late afternoon, looking towards the sun
	"fog_shafts": {"weather": "Scattered", "view": "chase",
		"setup": {"airport": "VAPO", "runway": "28", "start": "air", "air_ft": 1200.0, "air_nm": 4.0, "air_kt": 100.0, "time_h": 16.9,
			"cloud_base_ft": 4000.0, "cloud_cover": 0.6, "visibility_m": 12000.0, "precip": 0.0},
		"cam": [-30.0, -10.0, 4.0], "aim": [400.0, -60.0, 30.0], "fov": 70.0},
}


static func scenes() -> Dictionary:
	return SCENES.duplicate(true)
