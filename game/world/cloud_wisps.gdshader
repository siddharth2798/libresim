shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Cloud wisps: soft streaks fixed in the air mass that stream past the camera inside cloud (a motion cue).
// Each instance of a QuadMesh MultiMesh is placed by a hash of its id inside a box that wraps around the
// camera (so the wisps are static in the air and the camera flies through them), stretched along the
// relative wind and turned to face the camera. No particle simulation: only uniforms change per frame.

uniform vec3 cam_air = vec3(0.0);  // camera ENU in the air-mass frame (position + cloud drift), m
uniform vec3 flow = vec3(0.0, 0.0, 1.0);  // air velocity relative to the aircraft, render frame, m/s
uniform float half_len = 3.0;  // m
uniform float strength = 0.0;  // peak opacity
uniform vec3 tint : source_color = vec3(0.6);
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
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 axis = length(flow) > 0.5 ? normalize(flow) : normalize(vec3(s2.x - 0.5, 0.2, s2.y - 0.5));
	vec3 to_c = rel_r / max(dist, 1e-3);
	vec3 side = normalize(cross(axis, to_c) + vec3(1e-5));
	float size = 0.6 + s2.x;
	vec3 p = cam + rel_r + axis * (VERTEX.x * 2.0 * half_len * size) + side * (VERTEX.y * 2.0 * (0.9 + 1.8 * s2.y) * size);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_a = strength * (1.0 - smoothstep(0.7, 1.0, edge)) * smoothstep(2.0, 10.0, dist) * (0.4 + 0.6 * s2.z);
	v_b = mix(0.72, 1.28, s.z);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = max(1.0 - dot(q, q), 0.0);
	ALBEDO = tint * v_b;
	ALPHA = a * a * v_a;
}
