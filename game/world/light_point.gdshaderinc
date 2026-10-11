// Aerodrome light point: one camera-facing quad per MultiMesh instance.
// Per instance (see world/light_set.gd):
//   COLOR.rgb  light colour, COLOR.a size scale
//   CUSTOM.xy  beam direction in render x/z (0,0 = omnidirectional)
//   CUSTOM.z   lobe exponent + spill fraction (negative = bidirectional)
//   CUSTOM.w   mode: 0 steady, 1+phase sequenced flasher (2 Hz), 2+phase wig-wag (1 Hz),
//              3+phase rotating beacon (12 rpm), 10+angle PAPI unit (white above angle, red below)
// The quad keeps a minimum pixel size, grows with distance up to a cap, and is drawn
// at the depth of its centre (pulled toward the camera) so coarse terrain LODs and the
// ground under a light never clip half of its glow.
global uniform float haze_density;
global uniform vec3 fog_color;

uniform float level = 1.0;    // group intensity 0..1 (day / night / visibility)
uniform float gain = 2.5;     // HDR multiplier of the core (glow threshold is 1.2)
uniform float base_m = 0.5;   // physical glow diameter close up
uniform float min_px = 2.2;   // smallest on-screen core size
uniform float max_m = 40.0;   // cap of the core diameter
uniform float halo = 0.25;    // halo strength

varying vec4 v_col;
varying float v_fog;

const vec3 PAPI_RED = vec3(1.0, 0.08, 0.04);
const vec3 PAPI_WHITE = vec3(1.0, 0.97, 0.92);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - wp;
	float dist = max(length(to_cam), 0.1);
	vec3 col = COLOR.rgb;
	float k = 1.0;
	vec2 f = INSTANCE_CUSTOM.xy;
	vec2 h = normalize(to_cam.xz + vec2(1e-4, 0.0));
	if (dot(f, f) > 0.01) {
		float lobe = abs(INSTANCE_CUSTOM.z);
		float spill = fract(lobe);
		float c = dot(normalize(f), h);
		if (INSTANCE_CUSTOM.z < 0.0) c = abs(c);
		// beams are aimed a few degrees up: from far above they fade a little
		k = spill + (1.0 - spill) * pow(max(c, 0.0), floor(lobe));
	}
	float m = INSTANCE_CUSTOM.w;
	if (m >= 10.0) {
		float el = degrees(asin(clamp(to_cam.y / dist, -1.0, 1.0)));
		col = mix(PAPI_RED, PAPI_WHITE, smoothstep(m - 10.0 - 0.03, m - 10.0 + 0.03, el));
	} else if (m >= 3.0) {
		float a = TIME * 1.2566 + fract(m) * 6.2832;  // 12 rpm
		float c = dot(vec2(sin(a), cos(a)), h);
		k = pow(max(c, 0.0), 24.0) * 1.6 + 0.02;
	} else if (m >= 2.0) {
		float s = fract(TIME - fract(m));
		k *= smoothstep(0.0, 0.06, s) * (1.0 - smoothstep(0.44, 0.5, s));
	} else if (m >= 1.0) {
		float s = fract(TIME * 2.0 - fract(m));
		k *= exp(-s * 28.0) * 2.0;
	}
	float trans = exp(-dist * haze_density * 2.0);  // lights outrange objects (Allard) but fade in haze
	// far lights read dimmer, but a point source never quite vanishes before the haze takes it
	float att = mix(1.0, 0.6, smoothstep(400.0, 12000.0, dist));
	float e = k * level * trans * att;
	float px_m = dist * 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);  // metres per pixel (P11 < 0: y flip)
	float sz = clamp(min_px * px_m, base_m, max_m) * COLOR.a;
	sz *= 1.0 + 0.8 * (1.0 - trans);  // scattering halo in haze
	sz *= mix(0.45, 1.0, level);  // by day (low level) lights are small points, not glare blobs
	if (e < 0.004) sz = 0.0;  // degenerate quad: nothing rasterised
	v_col = vec4(col, e);
	v_fog = 1.0 - trans;
	vec3 vc = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	float pull = min(2.0 + 0.012 * dist + sz, dist * 0.5);
	vc *= 1.0 - pull / dist;
	POSITION = PROJECTION_MATRIX * vec4(vc, 1.0);
	POSITION.xy += VERTEX.xy * 2.5 * sz * vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]) * POSITION.w / dist;
}
