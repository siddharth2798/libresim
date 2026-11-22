shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Shadow-only proxy of an impostor tree (TreeShadows): drawn in the sun's shadow pass only (cast_shadow SHADOWS_ONLY).
// UV.x = 1 marks the unit icosahedron crown, moved here to the species' crown (unit tree space: x / z in crown widths,
// y in heights); the trunk prism stays. Opaque, no alpha test. A tree collapses to its foot inside the near-mesh radius
// (lod_r: the mesh casts its own shadow) and fades out over the last 15 % of shadow_r. INSTANCE_CUSTOM.g carries the
// species (species * variant_n + variant), as for the impostor.

#include "res://world/curvature.gdshaderinc"  // Earth curvature (G4): the shadows fall where the bent trees stand
#include "res://world/tree_tint.gdshaderinc"

uniform float shadow_r = 800.0;
uniform float lod_r = 0.0;
uniform float variant_n = 4.0;
// per species (TreeSpecies order): crown centre height, vertical radius, horizontal radius
const vec3 CROWN[5] = vec3[5](vec3(0.67, 0.3, 0.42), vec3(0.86, 0.1, 0.45), vec3(0.72, 0.12, 0.48),
	vec3(0.65, 0.3, 0.42), vec3(0.6, 0.3, 0.46));

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(terrain_eye, wp);
	float keep = step(lod_r, d) * (1.0 - smoothstep(shadow_r * 0.85, shadow_r, d));
	if (UV.x > 0.5) {
		vec3 c = CROWN[clamp(tree_species_of(INSTANCE_CUSTOM.g, variant_n), 0, 4)];
		VERTEX = vec3(0.0, c.x, 0.0) + VERTEX * vec3(c.z, c.y, c.z);
	}
	VERTEX *= keep;
	VERTEX += curve_local(MODEL_MATRIX, curve_drop(wp));
}

void fragment() {
	ALBEDO = vec3(0.0);
}
