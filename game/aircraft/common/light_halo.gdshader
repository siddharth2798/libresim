shader_type spatial;
// Halo of an aircraft light (aircraft_lights.gd, light_parts.gd): one camera-facing quad per light in the
// world/light_set.gd instance layout (COLOR.rgb colour, COLOR.a size scale; no beam, no flash modes, the script
// drives `level`). Like world/light_point.gdshader it keeps a minimum pixel size and grows with distance, but:
// it is pulled toward the camera only by about its own size (enough that the skin around a bulb does not clip
// it, not so much that a light on the far side shows through the airframe close up), and the glow falls to
// zero inside the quad, so a bright strobe or a close-up never shows the square edge.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

global uniform float haze_density;

uniform float level = 0.0;    // 0..1+ (switch, flash, night)
uniform float gain = 2.5;     // HDR multiplier of the core
uniform float base_m = 0.35;  // physical glow diameter close up
uniform float min_px = 3.0;   // smallest on-screen core size
uniform float max_m = 30.0;   // cap of the core diameter
uniform float halo = 0.45;    // halo strength

varying vec4 v_col;
varying float v_fog;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = max(length(INV_VIEW_MATRIX[3].xyz - wp), 0.1);
	float trans = exp(-dist * haze_density * 2.0);
	float att = mix(1.0, 0.6, smoothstep(400.0, 12000.0, dist));
	float e = level * trans * att;
	float px_m = dist * 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float sz = clamp(min_px * px_m, base_m, max_m) * COLOR.a;
	sz *= 1.0 + 0.8 * (1.0 - trans);
	sz *= mix(0.45, 1.0, clamp(level, 0.0, 1.0));
	if (e < 0.004) sz = 0.0;
	v_col = vec4(COLOR.rgb, e);
	v_fog = 1.0 - trans;
	vec3 vc = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	float pull = min(0.08 + 0.6 * sz + 0.004 * dist, dist * 0.5);
	vc *= 1.0 - pull / dist;
	POSITION = PROJECTION_MATRIX * vec4(vc, 1.0);
	POSITION.xy += VERTEX.xy * 2.5 * sz * vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]) * POSITION.w / dist;
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	float win = 1.0 - smoothstep(0.45, 1.0, r2);
	float core = exp(-r2 * 9.0);
	float glow = exp(-r2 * 4.0) * (halo + v_fog * 0.5);
	vec3 c = v_col.rgb * v_col.a;
	ALBEDO = (c * core * gain + c * glow + vec3(core * core * v_col.a * gain * 0.2)) * win;
	ALPHA = 1.0;
}
