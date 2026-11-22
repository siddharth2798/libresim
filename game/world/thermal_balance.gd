class_name ThermalBalance
extends RefCounted
## Mass balance of the thermals (world/cloud_convection.gd): what goes up in the cells comes down between them. The cell
## field is the fixed cloud coverage noise, so its distribution over one noise tile is sampled once; for a cell threshold
## the sink ratio is mean(up share) / mean(sink share), and sink = ratio x the updraft speed there gives an area-mean
## vertical wind of zero below the cloud.

const N := 96  # samples per side over one noise tile
const KEY_STEP := 0.001  # thresholds are cached at this resolution

static var _field := PackedFloat32Array()
static var _ratios := {}


## The cell field at N x N points over one tile (computed on first use).
static func samples() -> PackedFloat32Array:
	if _field.is_empty():
		_field.resize(N * N)
		for i in N:
			for j in N:
				_field[i * N + j] = CloudConvection.cell_field(Vector2((i + 0.5) / N, (j + 0.5) / N))
	return _field


## Sink speed per unit of updraft speed for cell threshold thr.
static func sink_ratio(thr: float) -> float:
	var key := snappedf(thr, KEY_STEP)
	if _ratios.has(key):
		return _ratios[key]
	var up := 0.0
	var down := 0.0
	for s in samples():
		up += CloudConvection.up_share(s, key)
		down += CloudConvection.down_share(s, key)
	var r := up / maxf(down, 1e-6)
	_ratios[key] = r
	return r
