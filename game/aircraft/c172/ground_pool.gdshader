shader_type spatial;
// Pool of landing / taxi light on the ground ahead of the aircraft: an additive warm
// gradient on a flat quad laid on the ground (UV.y 0 = near end, 1 = far end). A grazing
// spot light alone barely lifts dark asphalt, while the eye sees a clear lit patch.
// Pulled toward the camera like world/runway.gdshader so it sits on top of the runway.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

global uniform float haze_density;

uniform vec3 tint : source_color = vec3(1.0, 0.93, 0.8);
uniform float level = 0.0;
uniform float peak = 0.3;  // where along the pool it is brightest (0..1)

varying float v_trans;

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_trans = exp(-length(vp.xyz) * haze_density * 1.6);
	vp.xyz *= 0.996;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float y = UV.y;
	float along = smoothstep(0.0, peak, y) * (1.0 - smoothstep(peak, 1.0, y));
	float across = exp(-x * x * 3.0) * (1.0 - smoothstep(0.75, 1.0, abs(x)));
	ALBEDO = tint * level * along * along * across * v_trans;
	ALPHA = 1.0;
}
