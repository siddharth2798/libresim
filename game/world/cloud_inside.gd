class_name CloudInside
extends RefCounted
## Applies the in-cloud presentation (maps in CloudLook) each frame, called by SkyTime after the cloud pass is
## fed: the eased in-cloud factor from the camera's cloud density, the fog (density continuous with the
## density, capped around the aircraft in outside views; colour with luminance structure and darker in storm
## cloud), a diffuse light floor so the aircraft keeps its shading, a brighter sky overhead for the ambient
## light, the cloud pass's pocket and glow, and the wisps.

var k := 0.0  # 0..1 eased in-cloud factor
var ext := 0.0  # 0..1 eased "outside view of the aircraft" weight
var tone := 1.0
var _flow := Vector3.ZERO


## d: cloud density at the camera, haze: clear-air extinction, light: daylight x overcast dimming (0..1),
## hor: clear fog colour, drift: the cloud field's offset, sun_dir: towards the sun (render frame).
func update(dt: float, cam: Camera3D, env: Environment, sky: ShaderMaterial, sun: DirectionalLight3D, layer: CloudLayer,
		d: float, haze: float, light: float, hor: Color, drift: Vector2, sun_dir: Vector3) -> void:
	var target := CloudLook.ramp(d)
	k = CloudLook.ease_to(k, target, dt, 0.6 if target > k else 1.2)
	var rig := cam as CameraRig
	var cockpit := rig == null or rig.aircraft == null or rig.mode == CameraRig.Mode.COCKPIT
	var dist := 1.0e9 if cockpit else cam.global_position.distance_to(rig.aircraft.global_position)
	ext = CloudLook.ease_to(ext, CloudLook.subject_weight(dist, cockpit), dt, 0.5)
	var wisps := cam.get_node_or_null("CloudWisps") as CloudWisps
	if k < 0.002:
		layer.set_inside(0.0, 0.0, Color.BLACK)
		if wisps:
			wisps.update_wisps(Vector3.ZERO, Vector3.ZERO, 0.0, Color.BLACK)
		return
	var kind := str(Props.get_v("environment/cloud_kind", "stratiform"))
	tone = CloudLook.kind_tone(kind, Props.get_f("environment/storm_intensity"))
	var base := Color(0.8, 0.82, 0.86) * maxf(light, 0.04) * tone
	var glow_col := sun.light_color * (CloudLook.GLOW * smoothstep(0.1, 0.6, light) * tone)
	var fwd := -cam.global_transform.basis.z
	var inside := CloudLook.tint(base, fwd.y, fwd.dot(sun_dir), glow_col)
	var sigma := CloudLook.fog_sigma(haze, d, k, dist, ext)
	env.fog_enabled = true
	env.fog_density = sigma
	env.fog_light_color = hor.lerp(inside, k)
	RenderingServer.global_shader_parameter_set("haze_density", sigma)
	RenderingServer.global_shader_parameter_set("fog_color", env.fog_light_color.srgb_to_linear())
	sun.light_energy = maxf(sun.light_energy, CloudLook.sun_floor(k, light, ext, tone))
	var top: Color = sky.get_shader_parameter("zenith_color")  # brighter overhead: the ambient light comes from above
	sky.set_shader_parameter("zenith_color", top.lerp(inside * 1.2, k * 0.8))
	layer.set_inside(k, CloudLook.bubble_m(dist, ext), glow_col)
	if wisps:
		_update_wisps(wisps, cam, rig, d, drift, base)


## Wisps are fixed in the air mass: the camera position includes the cloud drift, the streak direction and
## length come from the aircraft's velocity relative to the air (so a paused flight still shows its streaks).
func _update_wisps(wisps: CloudWisps, cam: Camera3D, rig: CameraRig, d: float, drift: Vector2, base: Color) -> void:
	var w := FloatingOrigin.to_world(cam.global_position)
	var flow := Vector3.ZERO
	if rig and rig.aircraft:
		var v: Vector3 = rig.aircraft.fdm_node.fdm.velocity_ned()
		var wind: Vector3 = Props.get_v("environment/wind_ned", Vector3.ZERO)
		var rel := v - wind  # air-relative velocity, NED
		flow = Vector3(rel.y, -rel.z, -rel.x)  # render frame: east, up, south
	wisps.update_wisps(Vector3(w.x + drift.x, w.y + drift.y, w.z), flow, CloudLook.wisp_alpha(k, d, tone), base * 1.5)
