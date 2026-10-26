extends RefCounted
## README showcase scenes for tests/debug_showcase.gd. One entry per screenshot:
##   menu: start-screen page (home | training | flight [+ step]), else a flight scene with
##   weather: preset name; setup: Session.setup overrides (airport, runway, start, air_ft, air_nm,
##            air_kt, time_h IST, day_of_year, wind_*, visibility_m, precip ...)
##   lesson: training lesson id; view: cockpit | chase | orbit | ...
##   fly: {secs, pitch, throttle, roll, flaps}: scripted flight before the aircraft is frozen
##   cam: [forward, right, up] metres from the aircraft in its heading frame, aim: same frame
##        (free camera); look: [yaw_deg, pitch_deg] for cockpit / orbit; fov; dist (orbit)
##   ui: UI elements to keep ("Hud", "Map", "Panel", "training"); map: show the moving map;
##   panel: 2D panel layout index (0 Full, 1 Split, 2 Compact, 3 Minimal, 4 Off)
##   wait: seconds before polling the streamers
##   prop_deg: fixed propeller angle; lights: {name: bool} cockpit light switches (e.g. strobe);
##   pilot_lesson: fly the landing lesson's scripted pilot (fly.landing) without any training UI;
##   variants: several camera tries from one placement (files <scene>_<n>.png), for looking around;
##   map_zoom (m per px) and gps (direct-to ident) for the moving map
## Order and file names of the final README images are in tools/make_screenshots.sh.

const SCENES := {
	"start_home": {"menu": "home"},
	"start_flight": {"menu": "flight", "step": 0, "weather": "Broken",
		"setup": {"airport": "VABB", "start": "stand", "time_h": 18.0}},
	"vabb_final_golden": {"weather": "Broken", "view": "cockpit", "pilot_lesson": "landing", "prop_deg": 90.0,
		"setup": {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 350.0, "air_nm": 1.1, "air_kt": 80.0,
			"time_h": 18.3, "wind_dir_deg": 270.0, "wind_kt": 6.0, "precip": 0.0, "visibility_m": 30000.0},
		"fly": {"landing": true, "secs": 22.0}},
	"low_ground": {"weather": "Fair", "view": "chase",
		"setup": {"airport": "VAPO", "start": "air", "air_ft": 450.0, "air_nm": 6.0, "time_h": 17.4, "visibility_m": 30000.0},
		"fly": {"secs": 3.0, "pitch": 0.0, "throttle": 0.6},
		"cam": [-22.0, -9.0, 5.0], "aim": [60.0, 0.0, -8.0], "fov": 62.0},
	"chase_close": {"weather": "Fair", "view": "chase",
		"setup": {"airport": "VAPO", "start": "air", "air_ft": 2500.0, "air_nm": 5.0, "time_h": 16.6, "visibility_m": 30000.0},
		"fly": {"secs": 3.0, "pitch": 0.0, "throttle": 0.7},
		"cam": [-8.0, -5.0, 2.2], "aim": [0.5, 0.0, 0.6], "fov": 48.0},
	"cloud_shadows": {"weather": "Scattered", "view": "chase",
		"setup": {"airport": "VAPO", "start": "air", "air_ft": 500.0, "air_nm": 6.0, "time_h": 15.0, "visibility_m": 40000.0},
		"fly": {"secs": 3.0, "pitch": 0.0, "throttle": 0.6},
		"cam": [-30.0, 0.0, 20.0], "aim": [200.0, 0.0, -20.0], "fov": 70.0},
	"ghats_chase": {"weather": "Fair", "view": "chase",
		"setup": {"airport": "VAAV", "start": "air", "air_ft": 2200.0, "air_nm": 5.0, "time_h": 17.2, "visibility_m": 25000.0},
		"fly": {"secs": 6.0, "pitch": 5.0, "throttle": 1.0},
		"cam": [-26.0, -11.0, 9.0], "aim": [50.0, 0.0, -6.0], "fov": 62.0},
	"night_approach": {"weather": "Clear", "view": "chase", "pilot_lesson": "landing", "lights": {"strobe": false},
		"setup": {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 350.0, "air_nm": 1.1, "air_kt": 80.0, "time_h": 20.2},
		"fly": {"landing": true, "secs": 22.0},
		"cam": [-18.0, 6.0, 4.0], "aim": [40.0, 0.0, -6.0], "fov": 62.0},
	"vabb_terminal": {"weather": "Clear", "view": "orbit",
		"setup": {"airport": "VABB", "start": "stand", "time_h": 18.95},
		"cam": [-150.0, 120.0, 90.0], "aim": [40.0, -60.0, 8.0], "fov": 50.0},
	"voci_stand": {"weather": "Fair", "view": "orbit",
		"setup": {"airport": "VOCI", "start": "stand", "time_h": 17.7},
		"cam": [-45.0, 20.0, 18.0], "aim": [25.0, -30.0, 8.0], "fov": 60.0},
	"monsoon": {"weather": "Monsoon", "view": "cockpit", "pilot_lesson": "landing",
		"setup": {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 350.0, "air_nm": 1.1, "air_kt": 80.0, "time_h": 15.0},
		"fly": {"landing": true, "secs": 22.0}},
	"training_landing": {"lesson": "landing", "view": "cockpit", "ui": ["training", "Hud"],
		"setup": {"air_ft": 500.0, "air_nm": 1.5},
		"fly": {"landing": true, "secs": 24.0}},
	"moving_map": {"weather": "Fair", "view": "chase", "ui": ["Panel"], "map": true, "panel": 2, "map_zoom": 140.0, "gps": "VAAV",
		"setup": {"airport": "VANM", "runway": "08", "start": "air", "air_ft": 3500.0, "air_nm": 4.0, "time_h": 10.0},
		"cam": [-18.0, 11.0, 4.0], "aim": [0.0, 11.0, 0.0], "fov": 60.0},
}
