// Earth curvature, visual only (docs/GRAPHICS-PLAN.md G4): far geometry is lowered by d^2 / 2R, d the horizontal
// distance from the camera (terrain_eye, also the real camera in shadow passes, so casters and receivers bend
// alike), so the horizon dips below eye level and the haze meets the sky instead of a flat edge. The FDM and
// height_at() are flat and untouched. Everything drawn far away uses this one function (terrain, buildings,
// trees, terminals, runway ribbons, light points), so nothing floats above the bent ground. Near the camera the
// drop is tiny (0.3 m at 2 km, 7.8 m at 10 km, 785 m at 100 km).
// Around the aircraft (ground_focus) the ground stays flat when the camera is a few km off (tower / fly-by
// views), so the unbent aircraft keeps its wheels on it; the step this leaves is ~1 m at 4 km, gone by 8 km.
#ifndef CURVATURE_INC
#define CURVATURE_INC
#include "res://world/ground_lift.gdshaderinc"
global uniform vec3 terrain_eye;  // camera, render space (same in shadow passes); TerrainQuadtree sets it

const float CURVE_INV_2R = 0.5 / 6371000.0;

// Metres to lower a point at render-space position wp.
float curve_drop(vec3 wp) {
	vec2 d = wp.xz - terrain_eye.xz;
	float keep = (1.0 - smoothstep(300.0, 700.0, distance(wp.xz, ground_focus.xz)))
		* (1.0 - smoothstep(4000.0, 8000.0, distance(ground_focus.xz, terrain_eye.xz)));
	return dot(d, d) * CURVE_INV_2R * (1.0 - keep);
}

// Local-space offset that moves a vertex `drop` metres down in world y, for a model matrix m without shear
// (rotation x scale: inverse(M) v = column_i . v / |column_i|^2 per component).
vec3 curve_local(mat4 m, float drop) {
	vec3 c0 = m[0].xyz, c1 = m[1].xyz, c2 = m[2].xyz;
	return -drop * vec3(c0.y / dot(c0, c0), c1.y / dot(c1, c1), c2.y / dot(c2, c2));
}
#endif
