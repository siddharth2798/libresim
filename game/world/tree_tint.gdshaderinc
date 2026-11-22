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

// Season (TreeLook.dryness, 0 after the monsoon .. 1 at the end of the dry season, from the date): deciduous teak and
// scrub turn olive and yellow-brown, mango, palms and casuarina hardly change. TreeLook.DRY_RESPONSE has the same
// numbers per species (TreeSpecies order: forest, palm, scrub, slim, spread). seed varies it per tree.
const float TREE_DRY_RESPONSE[5] = float[5](0.8, 0.12, 0.9, 0.2, 0.3);
vec3 tree_season(vec3 c, int species, float dry, float seed) {
	float k = clamp(dry * TREE_DRY_RESPONSE[clamp(species, 0, 4)] * mix(0.6, 1.25, seed), 0.0, 1.0);
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 dry_col = l * vec3(1.6, 1.12, 0.42);
	return mix(c * vec3(0.96, 1.04, 0.96), dry_col, k * 0.6);
}

// Species index from INSTANCE_CUSTOM.g (species * variant_n + variant).
int tree_species_of(float custom_g, float variant_n) {
	return int(floor(floor(custom_g + 0.5) / variant_n));
}
#endif
