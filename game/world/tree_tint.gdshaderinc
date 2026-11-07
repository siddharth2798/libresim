#ifndef TREE_TINT_INC
#define TREE_TINT_INC
// Per-instance leaf tint from stable INSTANCE_CUSTOM seeds (TreeLook.colour_unit).
// A few degrees of hue and a few percent of value. Does not depend on time.
vec3 tree_tint(vec3 c, float seed_hue, float seed_value) {
	float h = (seed_hue - 0.5) * 0.16;
	float v = mix(0.93, 1.07, seed_value);
	const vec3 k = vec3(0.57735027);
	float ch = cos(h);
	return (c * ch + cross(k, c) * sin(h) + k * dot(k, c) * (1.0 - ch)) * v;
}
#endif
