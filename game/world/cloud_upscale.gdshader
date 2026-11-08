shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, blend_mix;
// G7. Two passes, one shader.
// blit = 0 (full-resolution history view): depth-aware upsample of the low-res march, then blend with the
//   previous frame reprojected into this view. Samples are premultiplied (the march blends onto clear).
// blit = 1 (main camera): the same clouds, gathered again with THIS frame's depth so a low-res block does
//   not smear across the aircraft or the terrain. Low / Medium never draw this shader.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D scene_depth : filter_nearest, repeat_disable;
uniform sampler2D current_tex : filter_linear, repeat_disable; // low-res march, premultiplied
uniform sampler2D history_tex : filter_linear, repeat_disable; // previous full-res blend, premultiplied
uniform sampler2D accum_tex : filter_linear, repeat_disable; // this frame's blend, for the sharpen pass
uniform mat4 reproj; // current view space -> previous clip (CloudTemporal.reproj_matrix)
uniform mat4 inv_proj; // camera projection inverse, passed in (a helper cannot read the built-in)
uniform float blit = 0.0;
uniform float blend_w = 1.0; // weight of the new march; 1 discards history
uniform float history_on = 0.0;
uniform float depth_flip = 0.0;
uniform int block = 2; // 2 half, 4 quarter
uniform float clear_m = 0.0; // camera to the cloud slab (CloudTemporal.clear_dist): nearer surfaces get no cloud

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

vec2 depth_uv(vec2 uv) {
	return depth_flip > 0.5 ? vec2(uv.x, 1.0 - uv.y) : uv;
}

float raw_depth(vec2 uv) {
	if (blit > 0.5) {
		return textureLod(depth_tex, uv, 0.0).r;
	}
	return textureLod(scene_depth, depth_uv(uv), 0.0).r;
}

// Screen UV and stored depth to the clip space of `inv_proj` (Camera3D.get_camera_projection(): OpenGL style,
// y up, z -1 near .. 1 far). The depth buffer is reversed (1 near, 0 far / sky) and the screen y runs down.
// Using the stored depth as clip z put the sky at the near plane and scrambled every distance compared here.
vec4 clip_of(vec2 uv) {
	return vec4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 1.0 - 2.0 * raw_depth(uv), 1.0);
}

vec3 view_pos(vec2 uv) {
	vec4 v = inv_proj * clip_of(uv);
	return v.xyz / v.w;
}

float view_dist(vec2 uv) {
	return length(view_pos(uv));
}

// 0 across a depth edge (aircraft against sky, a ridge), 1 on a continuous surface.
float edge(float d0, float d1) {
	float rel = abs(d0 - d1) / max(max(d0, d1), 1.0);
	if (rel > 0.06) {
		return 0.0;
	}
	return exp(-rel * rel * 140.0);
}

vec2 prev_uv(vec2 uv) {
	vec4 c = reproj * vec4(view_pos(uv), 1.0);
	if (c.w <= 1e-5) {
		return vec2(-1.0, -1.0);
	}
	return vec2(c.x / c.w * 0.5 + 0.5, 0.5 - c.y / c.w * 0.5);
}

void fragment() {
	vec4 outc = vec4(0.0);
	if (view_dist(SCREEN_UV) < clear_m) {
		discard; // in front of every cloud (cockpit frame, the aircraft below the layer)
	}
	if (blit > 0.5) {
		vec2 px = 1.0 / max(VIEWPORT_SIZE, vec2(1.0));
		float rad = clamp(float(block) * 0.5, 1.0, 2.0);
		float d0 = view_dist(SCREEN_UV);
		vec4 acc = vec4(0.0);
		float wsum = 0.0;
		vec4 centre = textureLod(accum_tex, SCREEN_UV, 0.0);
		for (int y = -2; y <= 2; y++) {
			for (int x = -2; x <= 2; x++) {
				float outside = max(abs(float(x)), abs(float(y))) > rad ? 1.0 : 0.0;
				vec2 u = SCREEN_UV + vec2(float(x), float(y)) * px;
				float w = (1.0 - outside) * edge(d0, view_dist(u)) * exp(-float(x * x + y * y) * 0.25);
				acc += textureLod(accum_tex, clamp(u, vec2(0.0), vec2(1.0)), 0.0) * w;
				wsum += w;
			}
		}
		outc = wsum > 1e-4 ? acc / wsum : centre;
	} else {
		// 4 x 4 low-res texels around the pixel, weighted by distance and by depth match. With only the
		// 2 x 2 nearest, a pixel on a depth edge (the horizon, the windshield frame against the sky) often
		// matched none of them and took the single nearest texel, which the per-frame march jitter flips
		// between cloud and occluded: the edge blinked.
		vec2 tsize = max(vec2(textureSize(current_tex, 0)), vec2(1.0));
		vec2 texel = 1.0 / tsize;
		vec2 base = (floor(SCREEN_UV * tsize - 0.5) + 0.5) * texel;
		vec2 f = (SCREEN_UV - base) / texel;
		float d0 = view_dist(SCREEN_UV);
		vec4 acc = vec4(0.0);
		float wsum = 0.0;
		vec4 nearest = textureLod(current_tex, SCREEN_UV, 0.0);
		vec4 lo = vec4(1e4);
		vec4 hi = vec4(-1e4);
		float dmin = 1e30;
		for (int y = -1; y <= 2; y++) {
			for (int x = -1; x <= 2; x++) {
				vec2 o = vec2(float(x), float(y));
				vec2 u = clamp(base + o * texel, vec2(0.0), vec2(1.0));
				vec4 s = textureLod(current_tex, u, 0.0);
				vec2 dd = o - f;
				float du = view_dist(u);
				dmin = min(dmin, du);
				float w = edge(d0, du) * exp(-dot(dd, dd) * 1.2);
				acc += s * w;
				wsum += w;
				if (w > 1e-3) {
					lo = min(lo, s);
					hi = max(hi, s);
				}
			}
		}
		bool matched = wsum > 1e-4;
		// Nearer than every texel around it (the windshield frame or the aircraft against the sky): a cloud
		// cannot be in front of it. Taking the nearest texel here painted sky over the frame in low-res blocks.
		bool occluder = !matched && d0 < dmin * 0.94;
		vec4 cur = matched ? acc / wsum : (occluder ? vec4(0.0) : nearest);
		if (!matched) {
			lo = cur;
			hi = cur;
		}
		vec4 pad = (hi - lo) * 0.05 + vec4(0.002);
		outc = cur;
		if (history_on > 0.5 && blend_w < 0.999 && !occluder) {
			vec2 huv = prev_uv(SCREEN_UV);
			if (huv.x > 0.0 && huv.y > 0.0 && huv.x < 1.0 && huv.y < 1.0) {
				vec4 h = textureLod(history_tex, huv, 0.0);
				// No texel at this depth: keep the reprojected history (stable) rather than a jittered guess.
				outc = matched ? mix(clamp(h, lo - pad, hi + pad), cur, blend_w) : h;
			}
		}
	}
	if (outc.a < 1e-4) {
		discard;
	}
	ALBEDO = outc.rgb / outc.a;
	ALPHA = outc.a;
}
