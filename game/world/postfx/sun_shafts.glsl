#[versions]

mask = "#define MODE_MASK";
comp_fp16 = "#define MODE_COMP\n#define COLOR_FMT rgba16f";
comp_rgb10 = "#define MODE_COMP\n#define COLOR_FMT rgb10_a2";

#[compute]
#version 450

#VERSION_DEFINES

// Screen-space sun shafts (world/postfx/sun_shafts_effect.gd). Two passes:
//  mask  (quarter resolution): bright open sky around the sun. Only pixels with empty depth (sky, reverse-Z 0)
//        count, so terrain, the aircraft and the cockpit frame occlude; this runs after the transparent pass, so a
//        cloud in front of the sun darkens the sky colour and occludes too, and gaps between clouds shine through.
//  comp  (full resolution): radial blur of the mask towards the sun's screen position, added to the colour in
//        place (each pixel reads only the mask and its own colour). comp_rgb10 is the Mobile colour buffer format,
//        where the renderer stores colour at half range (lum_scale 0.5).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
	vec2 size;       // size of the image this pass writes
	vec2 sun_uv;     // sun on screen (may be off screen)
	vec3 sun_color;
	float strength;
	float threshold; // sky luminance that starts to count as bright
	float lum_scale; // 1 Forward+, 0.5 Mobile (half-range colour buffer)
	float aspect;
	float samples;
} pc;

#ifdef MODE_MASK
layout(set = 0, binding = 0) uniform sampler2D color_tex;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(r16f, set = 0, binding = 2) uniform restrict writeonly image2D mask_img;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(pc.size.x) || px.y >= int(pc.size.y)) {
		return;
	}
	vec2 uv = (vec2(px) + 0.5) / pc.size;
	float d = textureLod(depth_tex, uv, 0.0).r;
	float m = 0.0;
	if (d <= 0.0) {
		vec3 c = textureLod(color_tex, uv, 0.0).rgb / pc.lum_scale;
		float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
		vec2 off = (uv - pc.sun_uv) * vec2(pc.aspect, 1.0);
		m = smoothstep(pc.threshold, pc.threshold * 4.0, lum) * exp(-dot(off, off) * 6.0);  // the sun's surroundings
	}
	imageStore(mask_img, px, vec4(m));
}
#endif

#ifdef MODE_COMP
layout(set = 0, binding = 0) uniform sampler2D mask_tex;
layout(COLOR_FMT, set = 0, binding = 1) uniform restrict image2D color_img;

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(pc.size.x) || px.y >= int(pc.size.y)) {
		return;
	}
	vec2 uv = (vec2(px) + 0.5) / pc.size;
	int n = int(pc.samples);
	vec2 step_uv = (pc.sun_uv - uv) * 0.85 / float(n);  // rays reach most of the way to the sun
	vec2 p = uv + step_uv * ign(vec2(px));
	float acc = 0.0;
	float decay = 1.0;
	for (int i = 0; i < n; i++) {
		acc += textureLod(mask_tex, p, 0.0).r * decay;
		decay *= 0.955;
		p += step_uv;
	}
	acc /= float(n);
	vec4 c = imageLoad(color_img, px);
	c.rgb += pc.sun_color * (acc * pc.strength * pc.lum_scale);
	imageStore(color_img, px, c);
}
#endif
