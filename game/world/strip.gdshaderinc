// Runway / taxiway surface with procedural markings (shared by runway.gdshader and
// taxiway.gdshader; the taxiway variant defines TAXI_FADE and fades out with distance).
// UV.x: 0..1 across the width, UV.y: metres along the centreline.
// The mesh lies exactly on the terrain (GroundDrape). Pulled slightly toward the camera so it never z-fights
// the terrain under it, and lifted with distance away from the aircraft (lod_lift rad, ~0.7 px,
// ground_lift.gdshaderinc): coarser terrain LODs deviate from the strip by metres (p99 ~3 m at level 0,
// ~4.5 m at level 2, see tools/17_airport_fixups.py), and a view-space pull alone gives only ~0.15 % x
// camera height of vertical margin at grazing angles.
#include "res://world/ground_lift.gdshaderinc"

uniform bool is_runway = true;
uniform float length_m = 1000.0;
uniform float width_m = 45.0;
uniform vec3 asphalt : source_color = vec3(0.36, 0.36, 0.37);  // sRGB ~= 0.11 linear: weathered airport asphalt (0.17 read as black next to the concrete aprons)
uniform vec3 paint : source_color = vec3(0.92, 0.92, 0.9);
uniform vec3 taxi_paint : source_color = vec3(0.95, 0.75, 0.15);
uniform float lod_lift = 0.0007;
global uniform vec3 fog_color;
global uniform float haze_density;
#include "res://world/curvature.gdshaderinc"  // Earth curvature (G4)
#include "res://world/haze_sky.gdshaderinc"  // view-dependent haze colour (G4)
global uniform float wetness;
varying float v_dist;

void vertex() {
	VERTEX.y += ground_lift((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD, lod_lift);
	VERTEX += curve_local(MODEL_MATRIX, curve_drop((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz));
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_dist = length(vp.xyz);
#ifdef LEAD_ON
	vp.xyz *= 0.998;  // pulled more than the runway (0.9985): the line shows on top of it
#elif defined(TAXI_FADE)
	vp.xyz *= 0.999;  // pulled less than runways: where they cross, the runway always wins
#else
	vp.xyz *= 0.9985;
#endif
	POSITION = PROJECTION_MATRIX * vp;
}

// aa = screen-space width of one metre across/along; passed in so that bands on wrapped
// coordinates (mod) don't pick up the huge derivative at the wrap (dotted-line shimmer).
// A band narrower than ~1 px (aa > hw) only aliases (crawling dashes): it fades out instead.
float band(float x, float c, float hw, float aa) {
	float b = smoothstep(c - hw - aa, c - hw + aa, x) - smoothstep(c + hw - aa, c + hw + aa, x);
	return b * (1.0 - smoothstep(hw * 0.6, hw * 1.5, aa));
}

float strip_hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float strip_noise(vec2 p) {  // value noise, 0..1
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(strip_hash(i), strip_hash(i + vec2(1.0, 0.0)), f.x), mix(strip_hash(i + vec2(0.0, 1.0)), strip_hash(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	float across = (UV.x - 0.5) * width_m;  // metres from centreline
	float along = UV.y;
	float aa_x = fwidth(across) * 0.75;
	vec3 col = asphalt;
	// subtle wear / tyre marks
	col *= 0.92 + 0.08 * sin(along * 0.37 + sin(along * 0.051) * 4.0) * sin(across * 1.3);
	// aggregate grain and patchy weathering (faded with distance so it never shimmers)
	vec2 sp = vec2(across, mod(along, 4096.0));
	float near_k = 1.0 - smoothstep(60.0, 400.0, v_dist);
	col *= 1.0 + (strip_noise(sp * 0.13) - 0.5) * 0.22 + (strip_noise(sp * 2.1) - 0.5) * 0.12 * near_k;
	float m = 0.0;
	float line = 0.0;
	if (is_runway) {
		float from_end = min(along, length_m - along);
		// centreline: 30 m dashes, 20 m gaps, outside the threshold zone
		if (from_end > 60.0 && mod(along, 50.0) < 30.0)
			m = max(m, band(across, 0.0, 0.45, aa_x));
		// edge lines
		m = max(m, band(abs(across), width_m * 0.5 - 1.2, 0.45, aa_x));
		// threshold piano keys
		if (from_end > 6.0 && from_end < 36.0) {
			float k = mod(abs(across) + 0.9, 3.6);
			if (abs(across) > 1.8 && abs(across) < width_m * 0.5 - 3.0)
				m = max(m, band(k, 1.8, 0.9, aa_x));
		}
		// aiming point blocks at 300 m
		if (from_end > 300.0 && from_end < 345.0)
			m = max(m, band(abs(across), 6.0, 2.5, aa_x));
	} else {
		m = band(across, 0.0, 0.08, aa_x);
		line = m;
		col = mix(col, taxi_paint, m);
		m = 0.0;
	}
	col = mix(col, paint, m * 0.9) * mix(1.0, 0.65, wetness);  // wet tarmac darkens
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = haze_color(-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * haze;
	ROUGHNESS = mix(0.85, 0.25, wetness);
#ifdef LEAD_ON
	ALPHA = line;
#elif defined(TAXI_FADE)
	// A taxiway a few px wide (far away / edge-on) rasterises as stair-stepped dashes; fade it
	// into the terrain imagery, which already shows the pavement at that size.
	ALPHA = smoothstep(2.0, 6.0, width_m / max(fwidth(across), 1e-4));
#endif
	SPECULAR = mix(0.2, 0.5, wetness) * (1.0 - haze);
}
