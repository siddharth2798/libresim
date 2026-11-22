shader_type spatial;
render_mode fog_disabled;
// Realistic runway (docs plan "Realistic runways", Stage 1: used by tests/debug_runway_preview only). A GroundDrape
// ribbon like runway.gdshader (UV.x 0..1 across, 0 = left of travel from ends[0]; UV.y metres along from ends[0]),
// with the same vertex treatment as strip.gdshaderinc: ground_lift far from the aircraft, Earth curvature and the
// 0.9985 view-space pull, and the same haze / wetness. Layout uniforms come from RunwayMarkings.uniforms(), the glyph
// atlas from RunwayGlyphs, the detail arrays from TerrainDetail.apply. Layers, bottom up: pavement (runway_surface),
// lane tone / patches / sealant or concrete slabs (runway_cracks), wheel tracks and oil, ICAO paint (runway_marks),
// sealant over old paint, rubber and the pilot's touchdown marks (runway_wear), inset light fittings.
// runway_detail (global, RunwayQuality from the preset): 0 Low (baked look + paint), 1 Medium (+ near-field sealant
// lines and tyre streaks), 2 High (+ aggregate texture and normal, light fittings), 3 Ultra / Max (+ near block cracks).
// Until its bake is ready (RunwayBakes) a runway draws a cheap unbaked look and fades the bake in over bake_mix.
#include "res://world/ground_lift.gdshaderinc"

uniform bool is_runway = true;
uniform float length_m = 1000.0;
uniform float width_m = 45.0;
uniform float seed = 0.0;        // RunwayMarkings.runway_seed: per-runway pattern
uniform float gear_hw = 4.3;     // typical main-gear half-track (m)
global uniform int runway_detail;
uniform bool cl_lights = false;  // inset centreline light fittings (as RunwayLightLayout.centreline)
uniform vec2 tdz_lights = vec2(0.0);  // touchdown-zone light fittings at ends[0] / ends[1]
uniform float lod_lift = 0.0007;
uniform sampler2D bake_tex : filter_linear_mipmap_anisotropic, repeat_disable, hint_default_black;  // RunwayBake
uniform float bake_mix = 0.0;  // 0 = no bake yet (unbaked look), 1 = baked
uniform vec2 marks_along = vec2(0.0, 0.0);  // along range (m) the own touchdown marks cover (bounding test)
global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;
global uniform float precip;
#include "res://world/rain_ripples.gdshaderinc"
global uniform vec2 pattern_origin;
#include "res://world/curvature.gdshaderinc"
#include "res://world/haze_sky.gdshaderinc"
varying float v_dist;
varying vec2 v_en;

#include "res://world/runway_surface.gdshaderinc"
#include "res://world/runway_marks.gdshaderinc"
#include "res://world/runway_wear.gdshaderinc"
#include "res://world/runway_cracks.gdshaderinc"

const vec3 RW_PAINT = vec3(0.72, 0.72, 0.7);
const vec3 RW_FITTING = vec3(0.26, 0.26, 0.25);

void vertex() {
	VERTEX.y += ground_lift((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD, lod_lift);
	VERTEX += curve_local(MODEL_MATRIX, curve_drop((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz));
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_en = vec2(wp.x + pattern_origin.x, -wp.z + pattern_origin.y);
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_dist = length(vp.xyz);
	vp.xyz *= 0.9985;
	POSITION = PROJECTION_MATRIX * vp;
}

// inset light fittings: coverage of the metal ring (lens: the dark glass inside it)
float rw_fittings(float along, float across, float s, float x, int end_i, float hx, out float lens) {
	lens = 0.0;
	float fade = 1.0 - smoothstep(0.025, 0.07, hx);
	if (fade <= 0.0) {
		return 0.0;
	}
	float d = 99.0;
	if (cl_lights && abs(across - 0.6) < 0.4) {
		float c = 7.5 + 15.0 * floor((along - 7.5) / 15.0 + 0.5);
		d = length(vec2(across - 0.6, along - c));
	}
	if ((end_i == 0 ? tdz_lights.x : tdz_lights.y) > 0.5 && s > 45.0 && s < 915.0 && abs(abs(x) - 10.5) < 2.0) {
		float sc = 60.0 + 30.0 * clamp(floor((s - 60.0) / 30.0 + 0.5), 0.0, 28.0);
		float xc = 9.0 + 1.5 * clamp(floor((abs(x) - 9.0) / 1.5 + 0.5), 0.0, 2.0);
		d = min(d, length(vec2(abs(x) - xc, s - sc)));
	}
	lens = (1.0 - smoothstep(0.07 - hx, 0.07 + hx, d)) * fade;
	return (1.0 - smoothstep(0.19 - hx, 0.19 + hx, d)) * fade;
}

void fragment() {
	float across = (UV.x - 0.5) * width_m;  // metres right of the centreline, travelling from ends[0]
	float along = UV.y;
	float hx = fwidth(across) * 0.6 + 1e-3;  // pixel half-footprints (m)
	float hs = fwidth(along) * 0.6 + 1e-3;
	bool far_end = along > length_m * 0.5;
	int end_i = far_end ? 1 : 0;
	float s = far_end ? length_m - along : along;  // from the nearer threshold
	float x = far_end ? -across : across;          // right of the centreline landing over it
	vec2 dgx = vec2(dFdx(x), dFdx(s)), dgy = vec2(dFdy(x), dFdy(s));
	bool concrete = surface == 1 || s < concrete_ends_m;
	// near field: where a pixel is finer than the bake's texels; faded out smoothly by ~300 m
	float nf_far = runway_detail >= 3 ? 300.0 : 220.0;  // High keeps the near field shorter (GPU budget)
	float nf = (1.0 - smoothstep(0.06, 0.15, max(hx, 0.12 * hs))) * (1.0 - smoothstep(nf_far * 0.73, nf_far, v_dist));
	// --- cheap layers: everything ROUGHNESS and NORMAL read (the SSAO normal-roughness prepass runs only these) ---
	vec4 bk = vec4(0.0);  // RunwayBake: tone x 4, sealant, stain, worn paint
	if (bake_mix > 0.0) {
		bk = texture(bake_tex, vec2(UV.x, along / length_m));
	}
	if (bake_mix < 1.0) {  // not baked yet: the same layers, cheaply (no lanes, patches or cracks)
		vec4 ub = vec4(rw_base(concrete, across, along).g * 4.0, 0.012, rw_stain(s, x, end_i),
			rw_paint(s, x, across, along, end_i, hx, hs, dgx, dgy) * 0.85);
		bk = mix(ub, bk, bake_mix);
	}
	vec3 col = vec3(bk.r * 0.25) * (concrete ? vec3(1.0, 0.985, 0.95) : vec3(1.0, 1.0, 1.03));
	vec3 dn;
	float dr, agg;
	col *= rw_aggregate(concrete, v_en, v_dist, dn, dr, agg);
	float rough = (concrete ? 0.8 : 0.88) + dr;
	float paint = bk.a;
	if (nf > 0.0) {
		// crisp analytic paint up close (glyph and stripe edges), the bake's average beyond
		paint = mix(paint, rw_paint(s, x, across, along, end_i, hx, hs, dgx, dgy) * rw_paint_left(s, x, hx, hs, agg), nf);
	}
	float seal = bk.g * (concrete ? 0.55 : 1.0 - 0.5 * paint);
	float p_st = rw_streak_p(s, end_i);
	float rub = p_st > 0.004 ? 1.0 - (1.0 - bk.b) * (1.0 - rw_streak_avg(p_st, x)) : 0.0;
	rough = mix(mix(mix(rough, 0.62, paint), 0.3, seal), 0.62, rub);
	dn *= (1.0 - 0.6 * paint) * (1.0 - seal) * (1.0 - 0.7 * rub);
	// --- albedo-only near field: exact sealant lines, tyre streaks, own marks, light fittings ---
	if (nf > 0.0 && runway_detail >= 1) {
		if (!concrete) {
			float border;
			rw_patch(across, along, hx, hs, border);
			seal = mix(seal, max(rw_sealant(across, along, hx, hs), border) * (1.0 - 0.5 * paint), nf);
		}
		if (p_st > 0.004 && abs(abs(x) - gear_hw) < 3.0 * (0.33 * gear_hw + 1.3)) {
			float st = rw_streaks(s, x, p_st, hx);
			rub = mix(rub, 1.0 - (1.0 - bk.b) * (1.0 - st), nf);
		}
	}
	if (mark_count > 0 && along > marks_along.x && along < marks_along.y) {
		rub = 1.0 - (1.0 - rub) * (1.0 - rw_own_marks(along, across, hx));
	}
	col = mix(col, RW_PAINT * (0.92 + 0.08 * rw_noise(vec2(across * 0.2, along * 0.05) + seed)), paint);
	col = mix(col, concrete ? col * 0.35 : RW_SEAL, seal);
	col = mix(col, RW_RUBBER, rub);
	float metal = 0.0;
	if (runway_detail >= 2 && nf > 0.0 && (cl_lights || tdz_lights.x + tdz_lights.y > 0.0)) {
		float lens;
		float ring = rw_fittings(along, across, s, x, end_i, hx, lens);
		col = mix(mix(col, RW_FITTING, ring), vec3(0.05, 0.05, 0.055), lens);
		metal = ring * 0.6;  // albedo-side only: keeps the prepass free of the fitting maths
	}
	vec2 rip = rr_grad(v_en, TIME, v_dist, length(fwidth(v_en))) * wetness;  // rain rings (rain_ripples)
	dn += vec3(rip.x, 0.0, -rip.y);
	col *= mix(1.0, 0.65, wetness);  // wet pavement darkens and turns glossy (as strip.gdshaderinc)
	rough = mix(rough, rough * 0.3, wetness);
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = haze_color(-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * haze;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = metal;
	SPECULAR = mix(0.2, 0.5, wetness) * (1.0 - haze);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(dn, 0.0)).xyz * (1.0 - haze));
}
