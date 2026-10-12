// Runway / taxiway surface with procedural markings (shared by runway.gdshader and
// taxiway.gdshader; the taxiway variant defines TAXI_FADE and fades out with distance).
// UV.x: 0..1 across the width, UV.y: metres along the centreline.
// Pulled slightly toward the camera so it never z-fights the terrain under it, and lifted
// with distance (lod_lift rad, ~0.7 px): coarser terrain LODs deviate from the strip by
// metres (p99 ~3 m at level 0, ~4.5 m at level 2, see tools/17_airport_fixups.py), and a
// view-space pull alone gives only ~0.15 % x camera height of vertical margin at grazing angles.

uniform bool is_runway = true;
uniform float length_m = 1000.0;
uniform float width_m = 45.0;
uniform vec3 asphalt : source_color = vec3(0.17, 0.17, 0.18);
uniform vec3 paint : source_color = vec3(0.92, 0.92, 0.9);
uniform vec3 taxi_paint : source_color = vec3(0.95, 0.75, 0.15);
uniform float lod_lift = 0.0007;
global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;
varying float v_dist;

void vertex() {
	VERTEX.y += length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD) * lod_lift;
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

void fragment() {
	float across = (UV.x - 0.5) * width_m;  // metres from centreline
	float along = UV.y;
	float aa_x = fwidth(across) * 0.75;
	vec3 col = asphalt;
	// subtle wear / tyre marks
	col *= 0.92 + 0.08 * sin(along * 0.37 + sin(along * 0.051) * 4.0) * sin(across * 1.3);
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
	EMISSION = fog_color * haze;
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
