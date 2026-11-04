shader_type canvas_item;
render_mode unshaded;
// Final screen pass (world/postfx/screen_post.gd), drawn by a CanvasLayer below all UI: after tonemapping, TAA and
// the 3D upscale, on any renderer. A compositor effect cannot run after TAA in Godot 4.7, so sharpening is here.
//  sharpen  contrast-adaptive sharpening (after AMD FidelityFX CAS): less where the local contrast is already high
//  lens     vignette + slight chromatic aberration + film grain (one option, "lens_effects")
//  rain     drops on an outside camera's lens (lens_rain.gdshaderinc)
// Each part is skipped when its amount is 0; the node hides itself when all are 0 (no screen copy then).

#include "res://world/postfx/lens_rain.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float sharpen = 0.0;   // 0..1 (CAS "sharpness")
uniform float vignette = 0.0;  // darkening at the corners, 0..1
uniform float aberration = 0.0;  // radial colour split at the corners, in UV
uniform float grain = 0.0;     // film grain amplitude
uniform float rain = 0.0;      // lens rain amount 0..1
uniform float rain_speed = 0.0;  // m/s

vec3 tap(vec2 uv) {
	return textureLod(screen_tex, uv, 0.0).rgb;
}

vec3 cas(vec2 uv, vec2 px, vec3 e) {
	vec3 b = tap(uv + vec2(0.0, -px.y));
	vec3 d = tap(uv + vec2(-px.x, 0.0));
	vec3 f = tap(uv + vec2(px.x, 0.0));
	vec3 h = tap(uv + vec2(0.0, px.y));
	vec3 mn = min(min(min(d, e), min(f, b)), h);
	vec3 mx = max(max(max(d, e), max(f, b)), h);
	vec3 amp = sqrt(clamp(min(mn, 2.0 - mx) / max(mx, vec3(1e-4)), 0.0, 1.0));
	vec3 w = amp * (-1.0 / mix(8.0, 5.0, sharpen));
	return clamp((b * w + d * w + f * w + h * w + e) / (1.0 + 4.0 * w), 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	float shade = 0.0;
	if (rain > 0.001) {
		vec4 r = lens_rain(uv, aspect, rain, rain_speed, TIME);
		uv += r.xy * r.w;
		shade = r.z * r.w;
	}
	vec3 col = tap(uv);
	if (aberration > 0.0) {
		vec2 c = uv - 0.5;
		vec2 o = c * dot(c, c) * aberration;
		col = vec3(tap(uv + o).r, col.g, tap(uv - o).b);
	}
	if (sharpen > 0.001) {
		col = cas(uv, px, col);
	}
	col *= 1.0 - 0.35 * shade;  // darker drop rims
	if (vignette > 0.0) {
		vec2 c = SCREEN_UV - 0.5;
		col *= 1.0 - vignette * smoothstep(0.3, 1.0, dot(c, c) * 2.0);  // 0 at the centre, 1 in the corners
	}
	if (grain > 0.0) {
		float n = fract(sin(dot(FRAGCOORD.xy + fract(TIME * 13.7) * 91.0, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
		float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col += n * grain * (1.0 - 0.6 * l);  // grain shows most in the mid tones and shadows
	}
	COLOR = vec4(col, 1.0);
}
