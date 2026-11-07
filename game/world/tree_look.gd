class_name TreeLook
extends RefCounted
## Impostor sway and the stable per-instance colour seed. tree.gdshader uses the same
## sway numbers (uniforms set from here): none at the trunk base, a few centimetres at
## the crown, one cycle every SWAY_PERIOD_S. Trees has no quality flag, so the sway is
## this small on every preset. yaw_column is the atlas column tree.gdshader picks
## (camera on the tree's local +Z is column 0, the same yaw as tree_atlas.gdshader).

const SWAY_PERIOD_S := 4.5
const SWAY_CROWN_M := 0.045


## Metres of horizontal sway. height_01 is 0 at the trunk base and 1 at the crown.
static func sway_amplitude(height_01: float) -> float:
	return SWAY_CROWN_M * clampf(height_01, 0.0, 1.0)


static func sway_m(height_01: float, time_s: float, phase: float) -> float:
	return sin(TAU * time_s / SWAY_PERIOD_S + phase) * sway_amplitude(height_01)


## Same bits for the same index. Feeds colour_unit, which is stored in INSTANCE_CUSTOM.
static func colour_hash(index: int) -> int:
	var n: int = index * 747796405 + 2891336453
	n = (n ^ (n >> 13)) * 1274126177
	return n ^ (n >> 16)


## 0..1 tint seed for land cell (ci, cj). channel 0 is hue, 1 is value. Stable, no time.
static func colour_unit(ci: int, cj: int, channel: int) -> float:
	var h: int = absi(colour_hash(ci * 131 + cj * 17 + channel * 104729))
	return float(h % 100003) / 100003.0


## Nearest of `yaws` baked views. cam_x / cam_z is the camera in the tree's local XZ.
static func yaw_column(cam_x: float, cam_z: float, yaws: int) -> int:
	var yaw: float = atan2(cam_x, cam_z)
	var col: int = int(floor(yaw / TAU * float(yaws) + 0.5))
	return posmod(col, yaws)
