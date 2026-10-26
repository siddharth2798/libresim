extends Gauge
## Attitude indicator: sky/ground ball with pitch ladder and bank scale,
## fixed orange aircraft symbol. Shows the vacuum gyro's (possibly wrong) attitude.

const SKY := Color(0.18, 0.45, 0.85)
const GROUND := Color(0.45, 0.28, 0.12)
const PX_PER_DEG := 0.03  # fraction of radius per degree of pitch


func _draw_face(c: Vector2, r: float) -> void:
	var pitch := rad_to_deg(Props.get_f("instruments/ai/pitch_rad"))
	var roll := Props.get_f("instruments/ai/roll_rad")
	var up := dir(-roll)  # screen direction of "sky"; tilts toward the raised wing, like the bank scale
	var along := Vector2(-up.y, up.x)
	var centre := c - up * (pitch * PX_PER_DEG * r)  # horizon moves down when nose up
	draw_circle(c, r, SKY)
	# ground = disk ∩ half-plane below the horizon line (convex)
	var pts := PackedVector2Array()
	var n := 72
	for i in n:
		var p0 := c + Vector2(cos(TAU * i / n), sin(TAU * i / n)) * r
		var p1 := c + Vector2(cos(TAU * (i + 1) / n), sin(TAU * (i + 1) / n)) * r
		var s0 := (p0 - centre).dot(up)
		var s1 := (p1 - centre).dot(up)
		if s0 <= 0.0:
			pts.append(p0)
		if (s0 <= 0.0) != (s1 <= 0.0):  # edge crosses the horizon: add the intersection
			pts.append(p0.lerp(p1, s0 / (s0 - s1)))
	if pts.size() >= 3:
		draw_colored_polygon(pts, GROUND)
	draw_line(centre - along * r, centre + along * r, Color.WHITE, 2.0, true)
	for deg in [-20, -10, 10, 20]:
		var o: Vector2 = centre + up * (deg * PX_PER_DEG * r)
		var w := r * (0.3 if absi(deg) == 10 else 0.45)
		var o2 := o - along * w * 0.5
		var o3 := o + along * w * 0.5
		if (o - c).length() < r * 0.85:
			draw_line(o2, o3, Color.WHITE, 1.5, true)
	# bank scale (rotates with the gyro): 0, 10, 20, 30, 60, 90
	for b in [-90, -60, -30, -20, -10, 0, 10, 20, 30, 60, 90]:
		var a := deg_to_rad(b) - roll
		var l := 0.14 if absi(b) in [0, 30, 60, 90] else 0.08
		draw_line(c + dir(a) * r * 0.98, c + dir(a) * r * (0.98 - l), Color.WHITE, 2.0, true)


func _draw_needles(c: Vector2, r: float) -> void:
	var o := Color(1.0, 0.55, 0.05)
	draw_line(c + Vector2(-r * 0.55, 0), c + Vector2(-r * 0.18, 0), o, 4.0, true)
	draw_line(c + Vector2(r * 0.18, 0), c + Vector2(r * 0.55, 0), o, 4.0, true)
	draw_circle(c, 4.0, o)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.98), c + Vector2(-8, -r * 0.82), c + Vector2(8, -r * 0.82)]), o)
	if Props.get_b("instruments/ai/flag"):
		label(c + Vector2(0, r * 0.55), "GYRO", 12, Color(1, 0.3, 0.2))
