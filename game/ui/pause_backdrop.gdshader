shader_type canvas_item;
// Pause screen backdrop (ui/pause_menu.gd): the frozen frame behind it, softly blurred (a mipmap
// level plus four offset taps), slightly desaturated and dimmed toward a cool dark, with a
// vignette and a darker left edge under the menu. The scene stays recognisable.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 6.0) = 1.8;
uniform float dim : hint_range(0.0, 1.0) = 0.3;
uniform float vignette : hint_range(0.0, 1.0) = 0.4;
uniform float left_shade : hint_range(0.0, 1.0) = 0.22;
uniform vec3 tint = vec3(0.02, 0.04, 0.08);

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * exp2(blur_lod) * 0.75;
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb * 0.36;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, px.y), blur_lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y), blur_lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y), blur_lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, -px.y), blur_lod).rgb * 0.16;
	c = pow(c, vec3(0.8));  // lift the shadows so a night scene stays readable
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 0.85);
	c = mix(c, tint, dim);
	float d = length((SCREEN_UV - vec2(0.5)) * vec2(1.25, 1.0));
	c *= 1.0 - vignette * smoothstep(0.45, 0.95, d);
	c *= 1.0 - left_shade * (1.0 - smoothstep(0.0, 0.5, SCREEN_UV.x));
	COLOR = vec4(c, 1.0);
}
