#[compute]
#version 450
// Copies the resolved scene depth into an R32F image the low-resolution cloud march can sample
// (world/cloud_depth_copy.gd). Texel (0, 0) stays texel (0, 0): row 0 is the top of the view,
// matching SCREEN_UV and the motion-blur depth fetch.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D depth_src;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D depth_dst;

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 pad;
} pc;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(pc.size.x) || px.y >= int(pc.size.y)) {
		return;
	}
	imageStore(depth_dst, px, vec4(texelFetch(depth_src, px, 0).r, 0.0, 0.0, 0.0));
}
