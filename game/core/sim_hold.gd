class_name SimHold
extends RefCounted
## The world holds still while the flight is paused or a replay drives it. FdmNode publishes its paused / replaying
## flags as Props sim/hold every physics tick (and clears it when a flight starts or ends); the weather (Weather,
## CloudPhysics' storm clock), the cloud drift and the clock (SkyTime) and ice accretion (Icing) do not advance while it
## is set, nor do the systems that integrate state over time (battery charge, fuel line, APU, gyro drift: active()).
## Gauges that only follow their inputs with a lag hold only while paused (paused()): in a replay they keep following the
## replayed state, and the replay writes the recorded readings over them (systems/replay.gd).

const PROP := "sim/hold"
const PAUSED := "sim/paused"


static func publish(paused: bool, replaying: bool) -> void:
	Props.set_v(PROP, paused or replaying)
	Props.set_v(PAUSED, paused)


## Paused or replaying.
static func active() -> bool:
	return Props.get_b(PROP)


## Paused (the pause screen), not replaying.
static func paused() -> bool:
	return Props.get_b(PAUSED)
