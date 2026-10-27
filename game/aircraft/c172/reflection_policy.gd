class_name ReflectionPolicy
extends RefCounted
## Pure rules for the aircraft's ReflectionProbe (reflection_rig.gd): which graphics preset
## runs it and how, and when its cubemap has to be captured again. No nodes, so it is unit tested
## (tests/test_reflection_policy.gd). A capture renders the scenery six times, so it is throttled:
## the cubemap is re-taken only when the picture it holds has really changed.

const SUN_STEP_DEG := 2.0   # sun elevation change that makes the sky (and its glint) look different
const MOVE_M := 300.0       # horizontal travel since the capture (the probe box is +-600 m)
const ALT_M := 150.0        # altitude change since the capture (the box is +-300 m high)
const MIN_GAP_S := 2.0      # never capture more often than this, whatever changed
const WARM_S := 5.0         # a second capture this long after a start: the first one saw terrain still streaming in
const COVER_STEP := 0.15    # cloud cover change
const PRECIP_STEP := 0.2    # rain change
const VIS_RATIO := 0.3      # visibility change (relative)
const BASE_FT := 600.0      # cloud base change

## on: probe used. gap_s: periodic re-capture (0 = only when something changed). far_m: how far the
## capture sees (ReflectionProbe.max_distance; the box is already 1.2 km wide). intensity: probe
## reflection strength (a little under 1: the capture holds clouds and terrain the sky radiance lacks).
const PRESETS := {
	"low": {"on": false, "gap_s": 0.0, "far_m": 0.0, "intensity": 1.0},
	"medium": {"on": true, "gap_s": 30.0, "far_m": 2500.0, "intensity": 0.85},
	"high": {"on": true, "gap_s": 12.0, "far_m": 4000.0, "intensity": 0.85},
	"ultra": {"on": true, "gap_s": 5.0, "far_m": 6000.0, "intensity": 0.85},
}


static func for_preset(preset: String) -> Dictionary:
	return PRESETS.get(preset, PRESETS.high)


## What the capture depends on, taken now: sun elevation (deg), ENU position (m), altitude (m),
## weather settings.
static func snapshot(sun_elev_deg: float, enu: Vector3, alt_m: float, cover: float, precip: float, vis_m: float, base_ft: float) -> Dictionary:
	return {"sun": sun_elev_deg, "enu": enu, "alt": alt_m, "cover": cover, "precip": precip, "vis": vis_m, "base": base_ft}


static func weather_changed(a: Dictionary, b: Dictionary) -> bool:
	return absf(a.cover - b.cover) > COVER_STEP or absf(a.precip - b.precip) > PRECIP_STEP \
		or absf(a.base - b.base) > BASE_FT or absf(a.vis - b.vis) > VIS_RATIO * maxf(a.vis, 1000.0)


## True when the cubemap taken at `last` is out of date at `cur`. since_s: seconds since that
## capture; gap_s: the preset's periodic refresh (0 = none); captures: how many were taken since
## the probe was (re)configured. Changes are honoured after MIN_GAP_S.
static func needs_refresh(last: Dictionary, cur: Dictionary, since_s: float, gap_s: float, captures := 2) -> bool:
	if last.is_empty():
		return true
	if since_s < MIN_GAP_S:
		return false
	if captures < 2 and since_s >= WARM_S:
		return true
	if gap_s > 0.0 and since_s >= gap_s:
		return true
	if absf(cur.sun - last.sun) > SUN_STEP_DEG or absf(cur.alt - last.alt) > ALT_M:
		return true
	var d := Vector2(cur.enu.x - last.enu.x, cur.enu.y - last.enu.y)
	return d.length() > MOVE_M or weather_changed(last, cur)
