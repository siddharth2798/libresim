class_name FreeCamera
extends Camera3D
## Debug fly camera. World position is kept in ENU (64-bit) and converted to
## render space each frame, driving the floating origin.
## Controls: right mouse = look, WASD = move, Q/E = down/up, Shift = x10, Ctrl = x0.1,
## mouse wheel = base speed, R = reset to start point, G = snap to 50 m AGL.

@export var start_enu := Vector3(-59540.0, 38628.0, 600.0)  # over Juhu
@export var start_heading_deg := 90.0
@export var speed := 150.0

var enu: Vector3
var yaw := 0.0
var pitch := -0.2
var terrain: TerrainQuadtree


func _ready() -> void:
	far = 160000.0
	near = 0.5
	_reset()


func _reset() -> void:
	enu = start_enu
	yaw = deg_to_rad(-start_heading_deg)
	FloatingOrigin.set_origin(Vector2(enu.x, enu.y))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -1.5, 1.5)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed *= 1.25
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed /= 1.25
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_R:
			_reset()
		elif e.keycode == KEY_G and terrain:
			enu.z = terrain.height_at(enu.x, enu.y) + 50.0


func _process(dt: float) -> void:
	basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var mv := Vector3(
		Input.get_axis("ui_left", "ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q)),
		Input.get_axis("ui_up", "ui_down") + float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	var s := speed
	if Input.is_key_pressed(KEY_SHIFT):
		s *= 10.0
	if Input.is_key_pressed(KEY_CTRL):
		s *= 0.1
	var d := basis * mv.limit_length(1.0) * s * dt  # render-space delta
	enu += Vector3(d.x, -d.z, d.y)
	if terrain:
		enu.z = maxf(enu.z, terrain.height_at(enu.x, enu.y) + 2.0)
	FloatingOrigin.update_focus(enu)
	position = FloatingOrigin.to_render(enu)
