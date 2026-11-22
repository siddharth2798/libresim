shader_type canvas_item;
render_mode blend_disabled, unshaded;
// RunwayBake: one pass over a whole runway (UV.x 0..1 across, UV.y 0..1 along from ends[0]) writing the static,
// seed-deterministic layers of runway_v2.gdshader into RGBA8, box-filtered over one texel (hx, hs), so the runway
// shader reads them with one mipmapped fetch at any distance. R: bare pavement albedo x 4 (tone, lanes, patches,
// slabs, wheel tracks, oil), G: sealant / joint coverage, B: rubber stain, A: paint coverage (worn, far average).
uniform bool is_runway = true;
uniform float length_m = 1000.0;
uniform float width_m = 45.0;
uniform float seed = 0.0;
uniform float gear_hw = 4.3;
uniform int runway_detail = 3;  // the bake draws every static layer (cracks, block cracks, patches), averaged per texel
uniform vec2 texel_m = vec2(0.2, 0.5);  // metres per texel (across, along)

#include "res://world/runway_surface.gdshaderinc"
#include "res://world/runway_marks.gdshaderinc"
#include "res://world/runway_wear.gdshaderinc"
#include "res://world/runway_cracks.gdshaderinc"

void fragment() {
	float across = (UV.x - 0.5) * width_m;
	float along = UV.y * length_m;
	float hx = texel_m.x * 0.5, hs = texel_m.y * 0.5;
	bool far_end = along > length_m * 0.5;
	int end_i = far_end ? 1 : 0;
	float s = far_end ? length_m - along : along;
	float x = far_end ? -across : across;
	bool concrete = surface == 1 || s < concrete_ends_m;
	vec3 col = rw_base(concrete, across, along);
	float seal = 0.0;
	if (concrete) {
		col *= rw_slabs(across, along, hx, hs, seal);
	} else {
		float border;
		col *= rw_lane_tone(across, along) * rw_patch(across, along, hx, hs, border);
		seal = max(rw_sealant(across, along, hx, hs), border);
	}
	col *= 1.0 - rw_tracks(s, x);
	col = mix(col, RW_OIL, rw_oil(along, across, s, hx, hs));
	vec2 g = vec2(texel_m.x, 0.0) * (far_end ? -1.0 : 1.0);
	float paint = rw_paint(s, x, across, along, end_i, hx, hs, g, vec2(0.0, texel_m.y)) * rw_paint_left(s, x, hx, hs, 1.0);
	COLOR = vec4(clamp(col.g * 4.0, 0.0, 1.0), seal, rw_stain(s, x, end_i), paint);
}
