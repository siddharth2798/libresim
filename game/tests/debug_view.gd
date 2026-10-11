extends Node
## Debug: free camera at a fixed world spot (ENU m), for scenery checks and flicker hunting.
##   godot --path game res://tests/debug_view.tscn -- --airport=VABB --runway=27 \
##     --eye=-50000,37500,300 --at=-56000,37570,5 --wait=8 --out=/tmp/v.png
## With --to=e,n,alt --frames=N the eye then moves in a straight line to `to` over N frames
## (fixed step per frame) and every frame is saved as <shot dir>/p###.png.

var f: Node
var eye := Vector3.ZERO
var at := Vector3.ZERO
var to := Vector3.INF
var wait := 8.0
var frames := 0
var shot := ""
var t := 0.0
var _i := -1


static func _v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--eye="): eye = _v3(a.substr(6))
		elif a.begins_with("--at="): at = _v3(a.substr(5))
		elif a.begins_with("--to="): to = _v3(a.substr(5))
		elif a.begins_with("--wait="): wait = float(a.substr(7))
		elif a.begins_with("--frames="): frames = int(a.substr(9))
		elif a.begins_with("--out="): shot = a.substr(6)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func _aim(cam: CameraRig, p: Vector3) -> void:
	var d := FloatingOrigin.to_render(at) - FloatingOrigin.to_render(p)
	cam._free_enu = p
	cam._look = Vector2(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


func _process(dt: float) -> void:
	var cam: CameraRig = f.get_node("Camera")
	if cam.mode != CameraRig.Mode.FREE:
		cam.set_mode(CameraRig.Mode.FREE)
	t += dt
	if _i < 0:
		_aim(cam, eye)
		if t >= wait:
			if to == Vector3.INF or frames <= 0:
				get_viewport().get_texture().get_image().save_png(shot)
				print("saved ", shot)
				get_tree().quit()
				return
			_i = 0
		return
	# path mode: the image grabbed now is the frame rendered for the previous step
	if _i > 0:
		get_viewport().get_texture().get_image().save_png(shot.get_base_dir().path_join("p%03d.png" % (_i - 1)))
	if _i >= frames:
		print("saved %d frames" % frames)
		get_tree().quit()
		return
	_aim(cam, eye.lerp(to, float(_i) / frames))
	_i += 1
