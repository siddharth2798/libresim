extends Node
## Helper of debug_overhead_shake: runs before the camera rig and holds the cockpit eye's seat dip at zero.


func _process(_dt: float) -> void:
	Props.set_v("fdm/load_factor", 1.0)
	var cam := get_tree().root.find_child("Camera", true, false) as CameraRig
	if cam != null:
		cam._seat = Vector2.ZERO
