shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled;
// Flat paint on the ground (stand lead-in line / stop bar, taxi-route line: GroundPaint). The mesh lies on
// the terrain (GroundDrape); a view-space pull wins the depth test against the terrain and the runway /
// taxiway ribbons (runway 0.9985, taxiway 0.999, lead-on 0.998), and far from the aircraft it is lifted
// like them (ground_lift.gdshaderinc).
#include "res://world/ground_lift.gdshaderinc"
#include "res://world/curvature.gdshaderinc"  // Earth curvature (G4)

uniform vec4 color : source_color = vec4(0.95, 0.78, 0.15, 1.0);
uniform float pull = 0.998;
uniform float lod_lift = 0.0007;

void vertex() {
	VERTEX.y += ground_lift((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD, lod_lift);
	VERTEX += curve_local(MODEL_MATRIX, curve_drop((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz));
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= pull;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = color.rgb;
}
