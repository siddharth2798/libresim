// Ground overlays (runway / taxiway ribbons, stand paint, taxi-route line) are built on the FDM's ground and
// coplanar with the finest terrain LOD (GroundDrape). They win the depth test by a view-space pull toward the
// camera (strip.gdshaderinc, ground_paint.gdshader); far away, where coarser terrain LODs deviate from them by
// metres, they are also lifted by lod_lift rad x distance (~0.7 px). Not near the aircraft: TerrainQuadtree
// keeps the finest, un-morphed terrain within FOCUS_KEEP_M of it (ground_focus), so the tyres stand on the
// paint at every camera distance (docs/TYRE-CONTACT-PLAN.md).
#ifndef GROUND_LIFT_INC  // also included by curvature.gdshaderinc
#define GROUND_LIFT_INC
global uniform vec3 ground_focus;  // render space; far away when there is no aircraft

// Metres to lift a vertex at render-space position wp seen from cam.
float ground_lift(vec3 wp, vec3 cam, float lod_lift) {
	float away = smoothstep(220.0, 380.0, distance(wp.xz, ground_focus.xz));  // TerrainQuadtree.FOCUS_KEEP_M = 400
	return length(wp - cam) * lod_lift * away;
}
#endif
