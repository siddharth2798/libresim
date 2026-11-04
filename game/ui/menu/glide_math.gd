class_name GlideMath
extends RefCounted
## Maths of the air-start side view (glide_profile.gd): height over distance on final, runway at the right, the
## 3 degree path to the threshold. Heights in ft, distances in nm (what the start screen and Session.setup keep).

const CLOSE := 0.12  # within 12 % of the 3 degree height counts as "close to the path"
const MARGIN := Vector4(10, 22, 30, 24)  # left, top, right (the runway), bottom (the labels) px


## Height of the 3 degree path over the threshold at `nm` out (AirStart.FT_PER_NM_3DEG per nm).
static func path_ft(nm: float) -> float:
	return nm * AirStart.FT_PER_NM_3DEG


## Angle (deg) of the line from the threshold up to the aircraft.
static func angle_deg(ft: float, nm: float) -> float:
	return rad_to_deg(atan2(ft * 0.3048, maxf(nm, 0.001) * 1852.0))


## "close to the 3° path" | "above the 3° path" | "below the 3° path".
static func verdict(ft: float, nm: float) -> String:
	var ideal := path_ft(nm)
	if absf(ft - ideal) <= ideal * CLOSE:
		return "close to the 3° path"
	return "above the 3° path" if ft > ideal else "below the 3° path"


## "Path angle to the threshold: 1.0° (below the 3° path)".
static func caption(ft: float, nm: float) -> String:
	return "Path angle to the threshold: %.1f° (%s)" % [angle_deg(ft, nm), verdict(ft, nm)]


## Layout in a control of `size` px for an aircraft `ft` high, `nm` out. The ranges are the aircraft's (`max_nm` = its
## distance limit, the height range 0.45 x its height limit, more only when the aircraft is higher than that), so the
## picture keeps its scale while the pilot changes a number. Returns {span_nm, span_ft, threshold (Vector2: runway end on
## the ground), ground_y, plot (Rect2), marker (Vector2), path_end (Vector2: the 3 degree line where it leaves the plot)}.
static func layout(size: Vector2, ft: float, nm: float, max_nm := 25.0, max_ft := 12000.0) -> Dictionary:
	var span_nm := maxf(max_nm, nm)
	var span_ft := maxf(max_ft * 0.45, ft * 1.2)
	var plot := Rect2(MARGIN.x, MARGIN.y, maxf(size.x - MARGIN.x - MARGIN.z, 1.0), maxf(size.y - MARGIN.y - MARGIN.w, 1.0))
	var thr := Vector2(plot.end.x, plot.end.y)
	var at := func(n: float, f: float) -> Vector2:
		return Vector2(thr.x - n / span_nm * plot.size.x, thr.y - f / span_ft * plot.size.y)
	var n_end := span_nm  # the 3 degree line stops at the top of the plot or at the left edge
	if path_ft(span_nm) > span_ft:
		n_end = span_ft / AirStart.FT_PER_NM_3DEG
	return {"span_nm": span_nm, "span_ft": span_ft, "threshold": thr, "ground_y": thr.y, "plot": plot,
		"marker": at.call(nm, ft), "path_end": at.call(n_end, path_ft(n_end))}
