shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// One rain streak per particle (world/rain_particles.gd): a thin camera-facing quad along
// the particle's velocity (the particle's Y axis, align_y), fading at the ends and near
// the camera (so nothing is drawn inside the cockpit) and with distance.

uniform float streak_len = 0.5;   // m
uniform float width = 0.016;      // m
uniform vec3 tint : source_color = vec3(0.7, 0.72, 0.75);
uniform float alpha = 0.3;
uniform float near_fade = 1.6;    // m: no streaks closer than this
global uniform float haze_density;

varying float v_fade;

void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	float d = length(to_cam);
	vec3 side = normalize(cross(axis, to_cam / max(d, 1e-3)));
	// a little wider far away so distant streaks stay ~1 px instead of shimmering
	float w = width * (1.0 + d * 0.03);
	vec3 wp = center + side * VERTEX.x * w + axis * VERTEX.y * streak_len;
	v_fade = smoothstep(near_fade, near_fade + 1.0, d) * (1.0 - smoothstep(14.0, 20.0, d)) * exp(-d * haze_density);
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(UV.y * 3.14159);
	ALBEDO = tint;
	ALPHA = alpha * v_fade * across * along;
}
