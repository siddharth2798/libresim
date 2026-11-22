// ICAO Annex 14 runway paint for runway_v2.gdshader, laid out by RunwayMarkings.uniforms(): threshold stripes,
// designator (RunwayGlyphs atlas), centreline dashes, edge stripes, aiming point and touchdown-zone bars.
// s = metres from the nearer threshold, x = metres right of the centreline for an aircraft landing over it (so the far
// end's designator is turned half round and both read from the approach); centreline and edges use the runway's own
// (across, along). Every feature is box-filtered over the pixel footprint (hx across, hs along), so a stripe narrower
// than a pixel fades to its average share instead of shimmering. Needs rw_box (runway_surface) and width_m.

uniform sampler2D glyphs : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform int thr_k = 6;            // threshold stripes per side
uniform float thr_pitch = 3.25;   // stripe + gap (m)
uniform vec4 des_a = vec4(2.0, 7.0, -1.0, 0.0);  // ends[0] designator: tens, units, letter (atlas index, -1 none)
uniform vec4 des_b = vec4(0.0, 9.0, -1.0, 0.0);  // ends[1]
uniform float cl_hw = 0.45;       // centreline half-width (m)
uniform float cl_start = 90.0;    // first centreline dash (m along from ends[0])
uniform int cl_count = 0;
uniform float edge_hw = 0.45;     // edge stripe half-width (m)
uniform vec4 aim = vec4(400.0, 60.0, 10.0, 11.25);  // aiming point: distance, length, bar width, inner half-spacing
uniform int tdz_bits = 0;         // bit k-1: touchdown-zone pair at k x 150 m

const float RW_STRIPE = 1.8;
const float RW_GLYPH_W = 3.0, RW_GLYPH_H = 9.0, RW_GLYPH_GAP = 1.6;  // digit box and the space between two digits
const float RW_DES0 = 48.0, RW_LETTER_GAP = 6.0;
const float RW_ATLAS_N = 13.0, RW_CELL_W = 4.0, RW_CELL_H = 10.0, RW_MARGIN = 0.5;  // RunwayGlyphs

// integral over [0, u] of n pulses `on` metres long every `period` metres starting at 0
float rw_pulse_int(float u, float on, float period, float n) {
	u = clamp(u, 0.0, n * period);
	return floor(u / period) * on + min(mod(u, period), on);
}

// box-filtered pulse train at u (footprint +- h)
float rw_pulses(float u, float on, float period, float n, float h) {
	return (rw_pulse_int(u + h, on, period, n) - rw_pulse_int(u - h, on, period, n)) / (2.0 * h);
}

// coverage of glyph idx at glyph metres (gx right, gy away from the threshold); dgx / dgy: their screen derivatives
float rw_glyph(float idx, vec2 g, vec2 dgx, vec2 dgy) {
	if (idx < -0.5 || g.x < -RW_MARGIN || g.x > RW_GLYPH_W + RW_MARGIN || g.y < -RW_MARGIN || g.y > RW_GLYPH_H + RW_MARGIN) {
		return 0.0;
	}
	vec2 sc = vec2(1.0 / (RW_ATLAS_N * RW_CELL_W), -1.0 / RW_CELL_H);
	vec2 uv = vec2((idx * RW_CELL_W + g.x + RW_MARGIN) / (RW_ATLAS_N * RW_CELL_W), (RW_CELL_H - RW_MARGIN - g.y) / RW_CELL_H);
	return textureGrad(glyphs, uv, dgx * sc, dgy * sc).r;
}

// designator for the end with glyphs d: letter (if any) nearest the threshold, the number 6 m beyond it
float rw_designator(vec4 d, float s, float x, vec2 dgx, vec2 dgy) {
	float n0 = RW_DES0;
	float m = 0.0;
	if (d.z > -0.5) {
		m = rw_glyph(d.z, vec2(x + RW_GLYPH_W * 0.5, s - RW_DES0), dgx, dgy);
		n0 += RW_GLYPH_H + RW_LETTER_GAP;
	}
	float gy = s - n0;
	m = max(m, rw_glyph(d.x, vec2(x + RW_GLYPH_GAP * 0.5 + RW_GLYPH_W, gy), dgx, dgy));
	m = max(m, rw_glyph(d.y, vec2(x - RW_GLYPH_GAP * 0.5, gy), dgx, dgy));
	return m;
}

// Paint coverage 0..1. end_i: which threshold s and x are measured from (0 = ends[0]).
float rw_paint(float s, float x, float across, float along, int end_i, float hx, float hs, vec2 dgx, vec2 dgy) {
	float half_w = width_m * 0.5;
	float ax = abs(x);
	// edge stripes, outer edge just inside the pavement edge, the whole length
	float m = rw_box(abs(across), half_w - 0.15 - 2.0 * edge_hw, half_w - 0.15, hx);
	// centreline: 30 m dashes, 20 m gaps between the designators
	m = max(m, rw_pulses(along - cl_start, 30.0, 50.0, float(cl_count), hs) * rw_box(across, -cl_hw, cl_hw, hx));
	if (s < 120.0) {
		// threshold stripes: thr_k per side, the innermost two a double gap apart, 6 m to 36 m in
		float gap = thr_pitch - RW_STRIPE;
		m = max(m, rw_box(s, 6.0, 36.0, hs) * rw_pulses(ax - gap, RW_STRIPE, thr_pitch, float(thr_k), hx));
		if (s > RW_DES0 - 2.0 && ax < 8.0) {
			m = max(m, rw_designator(end_i == 0 ? des_a : des_b, s, x, dgx, dgy));
		}
	}
	// aiming point
	m = max(m, rw_box(s, aim.x, aim.x + aim.y, hs) * rw_box(ax, aim.w, aim.w + aim.z, hx));
	// touchdown zone: pairs every 150 m, triple / double / single 22.5 x 1.8 m bars 1.5 m apart, inner sides in line
	// with the aiming point's
	float k = floor((s - 11.25) / 150.0 + 0.5);
	if (k >= 1.0 && k <= 6.0 && ((tdz_bits >> (int(k) - 1)) & 1) == 1) {
		float bars = k <= 2.0 ? 3.0 : (k <= 4.0 ? 2.0 : 1.0);
		m = max(m, rw_box(s, k * 150.0, k * 150.0 + 22.5, hs) * rw_pulses(ax - aim.w, RW_STRIPE, 3.3, bars, hx));
	}
	return clamp(m, 0.0, 1.0);
}
