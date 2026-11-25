shader_type spatial;
// Warm glow round a jetway's cab door at night: one small camera-facing quad (world/jetway_night.gd), additive, soft round
// falloff, behind the cab and the tunnel (depth tested), switched by the global night_level like the rest of the jetway
// (nothing by day). Hidden with the cab's parts when the far stand-in takes over (JetwayStandin).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

global uniform float night_level;

uniform vec3 warm = vec3(1.0, 0.8, 0.52);
uniform float strength = 0.5;

void vertex() {
	// face the camera, keep the node's position and scale
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * sc.x, 0.0), vec4(INV_VIEW_MATRIX[1].xyz * sc.y, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz, 0.0), MODEL_MATRIX[3]);
}

void fragment() {
	if (night_level <= 0.0) {
		discard;
	}
	float r = length(UV * 2.0 - 1.0);
	float k = 1.0 - smoothstep(0.0, 1.0, r);
	ALBEDO = warm * (k * k * strength * night_level);
	ALPHA = 1.0;
}
