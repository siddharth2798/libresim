#ifndef TREE_PARTS_INC
#define TREE_PARTS_INC
// Albedo and cover of a near tree mesh fragment (TreeParts layout), shared by tree_mesh.gdshader and the impostor bake
// tree_bake.gdshader, so the baked impostors are the same colour as the meshes they stand in for.
// col = COLOR (rgb base colour with baked occlusion, a = part: 0 bark, 0.5 leaf card, 1 frond); leaf = the leaf-card
// atlas sample (tools/tree_leaf_cards.py: near-grey brightness, alpha = cover); local = unit-mesh position.

float tree_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float tree_vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(tree_hash(i), tree_hash(i + vec2(1, 0)), f.x), mix(tree_hash(i + vec2(0, 1)), tree_hash(i + vec2(1, 1)), f.x), f.y);
}

// Alpha-tested leaves thin out in the mip levels: raise the cover with the texel footprint (atlas 1024 px wide).
float tree_leaf_boost(vec2 uv) {
	float mip = log2(max(max(length(dFdx(uv)), length(dFdy(uv))) * 1024.0, 1.0));
	return 1.0 + 0.35 * mip;
}

vec4 tree_part_albedo(vec4 col, vec4 leaf, vec3 local, float boost) {
	if (col.a < 0.25) {  // bark: streaks along the trunk; palm trunks (a = 0.1) get leaf-scar rings
		vec3 b = col.rgb * (0.75 + 0.5 * tree_vnoise(local.xy * vec2(160.0, 18.0) + local.z * 100.0));
		if (col.a > 0.05) {
			float ring = abs(fract(local.y * 70.0 + tree_vnoise(local.xz * 40.0) * 0.4) - 0.5) * 2.0;
			b *= 0.68 + 0.32 * smoothstep(0.15, 0.55, ring);
		}
		return vec4(b, 1.0);
	}
	return vec4(col.rgb * leaf.rgb * 1.7, clamp(leaf.a * boost, 0.0, 1.0));
}
#endif
