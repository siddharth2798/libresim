class_name RunwayLights
extends MultiMeshInstance3D
## Night lighting for every runway in runways.json: white edge lights every
## 60 m (last 600 m amber), green threshold / red end bars, and a simple
## approach light bar (white, 300 m) on runways >= 1500 m. One MultiMesh.
## Fixed-size additive billboards (StandardMaterial3D) so they stay visible at range.
## Fades in when the sun is low (environment/sun_elev_deg) or visibility is poor.

const EDGE_SPACING := 60.0
const LIFT := 1.2  # above the DEM so coarse terrain LODs don't hide them
const SPRITE := 0.012  # fixed-size billboard (fraction of screen height)

var _anchor := Vector3.ZERO


func build(data: Dictionary, terrain: TerrainQuadtree) -> void:
	var pts: Array = []  # [enu Vector3, Color]
	for r in data.runways:
		var a: Dictionary = r.ends[0]
		var b: Dictionary = r.ends[1]
		var pa := Vector2(a.x, a.y)
		var pb := Vector2(b.x, b.y)
		var len: float = pa.distance_to(pb)
		var u := (pb - pa) / len
		var side := Vector2(u.y, -u.x) * (float(r.width) * 0.5 + 1.0)
		var n := int(len / EDGE_SPACING)
		for i in n + 1:
			var p := pa.lerp(pb, float(i) / n)
			var along := float(i) / n * len
			for s in [-1.0, 1.0]:
				var q: Vector2 = p + side * s
				var amber_a := along > len - 600.0  # last 600 m seen when landing toward b
				pts.append([q, Color(1.0, 0.85, 0.4, 0.9) if amber_a else Color(1.0, 0.97, 0.9, 0.9)])
		for e in [[pa, u, Color(0.2, 1.0, 0.3, 1.0), Color(1.0, 0.15, 0.1, 1.0)], [pb, -u, Color(0.2, 1.0, 0.3, 1.0), Color(1.0, 0.15, 0.1, 1.0)]]:
			var c: Vector2 = e[0]
			var w: float = float(r.width) * 0.5
			for k in range(-int(w / 3.0), int(w / 3.0) + 1):
				var q2: Vector2 = c + Vector2(u.y, -u.x) * k * 3.0
				pts.append([q2 - e[1] * 1.5, e[2]])  # green threshold (facing arrivals)
				pts.append([q2 + e[1] * 1.5, e[3]])  # red end (seen from the other way)
			if len >= 1500.0:
				for m in range(30, 301, 30):
					var ap: Vector2 = c - e[1] * float(m)
					for k2 in range(-2, 3):
						pts.append([ap + Vector2(u.y, -u.x) * k2 * 1.5, Color(1.0, 1.0, 0.95, 1.0)])
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	multimesh.mesh = q
	multimesh.instance_count = pts.size()
	_anchor = Vector3.ZERO
	if pts.size() > 0:
		var p0: Vector2 = pts[0][0]
		_anchor = Vector3(p0.x, p0.y, 0.0)
	for i in pts.size():
		var p: Vector2 = pts[i][0]
		var h := terrain.height_at(p.x, p.y) + LIFT
		multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x - _anchor.x, h, -(p.y - _anchor.y))))
		multimesh.set_instance_color(i, pts[i][1])
	q.size = Vector2(SPRITE, SPRITE)
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.25, Color(1, 1, 1, 0.8))
	g.gradient = grad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.fixed_size = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = g
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_fog = true
	m.albedo_color = Color(3, 3, 3, 1)
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 1e6
	FloatingOrigin.shifted.connect(func(_d): _place())
	_place()


func _place() -> void:
	position = FloatingOrigin.to_render(_anchor)


func _process(_dt: float) -> void:
	var sun := Props.get_f("environment/sun_elev_deg", 30.0)
	var vis := Props.get_f("weather/visibility_m", 20000.0)
	var v := clampf((4.0 - sun) / 8.0, 0.0, 1.0)
	if vis < 5000.0:
		v = maxf(v, 0.6)
	(material_override as StandardMaterial3D).albedo_color = Color(3, 3, 3, 1) * v
	visible = v > 0.01
