class_name PoolProfile
extends RefCounted
## The cone shape of one apron floodlight's pool (world/light_pool.gdshader and the real SpotLight3D of ApronLamps), one
## definition for both: Godot's spot cone f = 1 - rim^p, rim = (1 - cos a) / (1 - cos cone) (a: angle off the axis, cone: the
## spot angle). It always meets zero at the cone's edge at slope -p, so the edge is as soft as p is small: the old p = 1
## gave a plateau and a visible rim on the dark apron (the hard white "cones"), p = 0.7 a peaked beam that fades into the
## dark. The cone is also wider than the beam needs (CONE_EXTRA), so the rim sits where the light is already faint.

const EXP := 1.0  # spot_angle_attenuation of the real lamps; light_pool.gdshader's CONE_EXP


## Share of the aim-point light at a direction whose cosine to the axis is scos, for a cone whose half-angle has cosine
## cone_cos: 1 on the axis, falling to 0 at and beyond the edge.
static func cone(scos: float, cone_cos: float) -> float:
	var rim := clampf((1.0 - maxf(scos, cone_cos)) / (1.0 - cone_cos), 0.0, 1.0)
	return 1.0 - pow(rim, EXP)
