class_name GroundFx
extends Node3D
## Particles that meet the ground (graphics Phase 3), a child "Ground" of TouchdownFx:
##   rain splashes round the camera while it rains (RainSplash)
##   per wheel: water spray on a wet surface, a rooster tail behind each main wheel at speed, dust off dry grass or
##   dirt while rolling and a puff where a wheel lands there (WheelSpray; the wheels are the FDM's gear contacts, so
##   any aircraft works: the C172's three, the A320's nose and two bogies)
##   per engine: wash mist over wet ground at high power, or dust over dry grass (EngineWash)
## No splashes where the aircraft shelters the ground (fuselage and wing boxes, world/rain_splash.gdshader).
## Publishes ground/unpaved: the share of the wheels on the ground that stand off the pavement (the tyre sounds).
## Wetness is environment/wetness and the rain environment/precip (WeatherFx). Paved or not: GroundSurface. Particle
## counts per graphics preset (GroundFxQuality, set_counts): an effect at 0 has no emitter at all (Low: none).
## Paused or in a replay no new spray, wash or dust starts. clear() (a new flight, F5) drops every live particle.

const SURFACE_S := 0.1  # s between the paved / unpaved checks of each wheel

var fdm_node: FdmNode
var surface := GroundSurface.new()
var splash: RainSplash
var wheels := {}  # gear contact name -> WheelSpray
var washes: Array = []  # EngineWash per power unit
var counts := {}
var _paved := {}  # wheel name or "unit<i>" -> bool, refreshed every SURFACE_S
var _surface_t := 0.0
var _def: AircraftDef
var _airports: AirportBuilder
var _boxes: Array = []  # shelter boxes (fuselage, wing) for the splashes, made on first use


func setup(f: FdmNode, def: AircraftDef = null, airports: AirportBuilder = null) -> void:
	fdm_node = f
	_def = def if def != null else AircraftDef.current()
	_airports = airports
	if airports and airports.data is Dictionary:
		var tile := 7680.0
		if airports.terrain and airports.terrain.cache:
			tile = airports.terrain.cache.tmeta.tile_size_m
		surface.setup(airports.data, tile)
	if not counts.is_empty():
		set_counts(counts)


## GroundFxQuality.counts(): builds what has a count, resizes the rest (0 = off, emitter cleared).
func set_counts(c: Dictionary) -> void:
	counts = c
	if splash == null and int(c.get("splash", 0)) > 0:
		splash = RainSplash.new()
		splash.name = "Splash"
		if _airports and _airports.terrain:
			var t := _airports.terrain
			splash.height_at = func(e: float, n: float) -> float: return t.height_at(e, n)
		add_child(splash)
	if splash:
		splash.set_capacity(int(c.get("splash", 0)))
	if fdm_node == null or fdm_node.fdm == null:
		return
	var legs: Dictionary = _def.section("touchdown").get("legs", {}) if _def else {}
	for gc in fdm_node.fdm.gear.contacts:
		if not gc.wheel or wheels.has(gc.name):
			continue
		if int(c.get("spray", 0)) <= 0 and int(c.get("dust", 0)) <= 0:
			continue
		var w := WheelSpray.new()
		w.name = "Wheel_" + str(gc.name)
		w.main = str(gc.get("role", "main")) == "main"
		w.width = float(legs.get(gc.name, {}).get("width_m", 0.2))
		wheels[gc.name] = w
		add_child(w)
	for w in wheels.values():
		w.set_counts(c)
	if washes.is_empty() and int(c.get("wash", 0)) > 0:
		for u in fdm_node.fdm.units:
			var e := EngineWash.new()
			e.name = "Wash%d" % washes.size()
			e.setup(u)
			washes.append(e)
			add_child(e)
	for e in washes:
		e.set_capacity(int(c.get("wash", 0)))


## A wheel landed (a TouchdownDetect event): dust puff if the ground there is dry grass or dirt.
func touchdown(ev: Dictionary) -> void:
	var w: WheelSpray = wheels.get(ev.wheel)
	if w:
		w.touchdown(Props.get_f("environment/wetness"), surface.paved(float(ev.e), float(ev.n)))


func clear() -> void:
	if splash:
		splash.clear()
	for w in wheels.values():
		w.clear()
	for e in washes:
		e.clear()
	_paved.clear()


func _process(dt: float) -> void:
	if splash:
		splash.update(get_viewport().get_camera_3d(), Props.get_f("environment/precip"))
		if splash.emitting and fdm_node and fdm_node.fdm:
			_shelter(fdm_node.fdm)
	if fdm_node == null or fdm_node.fdm == null or (wheels.is_empty() and washes.is_empty()):
		return
	var halt := fdm_node.paused or fdm_node.replaying
	var fd := fdm_node.fdm
	var wet := Props.get_f("environment/wetness")
	var wind: Vector3 = Props.get_v("environment/wind_ned", Vector3.ZERO)
	var drift := Vector3(wind.y, 0.0, -wind.x) * 0.4
	var v := fd.velocity_ned()
	var vel := Vector3(v.y, -v.z, -v.x)
	var gs := Vector2(v.x, v.y).length()
	var fwd := Vector3(v.y, 0.0, -v.x).normalized() if gs > 0.5 else Vector3.ZERO
	_surface_t -= dt
	var check := _surface_t <= 0.0
	if check:
		_surface_t = SURFACE_S
	var n_on := 0
	var n_off := 0
	for name in wheels:
		var w: WheelSpray = wheels[name]
		var on := not halt and float(fd.gear.info.get(name, {}).get("depth", 0.0)) > 0.0
		var p := TouchdownDetect.wheel_enu(fd, name)
		if on and (check or not _paved.has(name)):
			_paved[name] = surface.paved(p.x, p.y)
		w.update(on, FloatingOrigin.to_render_d(p.x, p.y, p.z), vel, fwd, gs, wet, _paved.get(name, true), drift, dt)
		n_on += 1 if on else 0
		n_off += 1 if on and not _paved.get(name, true) else 0
	Props.set_v("ground/unpaved", float(n_off) / float(n_on) if n_on > 0 else 0.0)  # tyre sounds (aircraft.json audio)
	for i in washes.size():
		var e: EngineWash = washes[i]
		if halt:
			e.set_rate(0.0)
			continue
		var key := "unit%d" % i
		if check or not _paved.has(key):
			var hub := Vector3(fd.pos_n, fd.pos_e, fd.pos_d) + Basis(fd.q) * fd.mb.body_of(e.unit.pos)
			_paved[key] = surface.paved(hub.y, hub.x)
		e.update(fd, wet, _paved[key], drift)


## No splashes under the fuselage or the wings: boxes from the gear contacts (nose to tail, wingtips; the wing box is
## stretched along to cover a swept wing from its main gear to its tips).
func _shelter(fd: FDM) -> void:
	if _boxes.is_empty():
		var lo := 0.0
		var hi := 0.0
		var span := 0.0
		var tip_x := 0.0
		var main_x := 0.0
		for c in fd.gear.contacts:
			var b := fd.mb.body_of(c.pos)  # x forward, y right
			lo = minf(lo, b.x)
			hi = maxf(hi, b.x)
			if absf(b.y) > span:
				span = absf(b.y)
				tip_x = b.x
			if c.wheel and str(c.get("role", "")) == "main":
				main_x = b.x
		var mid := (tip_x + main_x) * 0.5
		_boxes = [Vector4((lo + hi) * 0.5, (hi - lo) * 0.5, maxf(0.06 * span, 0.6), 4.0),
			Vector4(mid, 0.07 * span + absf(tip_x - main_x) * 0.5, span, 4.0)]
	var nose := Basis(fd.q) * Vector3(1.0, 0.0, 0.0)  # NED
	var f := Vector2(nose.y, -nose.x).normalized()  # render x, z
	GroundFxLook.set_shelter(FloatingOrigin.to_render_d(fd.pos_e, fd.pos_n, -fd.pos_d), f, _boxes[0], _boxes[1])


func _exit_tree() -> void:
	surface.finish()
