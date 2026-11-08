#[compute]
#version 450
// Per-pixel motion blur (world/postfx/motion_blur_effect.gd), run after the transparent pass so the raymarched
// clouds blur with the rest. Motion per pixel, in UV units of this frame minus the previous one:
//  - the renderer's velocity buffer (Forward+ motion vectors: camera and object motion), else
//  - camera-only reprojection from depth: sky pixels (depth 0, reverse-Z) and far pixels that wrote no motion.
//    Pixels nearer than near_cut (the aircraft and its cockpit) never get the reprojection.
// Samples are centred on the pixel (so the sign of the motion does not matter) and depth-aware: a nearer sample
// (the aircraft, the cockpit frame) only counts if its own motion reaches this pixel, so a sharp foreground never
// smears onto the background behind it.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D color_tex;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform sampler2D velocity_tex;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D out_img;
layout(set = 0, binding = 4, std140) uniform Reproj {
	mat4 inv_proj;  // current projection (GL convention), inverted
	mat4 to_prev;   // current view space -> previous clip space
} rp;

layout(push_constant, std430) uniform Params {
	vec2 size;
	float scale;        // blur length per unit of per-frame motion (shutter, frame-time normalised)
	float max_px;       // blur length cap in pixels
	float samples;
	float near_cut;     // m: no reprojection nearer than this. Negative (cockpit view): nearer pixels never blur at all
	float use_velocity; // 1 = Forward+ velocity buffer present
	float flip_y;       // 1: texel row 0 is the top of the view (GL ndc y up)
} pc;

vec2 ndc_xy(vec2 uv) {
	return vec2(uv.x * 2.0 - 1.0, pc.flip_y > 0.5 ? 1.0 - 2.0 * uv.y : uv.y * 2.0 - 1.0);
}

// Linear view distance along -z of a depth-buffer value (reverse-Z [0, 1] -> GL ndc z = 1 - 2 d).
float lin_depth(float d) {
	float z = 1.0 - 2.0 * d;
	float vz = rp.inv_proj[2][2] * z + rp.inv_proj[3][2];
	float vw = rp.inv_proj[2][3] * z + rp.inv_proj[3][3];
	return -vz / vw;
}

float depth_at(vec2 uv) {
	float d = textureLod(depth_tex, uv, 0.0).r;
	return d <= 0.0 ? 1e9 : lin_depth(d);
}

// Camera-only motion of the pixel at uv: where it was on screen last frame (sky: direction only, w = 0).
vec2 reproject(vec2 uv, float d) {
	bool sky = d <= 0.0;
	vec4 v = rp.inv_proj * vec4(ndc_xy(uv), sky ? 1.0 : 1.0 - 2.0 * d, 1.0);
	vec3 p = v.xyz / v.w;
	vec4 c = rp.to_prev * vec4(p, sky ? 0.0 : 1.0);
	if (c.w <= 1e-6) {
		return vec2(0.0);
	}
	vec2 n = c.xy / c.w;
	vec2 prev_uv = vec2(n.x * 0.5 + 0.5, pc.flip_y > 0.5 ? 0.5 - 0.5 * n.y : n.y * 0.5 + 0.5);
	return uv - prev_uv;
}

float ign(vec2 p) {  // interleaved gradient noise: per-pixel sample offset, hides the steps
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(pc.size.x) || px.y >= int(pc.size.y)) {
		return;
	}
	vec2 uv = (vec2(px) + 0.5) / pc.size;
	vec4 c0 = textureLod(color_tex, uv, 0.0);
	float d = texelFetch(depth_tex, px, 0).r;
	float dc = d <= 0.0 ? 1e9 : lin_depth(d);
	float near_cut = abs(pc.near_cut);
	bool rigid_near = pc.near_cut < 0.0;
	if (rigid_near && dc < near_cut) {
		// Cockpit view: the cockpit and the aircraft ride with the camera, so they do not move on screen. The velocity
		// buffer is not trusted here: some frames it carried a whole frame of the aircraft's travel and smeared the panel.
		imageStore(out_img, px, c0);
		return;
	}
	vec2 vel = pc.use_velocity > 0.5 ? texelFetch(velocity_tex, px, 0).xy : vec2(0.0);
	if (d <= 0.0 || (dot(vel, vel) == 0.0 && dc > near_cut)) {
		vel = reproject(uv, d);
	}
	vec2 vpx = vel * pc.size * pc.scale;
	float len = length(vpx);
	if (len < 0.5) {
		imageStore(out_img, px, c0);
		return;
	}
	if (len > pc.max_px) {
		vpx *= pc.max_px / len;
		len = pc.max_px;
	}
	int n = int(pc.samples);
	float jit = ign(vec2(px)) - 0.5;
	float tol = dc * 0.05 + 0.5;
	vec4 acc = c0;
	float wsum = 1.0;
	for (int i = 0; i < n; i++) {
		float t = (float(i) + 0.5 + jit) / float(n) - 0.5;  // -0.5 .. 0.5 along the motion
		vec2 suv = uv + t * vpx / pc.size;
		float ds = depth_at(suv);
		float w = 1.0;
		if (ds < dc - tol) {  // a nearer sample: only if its own motion covers this pixel
			vec2 sv = pc.use_velocity > 0.5 && !(rigid_near && ds < near_cut) ? textureLod(velocity_tex, suv, 0.0).xy : vec2(0.0);
			w = step(abs(t) * len, length(sv * pc.size * pc.scale));
		}
		acc += w * textureLod(color_tex, suv, 0.0);
		wsum += w;
	}
	imageStore(out_img, px, vec4((acc / wsum).rgb, c0.a));
}
