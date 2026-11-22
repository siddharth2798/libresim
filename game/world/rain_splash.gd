class_name RainSplash
extends GroundEmitter
## Rain splashes on the ground round the camera: tiny droplet crowns that open and vanish in a quarter second, spread
## evenly over a square of ground in front of the camera (world/rain_ripples.gdshaderinc draws the matching rings on
## wet pavement). Rain falls evenly, so splashes born at random points on the ground look the same as drops that
## collided there, without a collision heightfield: that would re-render the scene's depth from above every frame the
## camera moves and does not exist on the Compatibility renderer. The square is laid on the terrain height under its
## corners, tilted to their plane; on ground a plane cannot follow (relief over RELIEF) the splashes fade out rather
## than float or sink.
## Only near the ground (below MAX_AGL) and only while it rains (environment/precip, as WeatherFx's rain streaks).

const HALF := 12.0  # m: half edge of the splash square
const AHEAD := 8.0  # m: its centre is this far ahead of the camera (horizontally)
const MAX_AGL := 40.0  # m: higher than this the splashes are too small to see
const RELIEF := 1.5  # m of height difference across the square before splashes fade

var height_at: Callable = func(_e: float, _n: float) -> float: return 0.0  # ground height (m) at ENU east, north


func _init() -> void:
	super("splash")
	proc.emission_box_extents = Vector3(HALF, 0.02, HALF)
	proc.spread = 0.0
	proc.initial_velocity_min = 0.0
	proc.initial_velocity_max = 0.0


## Splash strength 0..1 for rain rate precip (0..1), camera height above the ground (m) and the ground relief (m)
## across the square: 0 without rain, fading out with height and on uneven ground.
static func strength(precip: float, agl: float, relief := 0.0) -> float:
	if precip < 0.01 or agl > MAX_AGL:
		return 0.0
	return clampf(precip, 0.0, 1.0) * (1.0 - smoothstep(MAX_AGL * 0.4, MAX_AGL, agl)) * (1.0 - smoothstep(RELIEF * 0.5, RELIEF, relief))


## Once a frame: cam the active camera (null = off), precip the local rain rate 0..1.
func update(cam: Camera3D, precip: float) -> void:
	if cam == null or capacity <= 0:
		set_rate(0.0)
		return
	var c := FloatingOrigin.to_world(cam.global_position)
	var f := -cam.global_basis.z
	var fh := Vector2(f.x, -f.z)
	fh = fh.normalized() if fh.length() > 0.05 else Vector2.ZERO
	var mid := Vector2(c.x, c.y) + fh * AHEAD
	var h: float = height_at.call(mid.x, mid.y)
	var hc := []
	for d in [Vector2(HALF, HALF), Vector2(-HALF, HALF), Vector2(HALF, -HALF), Vector2(-HALF, -HALF)]:
		hc.append(float(height_at.call(mid.x + d.x, mid.y + d.y)))
	# the square is tilted to the ground's plane through the corners; what a plane cannot follow is "relief"
	var sx: float = (hc[0] + hc[2] - hc[1] - hc[3]) / (4.0 * HALF)
	var sy: float = (hc[0] + hc[1] - hc[2] - hc[3]) / (4.0 * HALF)
	var mean: float = (hc[0] + hc[1] + hc[2] + hc[3]) * 0.25
	var relief := 2.0 * maxf(absf(hc[0] - hc[1] - hc[2] + hc[3]) * 0.25, absf(h - mean))
	var k := strength(precip, c.z - h, relief)
	set_rate(k)
	if k > 0.0:
		GroundFxLook.splash_tint(Props.get_f("environment/light_level", 1.0))
		basis = Basis(Quaternion(Vector3.UP, Vector3(-sx, 1.0, sy).normalized()))
		place(FloatingOrigin.to_render_d(mid.x, mid.y, mean + 0.05))
