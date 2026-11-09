class_name RampCrew
extends Node3D
## The ground crew's vehicles around the player's aircraft while parked on a stand (RampLayout: tug, GPU, fuel, baggage trains,
## bus). They come when the aircraft stands on a stand point with the parking brake set and every engine stopped (a stand start is
## cold and dark: at once) and clear away when it is about to move: brake released (pushback needs that, GroundOps), an engine
## started, or the aircraft rolled off the stand. They are solid (OpsSolids, group "ramp:<ICAO>") but allowed in the stand's own
## corridor: RampLayout keeps them off the airframe, its danger zones and the taxi-in path. Child of AirportOps (setup).

const CHECK_S := 0.5
const PARK_M := 3.0  # CG this close to a stand's CG point
const PARK_DEG := 20.0  # and heading this close to the stand's
const STILL_MPS := 0.3
const JETWAY_HALF_M := 2.2  # half width of a docked jetway's strip on the ground

var ops: AirportOps
var stand := {}  # the stand served now ({} = none)
var icao := ""
var placed: Array = []  # RampLayout placements now standing
var _root := Node3D.new()
var _solids: OpsSolids
var _check := 0.0


func _init() -> void:
	_root.name = "ramp_crew"
	add_child(_root)  # here, not in setup(): a crew freed without setup() must not leave _root orphaned


func setup(o: AirportOps) -> void:
	ops = o
	if get_node_or_null("CabinDoor") == null:
		var door := CabinDoor.new()
		door.name = "CabinDoor"
		add_child(door)
	FloatingOrigin.shifted.connect(func(d: Vector3): _root.position += d)


func _process(dt: float) -> void:
	_check -= dt
	if _check > 0.0:
		return
	_check = CHECK_S
	var want := parked_stand()
	if want.is_empty():
		if not stand.is_empty():
			clear()
	elif stand.is_empty() or str(want.st.ref) != str(stand.ref) or want.icao != icao or Vector2(want.st.x, want.st.y) != Vector2(stand.x, stand.y):
		clear()
		serve(want.icao, want.st)


## {icao, st} of the stand the aircraft is parked on (brake set, engines stopped, still), {} if none.
func parked_stand() -> Dictionary:
	if ops == null or not Props.get_b("fdm/wow") or Props.get_f("fdm/groundspeed_mps") > STILL_MPS:
		return {}
	if Props.get_b("controls/ground/crew_away"):
		return {}  # sent away with the key; calling them again brings them back
	if not Props.get_b("controls/parking_brake") or engines_running():
		return {}
	var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var hd := Props.get_f("fdm/heading_rad")
	for k in ops._built:
		for st in ops.data[k].stands:
			if GroundParams.cg_at_stand(st).distance_to(Vector2(p.x, p.y)) < PARK_M \
					and absf(angle_difference(hd, deg_to_rad(float(st.heading_deg)))) < deg_to_rad(PARK_DEG):
				return {"icao": k, "st": st}
	return {}


static func engines_running() -> bool:
	var n := int(Props.get_f("engine/count", 1.0))
	for i in n:
		if Props.get_b("engines/%d/running" % (i + 1)):
			return true
	return Props.get_b("engine/running")


## Park the crew around the aircraft on stand st of airport k.
func serve(k: String, st: Dictionary) -> void:
	icao = k
	stand = st
	_root.position = FloatingOrigin.to_render(Vector3.ZERO)
	_solids = OpsSolids.new("ramp:" + k)
	var jetways := _docked_jetways(k, st)
	placed = RampLayout.plan(AircraftDef.current(), st, func(poly: PackedVector2Array, top: float) -> bool:
		return blocked(poly, top, jetways))
	var lamps := VehicleLamps.new()
	for v in placed:
		var seed := GroundVehicles.seed_at(v.pos)
		var working: bool = v.kind != "baggage_cart"
		var n := GroundVehicles.make(v.kind, float(v.scale), seed, working)
		var h := _h(v.pos)
		n.position = Vector3(v.pos.x, h, -v.pos.y)
		n.rotation.y = -float(v.heading)
		_root.add_child(n, true)
		# solid where RampLayout put it (in its own stand's corridor by design, so not OpsSolids.add_model's keep-out)
		ObstacleRegistry.add(_solids.group, ObstacleShapes.poly(v.poly, h - 0.5, h + float(v.top), OpsSolids.LABELS.get(v.kind, "a parked vehicle")))
		if working:
			lamps.add(v.kind, n.transform.scaled_local(Vector3.ONE * float(v.scale)), seed)
	lamps.attach(_root)
	Props.set_v("ops/ramp_crew", "%s %s: %d vehicles" % [k, st.ref, placed.size()])


func clear() -> void:
	for c in _root.get_children():
		c.queue_free()
	if _solids:
		_solids.clear()
		_solids = null
	placed = []
	stand = {}
	icao = ""
	Props.set_v("ops/ramp_crew", "")


func _exit_tree() -> void:
	if _solids:
		_solids.clear()


## Is something solid in the way of a vehicle footprint (world) of height top: a registered solid (jetway at rest, terminal,
## other dressing, mast) or a jetway docked at this stand (not solid while docked: a strip from its terminal end to the door)?
func blocked(poly: PackedVector2Array, top: float, jetways: Array) -> bool:
	for j in jetways:
		if not Geometry2D.intersect_polygons(poly, j).is_empty():
			return true
	var c := Vector2.ZERO
	for p in poly:
		c += p / poly.size()
	var g := _h(c)
	var out := []
	ObstacleRegistry.near(c.x, c.y, 10.0, out)
	if out.is_empty():
		return false
	var segs := []
	for z in [g + 0.2, g + top * 0.5, g + top]:
		for i in poly.size():
			segs.append([Vector3(poly[i].x, poly[i].y, z), Vector3(poly[(i + 1) % poly.size()].x, poly[(i + 1) % poly.size()].y, z)])
		segs.append([Vector3(poly[0].x, poly[0].y, z), Vector3(poly[2].x, poly[2].y, z)])
		segs.append([Vector3(poly[1].x, poly[1].y, z), Vector3(poly[3].x, poly[3].y, z)])
	for o in out:
		for s in segs:
			if ObstacleShapes.segment_hits(s[0], s[1], o):
				return true
	return false


## Ground strips of the jetways docked at (or docking to) this stand.
func _docked_jetways(k: String, st: Dictionary) -> Array:
	var out := []
	var root: Node = ops._built.get(k)
	if root == null or not GroundParams.dockable():
		return out
	var tip := GroundParams.door_tip(st)
	for n in root.get_children():
		if n is JetwayRig and (n as JetwayRig).docked_stand == str(st.ref) and str(st.ref) != "":
			out.append(strip((n as JetwayRig).terminal, tip, JETWAY_HALF_M))
	return out


static func strip(a: Vector2, b: Vector2, half: float) -> PackedVector2Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * half
	return PackedVector2Array([a + n, b + n, b - n, a - n])


func _h(p: Vector2) -> float:
	return ops.terrain.height_at(p.x, p.y) if ops and ops.terrain else 0.0
