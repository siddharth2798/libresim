shader_type spatial;
// Additive aerodrome light points (runway, approach, taxiway, stop bars, beacon).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://world/light_point.gdshaderinc"

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	float core = exp(-r2 * 9.0);
	float glow = exp(-r2 * 4.0) * (halo + v_fog * 0.5);
	vec3 c = v_col.rgb * v_col.a;
	ALBEDO = c * core * gain + c * glow + vec3(core * core * v_col.a * gain * 0.2);
	ALPHA = 1.0;
}
