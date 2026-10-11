shader_type spatial;
// Opaque-cored light points that stay saturated in daylight (PAPI): blended, not added.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://world/light_point.gdshaderinc"

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	float core = exp(-r2 * 10.0);
	float glow = exp(-r2 * 3.5) * (halo + v_fog * 0.5);
	ALBEDO = v_col.rgb * gain * mix(1.0, 0.6, glow / max(core + glow, 1e-3));
	ALPHA = clamp((core * 1.6 + glow) * min(v_col.a, 1.0), 0.0, 1.0);
}
