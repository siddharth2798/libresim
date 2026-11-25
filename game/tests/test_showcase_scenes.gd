extends RefCounted
## The showcase / benchmark scenes (tests/debug_showcase.gd, used by tools/bench.sh and tools/make_screenshots.sh):
## every scene's camera definition is finite and above the ground, and the pre-screenshot check (ShowcaseCamera
## view_error) refuses a camera rig that was never set up, a non-finite camera or one under the ground. The graphics
## audit once saved low_ground and cloud_tops from under the terrain after a script error stopped the flight scene.

const Showcase := preload("res://tests/debug_showcase.gd")
const Aim := preload("res://tests/showcase_camera.gd")


func test_every_scene_camera_is_finite_and_above_ground() -> String:
	var all := Showcase.all_scenes()
	var n := 0
	for k in all:
		var d: Dictionary = all[k]
		if d.has("menu"):
			continue
		for v in d.get("variants", [{}]):
			var dd := d.duplicate()
			dd.merge(v, true)
			var err := Aim.def_error(dd)
			if err != "":
				return "%s: %s" % [k, err]
			n += 1
	return "" if n > 20 else "only %d flight scene views" % n


func test_scene_check_catches_bad_cameras() -> String:
	var bad := [
		{"setup": {"start": "air", "air_ft": 450.0}, "cam": [-22.0, -9.0, NAN], "aim": [60.0, 0.0, -8.0]},
		{"setup": {"start": "stand"}, "cam": [10.0, 0.0, 2.0], "aim": [10.0, 0.0, 2.0]},
		{"setup": {"start": "stand"}, "cam": [10.0, 0.0, -3.0], "aim": [0.0, 0.0, 0.0]},
		{"setup": {"start": "air", "air_ft": 20.0}, "cam": [0.0, 0.0, -10.0], "aim": [10.0, 0.0, 0.0]},
		{"look": [0.0, 120.0]},
		{"fov": 0.0}]
	for d in bad:
		if Aim.def_error(d) == "":
			return "accepted %s" % d
	return "" if Aim.def_error({"setup": {"start": "air", "air_ft": 450.0}, "cam": [-22.0, -9.0, 5.0], "aim": [60.0, 0.0, -8.0], "fov": 62.0}) == "" else "refused low_ground's camera"


func test_screenshot_check_refuses_unplaced_camera() -> String:
	var ok := Transform3D(Basis(), Vector3(0.0, 140.0, 0.0))
	if Aim.eye_error(ok, 140.0, 0.0, false) == "":
		return "a camera rig that was never set up (flight _ready stopped) passed"
	if Aim.eye_error(Transform3D(Basis(), Vector3(NAN, 0.0, 0.0)), 0.0, 0.0, true) == "":
		return "a non-finite camera passed"
	if Aim.eye_error(ok, 3.0, 560.0, true) == "":
		return "a camera 557 m under the ground passed"
	if Aim.eye_error(ok, 0.9, 1.0, true) != "":
		return "a camera at the ground (within UNDER_M) refused"
	return "" if Aim.eye_error(ok, 140.0, NAN, true) == "" else "unknown ground height refused"
