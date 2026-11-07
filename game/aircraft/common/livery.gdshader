shader_type canvas_item;
render_mode blend_disabled;
// One-shot livery pass (livery_paint.gd): the atlas recoloured under up to four region masks, one texel to one pixel.
// The same arithmetic as Livery.recolor_multi (livery.gd explains the rule): sRGB values as stored, Rec.709 luma, the
// weights of the regions added up, each region keeping the shading left after the others' share is removed. Gain above
// 1 is scaled by how bright the new colour is against the region's luma, so a dark colour does not light a grey tip.
// blend_disabled writes the colour and alpha as they are (no premultiplied blend into the viewport).
uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform sampler2D mask0 : filter_nearest, repeat_disable;
uniform sampler2D mask1 : filter_nearest, repeat_disable;
uniform sampler2D mask2 : filter_nearest, repeat_disable;
uniform sampler2D mask3 : filter_nearest, repeat_disable;
uniform vec3 colour0;
uniform vec3 colour1;
uniform vec3 colour2;
uniform vec3 colour3;
uniform vec4 lumas = vec4(1.0);  // luma_base of each slot (an unused slot has a black mask: weight 0)
const float GAIN_MAX = 1.3;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec4 o = texture(atlas, UV);
	vec4 m = clamp(vec4(texture(mask0, UV).r, texture(mask1, UV).r, texture(mask2, UV).r, texture(mask3, UV).r), 0.0, 1.0);
	float total = m.x + m.y + m.z + m.w;
	vec4 w = m / max(total, 1.0);
	float wn = min(total, 1.0);
	float l = luma(o.rgb);
	vec3 cols[4] = vec3[4](colour0, colour1, colour2, colour3);
	float lb[4] = float[4](lumas.x, lumas.y, lumas.z, lumas.w);
	float wa[4] = float[4](w.x, w.y, w.z, w.w);
	vec3 rgb = o.rgb * (1.0 - wn);
	for (int i = 0; i < 4; i++) {
		float others = 0.0;
		for (int j = 0; j < 4; j++) {
			if (j != i) {
				others += wa[j] * lb[j];
			}
		}
		float li = max((l * wn - others) / max(wa[i], 0.001), 0.0);
		float raw = clamp(li / max(lb[i], 0.0001), 0.0, GAIN_MAX);
		float room = clamp(luma(cols[i]) / max(lb[i], 0.0001), 0.0, 1.0);
		float gain = min(raw, 1.0) + max(raw - 1.0, 0.0) * room;
		rgb += wa[i] * min(cols[i] * gain, vec3(1.0));
	}
	COLOR = vec4(rgb, o.a);
}
