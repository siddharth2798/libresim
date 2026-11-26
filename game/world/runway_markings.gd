class_name RunwayMarkings
extends RefCounted
## ICAO Annex 14 (5.2) runway marking layout for one runways.json record {airport, width, length, ends: [{ident, x, y,
## heading_true}, ...]}, as the uniforms of world/runway_v2.gdshader. Pure: no nodes, no data files.
## Shader coordinates: UV.y = metres along from ends[0]; for paint near either end the shader works in s = metres from
## that threshold and x = metres right of the centreline for an aircraft landing over it.
## Rules: threshold stripes by width (18 m -> 4 ... 60 m -> 16; 1.8 m wide, 30 m long from 6 m in, reaching to 3 m from
## the edge or 27 m from the axis), designator 12 m past them (9 m digits, letter on the threshold side), centreline
## 30 m dashes / 20 m gaps from 12 m past the designator, line widths by runway width, aiming point and touchdown-zone
## pairs by length (Annex 14 tables 5-1 / 5-2: pairs every 150 m, those within 50 m of the aiming point deleted).

const THR_CLASSES := [[60.0, 16], [45.0, 12], [30.0, 8], [23.0, 6], [18.0, 4]]
const STRIPE_W := 1.8
const THR_END := 36.0  # stripes from 6 m to 36 m past the threshold
const DES_START := 48.0  # designator 12 m past the stripes
const GLYPH_H := 9.0
const LETTER_GAP := 6.0  # between the letter (threshold side) and the number
const CL_GAP_AFTER_DES := 12.0
const CL_DASH := 30.0
const CL_PERIOD := 50.0
const TDZ_SPACING := 150.0
const PREVAILING_HDG := 260.0  # west-coast monsoon westerlies: the end landing into them is the busy one


## Threshold stripes in total (both sides) for a runway `width` metres wide: the nearest ICAO class at or below it.
static func stripe_count(width: float) -> int:
	for c in THR_CLASSES:
		if width >= float(c[0]) - 0.5:
			return int(c[1])
	return 4


## Stripe pitch (m, stripe + gap) so that count/2 stripes per side end 3 m from the edge (at most 27 m from the axis);
## the two innermost stripes are a double gap apart.
static func stripe_pitch(width: float) -> float:
	var reach := minf(width * 0.5 - 3.0, 27.0)
	return maxf(reach / (stripe_count(width) / 2.0), STRIPE_W + 0.6)


## Aiming point by landing distance: {dist (m from the threshold to its start), length, width, inner (half the
## spacing between the inner sides of the two bars: 18-22.5 m on long runways, the wider on 60 m ones)}.
static func aiming_point(length: float, width := 45.0) -> Dictionary:
	var inner := 11.25 if width >= 55.0 else 9.0
	if length >= 2400.0:
		return {"dist": 400.0, "length": 60.0, "width": 10.0, "inner": inner}
	if length >= 1200.0:
		return {"dist": 300.0, "length": 45.0, "width": 6.0, "inner": inner}
	if length >= 800.0:
		return {"dist": 250.0, "length": 30.0, "width": 6.0, "inner": 4.5}
	return {"dist": 150.0, "length": 30.0, "width": 4.0, "inner": 3.0}


## Touchdown-zone marking pairs by landing distance (Annex 14 table 5-2), before the aiming-point deletion.
static func tdz_pair_count(length: float) -> int:
	if length >= 2400.0:
		return 6
	if length >= 1500.0:
		return 4
	if length >= 1200.0:
		return 3
	if length >= 900.0:
		return 2
	return 1


## Distances (m from the threshold) of the touchdown-zone pairs that are painted: every 150 m, minus any within 50 m of
## the aiming point.
static func tdz_positions(length: float) -> Array:
	var aim: float = aiming_point(length).dist
	var out := []
	for k in range(1, tdz_pair_count(length) + 1):
		var d := k * TDZ_SPACING
		if absf(d - aim) > 50.0:
			out.append(d)
	return out


## Bars in each rectangle of the pair at distance d: triple, double, then single (22.5 x 1.8 m each).
static func tdz_bars(d: float) -> int:
	var k := int(round(d / TDZ_SPACING))
	return 3 if k <= 2 else (2 if k <= 4 else 1)


static func centreline_width(width: float) -> float:
	return 0.9 if width >= 44.5 else 0.45


static func edge_width(width: float) -> float:
	return 0.9 if width >= 29.5 else 0.45


## Atlas index of one designator character (RunwayGlyphs): 0-9 digits, 10 L, 11 C, 12 R, -1 none.
static func glyph(c: String) -> int:
	if c.length() == 1 and c >= "0" and c <= "9":
		return c.unicode_at(0) - 48
	return {"L": 10, "C": 11, "R": 12}.get(c.to_upper(), -1)


## [tens, units, letter] atlas indices for an end ident ("9" is painted "09"; letter -1 when there is none).
static func designator(ident: String) -> Array:
	var digits := ""
	var letter := ""
	for c in ident.strip_edges().to_upper():
		if c >= "0" and c <= "9":
			digits += c
		elif letter == "":
			letter = c
	if digits == "":
		digits = "00"
	digits = digits.right(2).lpad(2, "0")
	return [glyph(digits[0]), glyph(digits[1]), glyph(letter)]


## Metres past the threshold where the designator ends.
static func designator_end(ident: String) -> float:
	return DES_START + GLYPH_H + ((LETTER_GAP + GLYPH_H) if designator(ident)[2] >= 0 else 0.0)


## Stable per-runway seed in [0, 1000): the same runway always gets the same wear, cracks and patches.
static func runway_seed(airport: String, ident: String) -> float:
	var h := 2166136261
	for b in (airport + "/" + ident).to_utf8_buffer():  # FNV-1a, independent of the engine's String.hash
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return float(h % 100000) / 100.0


## Centreline dashes laid out symmetrically between the two designators: [first dash start (m along from
## ends[0]), dash count].
static func centreline_dashes(length: float, ident_a: String, ident_b: String) -> Array:
	var start_a := designator_end(ident_a) + CL_GAP_AFTER_DES
	var start_b := designator_end(ident_b) + CL_GAP_AFTER_DES
	var avail := length - start_a - start_b
	var n := maxi(int(floor((avail + CL_PERIOD - CL_DASH) / CL_PERIOD)), 0)
	var used := n * CL_PERIOD - (CL_PERIOD - CL_DASH)
	return [start_a + (avail - used) * 0.5, n]


## Which end gets the most landings (0 or 1): the one landing closest to into the prevailing wind.
static func busy_end(r: Dictionary) -> int:
	var d0 := absf(wrapf(float(r.ends[0].heading_true) - PREVAILING_HDG, -180.0, 180.0))
	var d1 := absf(wrapf(float(r.ends[1].heading_true) - PREVAILING_HDG, -180.0, 180.0))
	return 0 if d0 <= d1 else 1


static func _glyph_vec(ident: String) -> Vector4:
	var d := designator(ident)
	return Vector4(d[0], d[1], d[2], 0.0)


## Lights and touchdown-zone paint of runway record r from the ILS records (ils.json): {centreline: bool, tdz: [bool, bool]}.
## A touchdown zone (paint and fittings) belongs to an end with an ILS; the centreline lights to a runway with one ILS end
## or 2000 m and more (as AirportLights.describe).
static func lights_from_ils(r: Dictionary, ils: Array) -> Dictionary:
	if ils.is_empty():
		return {}
	var tdz := [false, false]
	for e in ils:
		if str(e.airport) == str(r.get("airport", "")):
			for i in 2:
				if str(e.runway) == str(r.ends[i].ident):
					tdz[i] = true
	return {"centreline": tdz[0] or tdz[1] or float(r.length) >= 2000.0, "tdz": tdz}


## Every runway_v2.gdshader uniform that depends on the runway (lights: {centreline: bool, tdz: [bool, bool]}, by
## default from the length as AirportLights does without ILS data; given (lights_from_ils), the touchdown-zone paint
## follows the ends with an ILS, so a runway end without one gets the non-precision look: no TDZ bars).
static func uniforms(r: Dictionary, lights := {}) -> Dictionary:
	var w := float(r.width)
	var L := float(r.length)
	var a: String = str(r.ends[0].ident)
	var b: String = str(r.ends[1].ident)
	var aim := aiming_point(L, w)
	var bits := 0
	for d in tdz_positions(L):
		bits |= 1 << (int(round(d / TDZ_SPACING)) - 1)
	var cl := centreline_dashes(L, a, b)
	var sd := runway_seed(str(r.get("airport", "")), a)
	var busy := 0.45 if L < 1500.0 else 1.0  # GA fields see far fewer landings
	var other := busy * (0.45 + 0.35 * fmod(sd * 7.31, 1.0))
	var rub := Vector2(busy, other) if busy_end(r) == 0 else Vector2(other, busy)
	var lane_choices := [3.75, 4.5, 5.0]
	var lane_target: float = lane_choices[int(sd) % 3]
	var tdz: Array = lights.get("tdz", [L >= 2400.0, L >= 2400.0])
	var bits_b := -1  # shader: ends[1] paints like ends[0]
	if lights.has("tdz"):
		bits_b = bits if tdz[1] else 0
		bits = bits if tdz[0] else 0
	return {
		"is_runway": true, "length_m": L, "width_m": w, "seed": sd,
		"thr_k": stripe_count(w) / 2, "thr_pitch": stripe_pitch(w),
		"des_a": _glyph_vec(a), "des_b": _glyph_vec(b),
		"cl_hw": centreline_width(w) * 0.5, "cl_start": cl[0], "cl_count": cl[1], "edge_hw": edge_width(w) * 0.5,
		"aim": Vector4(aim.dist, aim.length, aim.width, aim.inner), "tdz_bits": bits, "tdz_bits_b": bits_b,
		"rubber": rub, "gear_hw": 4.3 if L >= 1800.0 else 1.6,
		"lane_w": w / maxf(round(w / lane_target), 1.0),
		"cl_lights": bool(lights.get("centreline", L >= 2000.0)), "tdz_lights": Vector2(float(tdz[0]), float(tdz[1])),
		"surface": 1 if str(r.get("surface", "asphalt")) == "concrete" else 0,  # tools/09_runways.py; older data: asphalt
	}
