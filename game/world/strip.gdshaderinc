// Taxiway surface with its markings (taxiway.gdshader; lead_on.gdshader defines LEAD_ON and draws only the yellow
// line over a runway). Runways draw world/runway_v2.gdshader. Pavement from the runways' shared surface include
// (runway_surface.gdshaderinc: the apron asphalt tone, large-scale variation, trodden centre, oxidised edges), lighter
// wear than a runway (nose wheel on the line, main gears either side), the ICAO yellow centreline (0.15 m) and, where
// the data gave the taxiway a width (edge_lines), the double yellow edge lines. Fades out with distance (TAXI_FADE).
// UV.x: 0..1 across the width, UV.y: metres along the centreline. UV2 (a merged mesh, AirportCut: one mesh and one
// material for all of an airport's taxiways): (width m, 1 = paint the edges), per ribbon; 0 = use the uniforms.
// The mesh lies exactly on the terrain (GroundDrape). Pulled slightly toward the camera so it never z-fights
// the terrain under it, and lifted with distance away from the aircraft (lod_lift rad, ~0.7 px,
// ground_lift.gdshaderinc): coarser terrain LODs deviate from the strip by metres (p99 ~3 m at level 0,
// ~4.5 m at level 2, see tools/17_airport_fixups.py), and a view-space pull alone gives only ~0.15 % x
// camera height of vertical margin at grazing angles.
#include "res://world/ground_lift.gdshaderinc"

uniform bool is_runway = false;  // kept for AirportBuilder (always false here)
uniform float length_m = 1000.0;
uniform float width_m = 15.0;
uniform bool edge_lines = false;  // the taxiway's width is known: paint its edges
uniform vec3 taxi_paint : source_color = vec3(0.95, 0.75, 0.15);
uniform float lod_lift = 0.0007;
uniform float seed = 7.0;
uniform float gear_hw = 3.2;  // narrow-body main gear: where the taxi wear runs
const int runway_detail = 1;  // runway_surface.gdshaderinc: no aggregate on taxiways
global uniform vec3 fog_color;
global uniform float haze_density;
#include "res://world/curvature.gdshaderinc"  // Earth curvature (G4)
#include "res://world/haze_sky.gdshaderinc"  // view-dependent haze colour (G4)
#include "res://world/runway_surface.gdshaderinc"
global uniform float wetness;
global uniform float precip;
#include "res://world/rain_ripples.gdshaderinc"
varying float v_dist;
varying flat vec2 v_ribbon;

void vertex() {
	v_ribbon = UV2;
	VERTEX.y += ground_lift((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD, lod_lift);
	VERTEX += curve_local(MODEL_MATRIX, curve_drop((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz));
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_dist = length(vp.xyz);
#ifdef LEAD_ON
	vp.xyz *= 0.998;  // pulled more than the runway (0.9985): the line shows on top of it
#else
	vp.xyz *= 0.999;  // pulled less than runways: where they cross, the runway always wins
#endif
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	float w_m = v_ribbon.x > 0.0 ? v_ribbon.x : width_m;
	float across = (UV.x - 0.5) * w_m;  // metres from centreline
	float along = mod(UV.y, 4096.0);
	float hx = fwidth(across) * 0.6 + 1e-3;
	float ax = abs(across);
	// yellow centreline, a little scuffed by the nose wheel
	float line = rw_box(across, -0.075, 0.075, hx) * (0.8 + 0.2 * rw_noise(vec2(along * 0.4, 3.0)));
#ifndef LEAD_ON
	vec3 col = rw_base(false, across, along);
	// rolling wear: nose wheel on the line, main gears either side, mottled
	col *= 1.0 - (0.07 * rw_g((ax - gear_hw) / 1.0) + 0.05 * rw_g(across / 0.6)) * (0.6 + 0.4 * rw_noise(vec2(across, along * 0.05)));
	float edge = 0.0;
	if (v_ribbon.x > 0.0 ? v_ribbon.y > 0.5 : edge_lines) {  // double yellow edge lines (0.15 m, 0.15 m apart) just inside the pavement edge
		float e0 = w_m * 0.5 - 0.2;
		edge = rw_box(ax, e0 - 0.15, e0, hx) + rw_box(ax, e0 - 0.45, e0 - 0.3, hx);
	}
	col = mix(col, taxi_paint * 0.85, clamp(max(line, edge), 0.0, 1.0)) * mix(1.0, 0.65, wetness);  // wet tarmac darkens
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = haze_color(-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * haze;
	ROUGHNESS = mix(0.85, 0.25, wetness);
	SPECULAR = mix(0.2, 0.5, wetness) * (1.0 - haze);
	vec2 wxz = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;  // render frame: rain rings (rain_ripples)
	vec2 rip = rr_grad(wxz, TIME, v_dist, length(fwidth(wxz))) * wetness;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(rip.x, 0.0, rip.y, 0.0)).xyz);
	// A taxiway a few px wide (far away / edge-on) rasterises as stair-stepped dashes; fade it
	// into the terrain imagery, which already shows the pavement at that size.
	ALPHA = smoothstep(2.0, 6.0, w_m / max(fwidth(across), 1e-4));
#else
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = taxi_paint * mix(1.0, 0.65, wetness) * (1.0 - haze);
	EMISSION = haze_color(-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * haze;
	ROUGHNESS = mix(0.85, 0.25, wetness);
	SPECULAR = mix(0.2, 0.5, wetness) * (1.0 - haze);
	ALPHA = line;
#endif
}
