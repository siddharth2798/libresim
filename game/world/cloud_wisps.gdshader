shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Cloud wisps: faint, short streaks fixed in the air mass that flow past the camera inside cloud (a motion cue,
// not a star-field). Each instance of a QuadMesh MultiMesh is placed by a hash of its id inside a box that wraps
// around the camera (static in the air, the camera flies through them). Each is a screen-aligned strip in view
// space along the screen-space direction of the relative wind, flattened towards the horizontal so the strips
// sweep past instead of radiating from a point; they fade out in the middle of the picture and around the
// aircraft, and distant ones are fainter. Fades mirror CloudLook.wisp_screen_fade / wisp_depth_fade.

uniform vec3 cam_air = vec3(0.0);  // camera ENU in the air-mass frame (position + cloud drift), m
uniform vec3 flow = vec3(0.0, 0.0, 1.0);  // air velocity relative to the aircraft, render frame, m/s
uniform float half_len = 2.0;  // m
uniform float strength = 0.0;  // peak opacity
uniform vec3 tint : source_color = vec3(0.6);
uniform vec3 subject = vec3(0.0);  // aircraft position on screen (ndc x, y) and weight (0: fade around the centre only)
uniform vec3 box = vec3(220.0, 220.0, 120.0);  // m, the wrapping volume (ENU)

varying float v_a;
varying float v_b;

vec3 h3(float n) {
	return fract(sin(vec3(n * 12.9898, n * 78.233, n * 37.719)) * 43758.5453);
}

void vertex() {
	vec3 s = h3(float(INSTANCE_ID) + 1.0);
	vec3 s2 = h3(float(INSTANCE_ID) + 101.0);
	vec3 rel = (fract(s - cam_air / box) - 0.5) * box;  // ENU, camera relative
	float edge = max(max(abs(rel.x) / box.x, abs(rel.y) / box.y), abs(rel.z) / box.z) * 2.0;
	vec3 rel_r = vec3(rel.x, rel.z, -rel.y);  // render frame
	float dist = length(rel_r);
	vec3 cv = (VIEW_MATRIX * vec4(INV_VIEW_MATRIX[3].xyz + rel_r, 1.0)).xyz;  // view space
	vec3 fv = (VIEW_MATRIX * vec4(flow, 0.0)).xyz;
	vec2 sd = (fv.xy * cv.z - fv.z * cv.xy) * vec2(1.0, 0.35);  // screen direction of the flow here, flattened
	sd = length(sd) > 1e-4 ? normalize(sd) : vec2(1.0, 0.0);
	vec3 axis = vec3(sd, 0.0);
	vec3 side = vec3(-sd.y, sd.x, 0.0);
	float len = half_len * (0.5 + 1.1 * s2.x);
	float wid = (0.7 + 1.4 * s2.y) * (0.6 + s2.x);
	vec3 p = cv + axis * (VERTEX.x * 2.0 * len) + side * (VERTEX.y * 2.0 * wid);
	POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
	vec4 clip = PROJECTION_MATRIX * vec4(cv, 1.0);
	vec2 asp = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	vec2 ndc = clip.xy / max(abs(clip.w), 1e-3);
	float mid = smoothstep(0.12, 0.45, length(ndc * asp));  // not in the middle of the picture
	float around = smoothstep(0.2, 0.65, length((ndc - subject.xy) * asp));  // not around the aircraft
	float screen = mix(mid, min(mid, around), subject.z);
	float far = mix(1.0, 0.4, smoothstep(15.0, 90.0, dist));  // distant ones fainter
	v_a = cv.z < 0.0 ? strength * screen * far * (1.0 - smoothstep(0.7, 1.0, edge)) * smoothstep(3.0, 12.0, dist) * (0.25 + 0.75 * s2.z * s2.z) : 0.0;
	v_b = mix(0.75, 1.25, s.z);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = max(1.0 - dot(q, q), 0.0);
	ALBEDO = tint * v_b;
	ALPHA = a * a * v_a;
}
