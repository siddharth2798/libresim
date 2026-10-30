class_name CloudLook
extends RefCounted
## Pure maps for how flying inside cloud is drawn (CloudInside applies them, tests/test_weather_visuals.gd
## covers them). The cockpit keeps the realistic short visibility; outside views (chase, orbit, wing, tail)
## keep the aircraft readable: the extinction around it is capped so most of its light reaches the camera,
## and the cloud pass leaves a pocket free of cloud around the camera-to-aircraft distance.

const RAMP_LO := 0.02  # camera cloud density where the in-cloud look starts ...
const RAMP_HI := 0.45  # ... and where it is complete (was a hard switch at 0.05)
const SIGMA_THIN := 0.004  # 1/m extinction in thin cloud (visibility ~750 m)
const SIGMA_THICK := 0.03  # 1/m in dense cloud (visibility ~100 m): the cockpit keeps this
const SUBJECT_TRANS := 0.8  # outside views: share of the aircraft's light that reaches the camera
const SUBJECT_NEAR_M := 120.0  # the aircraft counts as the subject out to this distance, fading out by SUBJECT_FAR_M
const SUBJECT_FAR_M := 300.0
const BUBBLE := 1.5  # radius of the cloud-free pocket, in camera-to-aircraft distances
const VERT := 0.3  # in-cloud light is this much brighter looking straight up (darker straight down)
const SUN_FLOOR := 0.26  # diffuse "sun" energy kept in cloud (the sun stays dim: no shadows, no disc)
const GLOW := 0.22  # share of the sun colour added as a soft glow towards the sun inside cloud
const WISP_ALPHA := 0.07  # peak opacity of a cloud wisp at full density


## 0..1 how far the in-cloud look applies for a camera cloud density (continuous, no switch).
static func ramp(d: float) -> float:
	return smoothstep(RAMP_LO, RAMP_HI, d)


## Move `cur` towards `target` with time constant tau (s): easing into and out of cloud.
static func ease_to(cur: float, target: float, dt: float, tau: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-dt / maxf(tau, 1e-3)))


## Extinction (1/m) of the cloud itself at camera density d (thin cloud 0.004 .. dense 0.03).
static func sigma_inside(d: float) -> float:
	return lerpf(SIGMA_THIN, SIGMA_THICK, clampf(d * 2.0, 0.0, 1.0))


## 0..1 how much the aircraft is the subject of the picture: 0 in the cockpit and far from the aircraft.
static func subject_weight(dist_m: float, cockpit: bool) -> float:
	return 0.0 if cockpit else 1.0 - smoothstep(SUBJECT_NEAR_M, SUBJECT_FAR_M, dist_m)


## Largest extinction that still lets SUBJECT_TRANS of the aircraft's light through at dist_m.
static func subject_sigma_cap(dist_m: float) -> float:
	return -log(SUBJECT_TRANS) / maxf(dist_m, 1.0)


## Visibility (m, 5 % contrast) that cap gives: always well over 3x the camera-to-aircraft distance.
static func subject_visibility_m(dist_m: float) -> float:
	return -log(0.05) / subject_sigma_cap(dist_m)


## Fog extinction (1/m): the clear-air `haze` blends continuously (k) to the cloud's, which outside views cap
## by weight w (subject_weight). Never below the haze.
static func fog_sigma(haze: float, d: float, k: float, dist_m: float, w: float) -> float:
	var sig := sigma_inside(d)
	sig = lerpf(sig, minf(sig, subject_sigma_cap(dist_m)), w)
	return lerpf(haze, maxf(sig, haze), k)


## Radius (m) of the pocket the cloud pass keeps free of cloud around the camera (0 = none, cockpit).
static func bubble_m(dist_m: float, w: float) -> float:
	return BUBBLE * minf(dist_m, SUBJECT_NEAR_M) * w


## Brightness of the cloud interior by the aircraft's cloud kind: cumulonimbus (and a storm core) is dark.
static func kind_tone(kind: String, storm: float) -> float:
	var t := 0.72 if kind == "cumulonimbus" else (0.92 if kind == "stratiform" else 1.0)
	return t * (1.0 - 0.35 * clampf(storm, 0.0, 1.0))


## Luminance multiplier of the interior for a view direction with vertical component `up` (-1..1).
static func shade(up: float) -> float:
	return 1.0 + VERT * clampf(up, -1.0, 1.0)


## Soft forward-scatter glow, 0..1, for the cosine between the view direction and the sun.
static func glow(cos_sun: float) -> float:
	return pow(maxf(cos_sun, 0.0), 3.0)


## Colour of the interior seen along a view direction: the flat in-cloud grey with luminance structure.
static func tint(base: Color, up: float, cos_sun: float, glow_col: Color) -> Color:
	var s := shade(up)
	var g := glow(cos_sun)
	return Color(base.r * s + glow_col.r * g, base.g * s + glow_col.g * g, base.b * s + glow_col.b * g, 1.0)


## Diffuse sun energy kept inside cloud: `light` (0..1 daylight x overcast dimming), k the in-cloud factor,
## ext 0..1 how much of the view is an outside one (the cockpit gets half).
static func sun_floor(k: float, light: float, ext: float, tone: float) -> float:
	return SUN_FLOOR * k * smoothstep(0.1, 0.6, light) * lerpf(0.5, 1.0, ext) * tone


## Opacity of the cloud wisps: follows the in-cloud factor, a little more in dense cloud, dimmer in dark cloud.
static func wisp_alpha(k: float, d: float, tone: float) -> float:
	return WISP_ALPHA * k * (0.6 + 0.4 * clampf(d * 2.0, 0.0, 1.0)) * clampf(tone + 0.15, 0.0, 1.0)


## Half-length (m) of a wisp: puffs when slow, streaks that grow with the air speed (m/s).
static func wisp_length_m(speed: float) -> float:
	return 3.0 + minf(speed, 300.0) * 0.1

