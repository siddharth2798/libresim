class_name TyreContact
extends RefCounted
## Keeps every tyre of the exterior model on the ground the FDM stands on (docs/TYRE-CONTACT-PLAN.md). The FDM's gear
## contact point sinks by the spring compression c, so the ground is c above it. Each frame a wheel's parts are raised
## (vertically, world space) until the lowest point of its tyre (axle - radius, measured from the meshes in the rest
## pose, so a new aircraft needs no data) is on that ground. Per wheel contact (config.json gear, BOGEY):
##   leg     a pivot in model.surfaces with "compress": <contact> (retractable legs, A320). The retraction hinge stays
##           on the wing. The sliding tube and wheels move up the strut by the spring compression. Torque links and
##           side stays fold about their upper end so the leg shortens instead of the links floating off their mounts.
##           An optional "lift_m" replaces the measured tyre: raise = (c + lift_m) * gear_pos
##   parts   fixed gear (C172): the glb meshes named like a wheel part (WORDS) nearest that contact, or the names in
##           model.wheels {<contact>: [node names]}
##   model   nothing found: the whole model moves by the largest raise of those contacts, so no tyre sinks

const WORDS := ["wheel", "tyre", "tire", "fairing", "spat", "brake", "strut", "fork", "oleo"]
const NOT_TYRE := ["brake", "strut", "fairing", "spat", "fork", "oleo", "door", "well", "bay"]
const MAX_R := 1.5  # m: a part belongs to the nearest wheel contact within this (horizontally)
const NEAR_R := 0.6  # m: "model" fallback, vertices this close (horizontally) to the contact are the tyre

## [contact name, [[Node3D, base position]], [[tyre MeshInstance3D, axle (its local frame), radius m]],
##  lift_m (NAN: measured tyres), use gear_pos, contact structural position (config.json pos_m)]
var _groups: Array = []
var _whole: Array = []  # "model" contacts: [contact name, gap m (lowest vertex - contact, rest pose)]
var _root: Node3D
var _root_base := Vector3.ZERO


## root: the exterior (glb instance or placeholder airframe) under model (the AircraftModel, CG frame, at rest).
static func build(root: Node3D, model: Node3D, f: FDM, sec: Dictionary) -> TyreContact:
	var t := TyreContact.new()
	t._root = root
	t._root_base = root.position
	var contacts := {}  # name -> rest position in the model frame
	var spos := {}  # name -> structural position
	for c in f.gear.contacts:
		if c.wheel:
			contacts[c.name] = _local(f.mb.body_of(c.pos))
			spos[c.name] = c.pos
	var surfaces: Dictionary = sec.get("surfaces", {})
	var done := {}
	for n in surfaces:
		var s: Dictionary = surfaces[n]
		var pv := root.find_child("pivot_" + n, true, false) as Node3D
		if pv and s.has("compress") and contacts.has(str(s.compress)):
			var sliders := _named(pv, ["sliding", "wheel", "lower"])
			if sliders.is_empty():
				sliders = [pv]
			var ms: Array = []
			for mv in sliders:
				if mv is MeshInstance3D:
					ms.append(mv)
				ms.append_array((mv as Node).find_children("*", "MeshInstance3D", true, false))
			var ty := _tyres(ms)
			var lift := float(s.lift_m) if s.has("lift_m") else NAN
			var cn := str(s.compress)
			var nodes := sliders.map(func(nd): return [nd, (nd as Node3D).position])
			t._groups.append([cn, nodes, _axles(ty if not ty.is_empty() else ms, model), lift, true, spos[cn], _links(pv)])
			done[cn] = true
	var parts := {}  # contact -> [Node3D]
	var named: Dictionary = sec.get("wheels", {})
	for cn in named:
		if contacts.has(cn) and not done.has(cn):
			parts[cn] = []
			for nm in named[cn]:
				var nd := root.find_child(str(nm), true, false)
				if nd is Node3D:
					parts[cn].append(nd)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name).to_lower()
		if not WORDS.any(func(w): return nm.contains(w)):
			continue
		var p := _xf(mi, model) * (mi as MeshInstance3D).get_aabb().get_center()
		var best := ""
		var bd := MAX_R
		for cn in contacts:
			var d := Vector2(p.x - contacts[cn].x, p.z - contacts[cn].z).length()
			if d < bd:
				bd = d
				best = cn
		if best != "" and not done.has(best) and not named.has(best):
			if not parts.has(best):
				parts[best] = []
			parts[best].append(mi)
	for cn in contacts:
		if done.has(cn):
			continue
		var nodes: Array = parts.get(cn, [])
		nodes = nodes.filter(func(a): return not nodes.any(func(b): return b != a and b.is_ancestor_of(a)))
		var ty := _tyres(nodes)
		var ax := _axles(ty if not ty.is_empty() else nodes.filter(func(n): return n is MeshInstance3D), model)
		if ax.is_empty():
			t._whole.append([cn, _gap_near(root, model, contacts[cn])])
			continue
		t._groups.append([cn, nodes.map(func(nd): return [nd, nd.position]), ax, NAN, false, spos[cn]])
	return t


## Raise the wheel parts (or the model) for the FDM's current compressions and attitude; model: the
## AircraftModel (its transform is the FDM's pose). Call after the pose animation.
func update(f: FDM, model: Node3D) -> void:
	var gp := float(f.fcs.get("gear_pos")) if "gear_pos" in f.fcs else 1.0
	for g in _groups:
		var comp := float(f.gear.compression.get(g[0], 0.0))
		var up := 0.0
		if not is_nan(g[3]):
			up = (comp + float(g[3])) * gp
		else:
			for e in g[1]:
				(e[0] as Node3D).position = e[1]  # the unraised pose
			var bc := f.mb.body_of(g[5])
			var cw := model.global_transform * _local(bc)  # the contact point, render space
			var cn := Basis(f.q) * bc  # NED offset from the CG
			var n0: float = f.pos_n + cn.x
			var e0: float = f.pos_e + cn.y
			var h0: float = f.ground_height.call(n0, e0)
			up = -INF
			for a in g[2]:  # the lowest tyre of the group touches; the ground under its axle (slopes)
				var axle: Vector3 = (a[0] as MeshInstance3D).global_transform * (a[1] as Vector3)
				var d := axle - cw
				var ground := cw.y + comp + float(f.ground_height.call(n0 - d.z, e0 + d.x)) - h0
				up = maxf(up, ground - (axle.y - float(a[2])))
			if g[4]:
				up *= gp
		for e in g[1]:
			var nd: Node3D = e[0]
			nd.position = e[1] + nd.get_parent().global_transform.basis.inverse() * Vector3(0.0, up, 0.0)
		if g.size() > 6:
			var stroke := comp * (gp if g[4] else 1.0)
			for link in g[6]:
				_fold(link, stroke)
	if not _whole.is_empty():
		var up := -INF
		for w in _whole:
			up = maxf(up, float(f.gear.compression.get(w[0], 0.0)) - w[1])
		_root.position = _root_base + _root.get_parent().global_transform.basis.inverse() * Vector3(0.0, up, 0.0)


## For tests and debug: {contact name: "leg" | "parts" | "model"}.
func modes() -> Dictionary:
	var out := {}
	for g in _groups:
		out[g[0]] = "leg" if g[4] else "parts"
	for w in _whole:
		out[w[0]] = "model"
	return out


## Nodes under the gear pivot whose name contains one of `words`, the node itself and not its children.
static func _named(n: Node, words: Array) -> Array:
	var out: Array = []
	for ch in n.get_children():
		if not ch is Node3D:
			continue
		var nm := String(ch.name).to_lower()
		if words.any(func(w): return nm.contains(w)):
			out.append(ch)
		else:
			out.append_array(_named(ch, words))
	return out


## Torque links and side stays: [node, rest position, rest basis, upper hinge, lower tip, length], mesh space.
static func _links(pv: Node3D) -> Array:
	var out: Array = []
	for nd in _named(pv, ["torque", "slave"]):
		var mi := nd as MeshInstance3D
		if mi == null or mi.mesh == null:
			var found := (nd as Node).find_children("*", "MeshInstance3D", true, false)
			mi = found[0] if not found.is_empty() else null
		if mi == null or mi.mesh == null:
			continue
		var ends := _ends(mi)
		var hinge: Vector3 = ends[0]
		var tip: Vector3 = ends[1]
		out.append([nd, (nd as Node3D).position, (nd as Node3D).basis, hinge, tip, hinge.distance_to(tip)])
	return out


## The highest and lowest vertices of a link (mesh space): the upper mount and the end that follows the oleo.
static func _ends(mi: MeshInstance3D) -> Array:
	var top := Vector3.ZERO
	var bot := Vector3.ZERO
	var hi := -INF
	var lo := INF
	for si in mi.mesh.get_surface_count():
		for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			var p: Vector3 = v
			if p.y > hi:
				hi = p.y
				top = p
			if p.y < lo:
				lo = p.y
				bot = p
	return [top, bot]


## Fold a link about its upper end so the lower end rises `stroke` metres along the strut.
static func _fold(link: Array, stroke: float) -> void:
	var nd: Node3D = link[0]
	var rest_pos: Vector3 = link[1]
	var rest_basis: Basis = link[2]
	var hinge: Vector3 = link[3]
	var tip: Vector3 = link[4]
	var length: float = link[5]
	var s := clampf(stroke, 0.0, length * 0.85)
	var a := tip - hinge
	var b := a + Vector3(0.0, s, 0.0)
	if a.length() < 1e-4 or b.length() < 1e-4:
		nd.position = rest_pos
		nd.basis = rest_basis
		return
	nd.basis = rest_basis * Basis(Quaternion(a.normalized(), b.normalized()))
	nd.position = rest_pos + rest_basis * hinge - nd.basis * hinge


## Body frame (x nose, y right, z down, from the CG) -> model frame (-Z nose, +X right, +Y up).
static func _local(b: Vector3) -> Vector3:
	return Vector3(b.y, -b.z, -b.x)


## The tyre meshes among nodes (named like a wheel / tyre, not a brake, strut, fairing ...).
static func _tyres(nodes: Array) -> Array:
	return nodes.filter(func(n):
		var nm := String(n.name).to_lower()
		return n is MeshInstance3D and ["wheel", "tyre", "tire"].any(func(w): return nm.contains(w)) \
			and not NOT_TYRE.any(func(w): return nm.contains(w)))


## [[mesh, axle in its local frame (its bounds' centre), radius (axle - lowest vertex, model frame, rest)]].
static func _axles(meshes: Array, model: Node3D) -> Array:
	var out := []
	for mi in meshes:
		if not mi is MeshInstance3D or (mi as MeshInstance3D).mesh == null:
			continue
		var c: Vector3 = (mi as MeshInstance3D).get_aabb().get_center()
		var low := _lowest(mi, model, Vector2.INF, 0.0)
		if is_finite(low):
			out.append([mi, c, (_xf(mi, model) * c).y - low])
	return out


## "model" fallback: the lowest vertex of any mesh within NEAR_R (horizontally) of the contact, minus its height.
static func _gap_near(root: Node3D, model: Node3D, contact: Vector3) -> float:
	var low := INF
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		low = minf(low, _lowest(mi, model, Vector2(contact.x, contact.z), NEAR_R))
	return low - contact.y if is_finite(low) else 0.0


static func _lowest(mi: MeshInstance3D, model: Node3D, near: Vector2, r: float) -> float:
	var low := INF
	if mi.mesh == null:
		return low
	var xf := _xf(mi, model)
	for si in mi.mesh.get_surface_count():
		for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			var p: Vector3 = xf * v
			if near == Vector2.INF or Vector2(p.x, p.z).distance_to(near) < r:
				low = minf(low, p.y)
	return low


## Transform of node n in model's frame (walks the parents: works before the model is in the tree).
static func _xf(n: Node, model: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != model:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
