class_name GroundFxQuality
extends RefCounted
## Ground particle effects per graphics preset (world/ground_fx.gd): how many particles each effect may keep alive
## at full strength. 0 = that effect is off and its emitter is never built. Low has no particles at all: only the
## shader rain ripples on wet pavement (world/rain_ripples.gdshaderinc), which every preset draws.
##   splash  rain splash flecks on the ground round the camera (world/rain_splash.gd)
##   spray   water spray thrown up by each wheel on a wet surface        tail  the rooster tail behind a main wheel
##   wash    propeller / jet wash mist blown back over wet ground (or dust over dry grass)
##   dust    dust from each wheel rolling or landing on dry unpaved ground
## The cost is overdraw of soft transparent sprites (fill rate), so counts grow with the preset's resolution budget. Spray is
## many small faint wisps, so its count is higher than the others for about the same overdraw.
## The Compatibility renderer (OpenGL fallback, the weakest GPUs) is held to the Medium counts.
## Graphics.apply_to_scene calls apply().

const COUNTS := {
	"low": {"splash": 0, "spray": 0, "tail": 0, "wash": 0, "dust": 0},
	"medium": {"splash": 300, "spray": 130, "tail": 0, "wash": 70, "dust": 70},
	"high": {"splash": 600, "spray": 250, "tail": 90, "wash": 140, "dust": 140},
	"ultra": {"splash": 900, "spray": 350, "tail": 140, "wash": 200, "dust": 200},
	"max": {"splash": 1000, "spray": 390, "tail": 160, "wash": 220, "dust": 220},
}


## Particle counts for a preset on a renderer ("forward_plus", "mobile", "gl_compatibility").
static func counts(preset: String, renderer := "forward_plus") -> Dictionary:
	var c: Dictionary = COUNTS.get(preset, COUNTS.high).duplicate()
	if renderer == "gl_compatibility":
		for k in c:
			c[k] = mini(int(c[k]), int(COUNTS.medium[k]))
	return c


static func apply(root: Node, preset: String) -> void:
	var g := root.get_node_or_null("TouchdownFx/Ground") if root else null
	if g and g.has_method("set_counts"):
		g.set_counts(counts(preset, RenderingServer.get_current_rendering_method()))
