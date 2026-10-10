shader_type spatial;
render_mode fog_disabled;
// Runway / taxiway surface with procedural markings.
// UV.x: 0..1 across the width, UV.y: metres along the centreline.
// Pulled slightly toward the camera so it never z-fights the terrain under it.

uniform bool is_runway = true;
uniform float length_m = 1000.0;
uniform float width_m = 45.0;
uniform vec3 asphalt : source_color = vec3(0.17, 0.17, 0.18);
uniform vec3 paint : source_color = vec3(0.92, 0.92, 0.9);
uniform vec3 taxi_paint : source_color = vec3(0.95, 0.75, 0.15);

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= 0.9985;
	POSITION = PROJECTION_MATRIX * vp;
}

float band(float x, float c, float hw) {
	float aa = fwidth(x) * 0.75;
	return smoothstep(c - hw - aa, c - hw + aa, x) - smoothstep(c + hw - aa, c + hw + aa, x);
}

void fragment() {
	float across = (UV.x - 0.5) * width_m;  // metres from centreline
	float along = UV.y;
	vec3 col = asphalt;
	// subtle wear / tyre marks
	col *= 0.92 + 0.08 * sin(along * 0.37 + sin(along * 0.051) * 4.0) * sin(across * 1.3);
	float m = 0.0;
	if (is_runway) {
		float from_end = min(along, length_m - along);
		// centreline: 30 m dashes, 20 m gaps, outside the threshold zone
		if (from_end > 60.0 && mod(along, 50.0) < 30.0)
			m = max(m, band(across, 0.0, 0.45));
		// edge lines
		m = max(m, band(abs(across), width_m * 0.5 - 1.2, 0.45));
		// threshold piano keys
		if (from_end > 6.0 && from_end < 36.0) {
			float k = mod(abs(across) + 0.9, 3.6);
			if (abs(across) > 1.8 && abs(across) < width_m * 0.5 - 3.0)
				m = max(m, band(k, 1.8, 0.9));
		}
		// aiming point blocks at 300 m
		if (from_end > 300.0 && from_end < 345.0)
			m = max(m, band(abs(across), 6.0, 2.5));
	} else {
		m = band(across, 0.0, 0.08);
		col = mix(col, taxi_paint, m);
		m = 0.0;
	}
	ALBEDO = mix(col, paint, m * 0.9);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
