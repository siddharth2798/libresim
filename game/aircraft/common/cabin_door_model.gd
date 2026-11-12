class_name CabinDoorModel
extends RefCounted
## The modelled passenger door of a CabinDoorPanel (A320: models/doors.glb from tools/blender/a320_door.py), in place of the
## code-built grid panel. Nodes per door <id>: <id>_leaf (the door; under the panel's hinge, so it moves with
## CabinDoorPanel.offset and never turns), <id>_handle (door control handle: down = CLOSED / LOCKED, lifted fully up over the
## plug travel, which unlocks the door and raises it off its stops; stays up while open), <id>_lock_locked / _unlocked (green /
## red locking indicator, switched with the handle), <id>_arm (hinge arm, origin on its pivot pin in the forward frame; turns
## about the vertical by the swing angle, its end <id>_arm_end staying on the door's fitting), <id>_frame (the doorway lining,
## sill, stops, assist handles and the galley beyond) and <id>_mask (the painted outline).
## The exterior skin has no hole, so the doorway is drawn through a stencil portal: the mask writes PORTAL_REF where it is seen
## (in front of the skin, behind anything nearer), a second pass resets the depth there to the far plane, then the frame and
## a stencil-reading copy of the leaf, handle and arm draw with normal depth inside it. Slide arming stays DISARMED (lever up,
## safety pin and streamer in), the cabin-pressure and slide-armed lights stay off: doors open only on the ground at a stand.

const HANDLE_DEG := 165.0  # handle travel: hanging down against the door -> pointing up
const PORTAL_REF := 90  # stencil value of a visible doorway
const PRIO_MASK := -3  # transparent-pass order: mask, depth reset, then the doorway contents
const PRIO_CLEAR := -2
const PRIO_PORTAL := -1
const CABIN_GLOW := 0.35  # the cabin beyond is lit: emission = albedo x this
const DEPTH_RESET := preload("res://aircraft/common/door_portal_depth.gdshader")

var leaf: Node3D
var handle: Node3D  # pivot on the handle hinge (child of the panel's hinge)
var arm: Node3D  # pivot on the arm pin
var arm_end: Node3D
var frame: Node3D
var mask: Node3D
var locked: Node3D
var unlocked: Node3D
var _side := -1.0
var _arm_base := Vector3.ZERO
var _attach0 := Vector3.ZERO  # the arm's door end with the door shut (panel frame)
var _hinge: Node3D
var _hinge_base := Vector3.ZERO


## Moves the door <id> out of `scene` into `panel` (static parts) and `hinge` (parts that ride on the door). s: structural ->
## panel-local, as CabinDoorPanel uses. Null when the glb has no such door.
static func attach(panel: Node3D, hinge: Node3D, scene: PackedScene, id: String, s: Callable, side: float) -> CabinDoorModel:
	var root := scene.instantiate() as Node3D
	if root.find_child(id + "_leaf", true, false) == null:
		root.free()
		return null
	var m := CabinDoorModel.new()
	m._side = side
	m._hinge = hinge
	m._hinge_base = hinge.position
	var to_local := _glb_to_local(s)
	var on_door := Transform3D(Basis(), hinge.position).affine_inverse()
	m.leaf = _take(root, id + "_leaf", hinge, on_door * to_local)
	m.locked = _take(root, id + "_lock_locked", hinge, on_door * to_local)
	m.unlocked = _take(root, id + "_lock_unlocked", hinge, on_door * to_local)
	m.handle = _pivot(root, id + "_handle", hinge, on_door * to_local)
	m.arm = _pivot(root, id + "_arm", panel, to_local)
	m._arm_base = m.arm.position
	m.arm_end = m.arm.find_child(id + "_arm_end", true, false) as Node3D
	m.frame = _take(root, id + "_frame", panel, to_local)
	m.mask = _take(root, id + "_mask", panel, to_local)
	root.free()
	m._attach0 = m.arm_end_point()
	for n in [m.leaf, m.locked, m.unlocked, m.handle, m.arm]:
		_portal_copy(n)
	_portal_only(m.frame)
	_make_mask(m.mask, panel)
	return m


## pos 0..1 as CabinDoorPanel._apply: the handle comes up over the plug travel, the arm follows the plug and then swings.
func apply(pos: float) -> void:
	var shown := pos > 0.01
	for n in [arm, frame, mask]:
		n.visible = shown
	var k := smoothstep(0.0, CabinDoorPanel.PLUG, pos)
	var a := deg_to_rad(CabinDoorPanel.SWING_DEG) * smoothstep(CabinDoorPanel.PLUG, 1.0, pos)
	handle.rotation = Vector3(0.0, 0.0, -_side * deg_to_rad(HANDLE_DEG) * k)
	locked.visible = k < 0.05
	unlocked.visible = not locked.visible
	arm.position = _arm_base + Vector3(_side * CabinDoorPanel.PLUG_OUT_M * k, CabinDoorPanel.PLUG_UP_M * k, 0.0)
	arm.rotation = Vector3(0.0, _side * a, 0.0)


## Where the arm's door end is now (panel frame).
func arm_end_point() -> Vector3:
	var t := arm.transform
	var n: Node = arm_end
	var chain := Transform3D.IDENTITY
	while n != null and n != arm:
		chain = (n as Node3D).transform * chain
		n = n.get_parent()
	return (t * chain).origin


## Where the door's arm fitting is now (panel frame): it rides on the hinge.
func door_fitting_point() -> Vector3:
	return _attach0 + (_hinge.position - _hinge_base)


## glb (Y-up export of the structural frame) -> panel-local, from the structural -> local map s.
static func _glb_to_local(s: Callable) -> Transform3D:
	var o: Vector3 = s.call(Vector3.ZERO)
	var bx: Vector3 = (s.call(Vector3.RIGHT) as Vector3) - o
	var by: Vector3 = (s.call(Vector3.UP) as Vector3) - o
	var bz: Vector3 = (s.call(Vector3.BACK) as Vector3) - o
	return Transform3D(Basis(bx, bz, -by), o)  # glTF x = struct x, y = struct z, z = -struct y


static func _rel(root: Node, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		t = (at as Node3D).transform * t
		at = at.get_parent()
	return t


## Re-parents glb node `name` under `parent` keeping where it is (`base`: glb -> parent frame).
static func _take(root: Node, name: String, parent: Node3D, base: Transform3D) -> Node3D:
	var n := root.find_child(name, true, false) as Node3D
	var t := base * _rel(root, n)
	_detach(n)
	n.transform = t
	parent.add_child(n)
	return n


## Like _take, but under a plain pivot node at the glb node's origin with axes of `parent` (rotations are in that frame).
static func _pivot(root: Node, name: String, parent: Node3D, base: Transform3D) -> Node3D:
	var n := root.find_child(name, true, false) as Node3D
	var t := base * _rel(root, n)
	var p := Node3D.new()
	p.name = name + "_pivot"
	p.position = t.origin
	parent.add_child(p)
	_detach(n)
	n.transform = Transform3D(t.basis, Vector3.ZERO)
	p.add_child(n)
	return p


## Out of the glb scene, owner cleared (the panel is not that scene).
static func _detach(n: Node) -> void:
	n.owner = null
	for c in n.find_children("*", "", true, false):
		c.owner = null
	n.get_parent().remove_child(n)


static func _meshes(n: Node) -> Array:
	var out: Array = [n] if n is MeshInstance3D else []
	out.append_array(n.find_children("*", "MeshInstance3D", true, false))
	return out


static func _portal_mat(src: Material, glow: float) -> StandardMaterial3D:
	var m := (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
	m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_EQUAL
	m.stencil_reference = PORTAL_REF
	m.render_priority = PRIO_PORTAL
	m.next_pass = null
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = m.albedo_color * glow
	return m


## Opaque as usual, plus a pass inside the portal (the part of the door or arm that is behind the skin plane shows there).
static func _portal_copy(n: Node) -> void:
	for mi: MeshInstance3D in _meshes(n):
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i)
			var own := (base as StandardMaterial3D).duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
			own.next_pass = _portal_mat(base, 0.0)
			mi.set_surface_override_material(i, own)


static func _portal_only(n: Node) -> void:
	for mi: MeshInstance3D in _meshes(n):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, _portal_mat(mi.mesh.surface_get_material(i), CABIN_GLOW))


static func _make_mask(n: Node3D, panel: Node3D) -> void:
	var mi := _meshes(n)[0] as MeshInstance3D
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var w := StandardMaterial3D.new()
	w.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	w.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	w.albedo_color = Color(0, 0, 0, 0)
	w.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	w.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	w.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	w.stencil_reference = PORTAL_REF
	w.render_priority = PRIO_MASK
	mi.material_override = w
	var reset := MeshInstance3D.new()  # same mesh: far depth inside the portal
	reset.name = "PortalDepthReset"
	reset.mesh = mi.mesh
	reset.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := ShaderMaterial.new()
	sh.shader = DEPTH_RESET
	sh.render_priority = PRIO_CLEAR
	reset.material_override = sh
	mi.add_child(reset)
