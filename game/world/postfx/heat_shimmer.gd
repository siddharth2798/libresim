class_name HeatShimmer
extends MeshInstance3D
## Heat shimmer quad (heat_shimmer.gdshader), a child of the flight camera like SunGlare. The driver sets the
## ground term each frame (PostFxLook.ground_shimmer); the exhaust plumes come from the aircraft's data:
##   aircraft.json "exhausts": {"strength": 1.0, "list": [{"pos": [x, y, z], "dir": [x, y, z], "radius": m,
##     "kind": "jet" | "piston", "engine": n (1-based), "length_m": m, "spread": end radius / radius}]}
## pos and dir are in the model frame of models/*_pivots.json (FlightGear: x aft, y right, z up, from the VRP,
## AircraftModel.fg_to_local); dir defaults to straight aft. No section = no exhaust shimmer.
## A plume is as hot as its engine: engines/<n>/running and egt_k, which every engine type publishes (fdm_node.gd).

const MAX_PLUMES := 4
const KIND := {  # per-kind defaults; an exhaust entry overrides any of them
	"jet": {"length_k": 30.0, "spread": 2.5, "strength": 1.0},
	"piston": {"length_k": 25.0, "spread": 4.0, "strength": 0.35},
}

var _mat := ShaderMaterial.new()
var _exhausts: Array = []  # [{pos, dir (local), r, len, spread, k, engine}]
var _model: Node3D


const PRIORITY := -10  # Material.render_priority: before the clouds (CloudLayer.PRIORITY)


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mesh = q
	_mat.shader = preload("res://world/postfx/heat_shimmer.gdshader")
	material_override = _mat
	extra_cull_margin = 1e6
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sorting_offset = 500.0  # before the cloud quad (1000), see the shader header
	# Distance sorting between full-screen quads is not reliable: on Max the cloud upscale quad drew first, and the
	# shimmer then painted the cloud-free screen copy over the clouds (dark discs behind the engines). The material
	# priority always wins: shimmer, then clouds, then the sun glare.
	_mat.render_priority = PRIORITY
	visible = false


## The exhaust list of an aircraft (aircraft.json "exhausts", defaults filled in), in model-frame metres.
static func exhausts_of(def: AircraftDef) -> Array:
	var out := []
	if def == null:
		return out
	var sec := def.section_or("exhausts", {"strength": 1.0, "list": []})
	for e in sec.list:
		if not e is Dictionary or not e.has("pos"):
			continue
		var kind := str(e.get("kind", "jet"))
		var kd: Dictionary = KIND.get(kind, KIND.jet)
		var r := float(e.get("radius", 0.5))
		var p: Array = e.pos
		var d: Array = e.get("dir", [1.0, 0.0, 0.0])
		out.append({"pos": Vector3(p[0], p[1], p[2]), "dir": Vector3(d[0], d[1], d[2]).normalized(), "r": r,
			"len": float(e.get("length_m", r * kd.length_k)), "spread": float(e.get("spread", kd.spread)),
			"k": float(e.get("strength", kd.strength)) * float(sec.strength), "engine": int(e.get("engine", 1))})
		if out.size() == MAX_PLUMES:
			break
	return out


## model: the AircraftModel (anything with fg_to_local and a def), or null for no plumes.
func setup(model: Node3D) -> void:
	_model = model
	_exhausts = exhausts_of(model.def if model and "def" in model else null)


## ground: 0..1 hot-ground term; near_m / far_m: its distance band.
func update_shimmer(ground: float, near_m: float, far_m: float) -> void:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var k := PackedFloat32Array()
	for i in MAX_PLUMES:
		var heat := 0.0
		var pa := Vector4.ZERO
		var pb := Vector4.ZERO
		if i < _exhausts.size() and is_instance_valid(_model):
			var e: Dictionary = _exhausts[i]
			var n := int(e.engine)
			heat = PostFxLook.exhaust_heat(Props.get_b("engines/%d/running" % n), Props.get_f("engines/%d/egt_k" % n), e.k)
			var p0: Vector3 = _model.global_transform * _model.fg_to_local(e.pos)
			var p1: Vector3 = _model.global_transform * _model.fg_to_local(e.pos + e.dir * float(e.len))
			pa = Vector4(p0.x, p0.y, p0.z, e.r)
			pb = Vector4(p1.x, p1.y, p1.z, e.r * float(e.spread))
		a.append(pa)
		b.append(pb)
		k.append(heat)
	_mat.set_shader_parameter("plume_a", a)
	_mat.set_shader_parameter("plume_b", b)
	_mat.set_shader_parameter("plume_k", k)
	_mat.set_shader_parameter("ground", ground)
	_mat.set_shader_parameter("near_m", near_m)
	_mat.set_shader_parameter("far_m", far_m)
	visible = ground > 0.001 or Array(k).max() > 0.001
