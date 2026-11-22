class_name SimHold
extends RefCounted
## The world holds still while the flight is paused or a replay drives it. FdmNode publishes its paused / replaying
## flags as Props sim/hold every physics tick (and clears it when a flight starts or ends); the weather (Weather,
## CloudPhysics' storm clock), the cloud drift and the clock (SkyTime) and ice accretion (Icing) do not advance while it
## is set.

const PROP := "sim/hold"


static func publish(paused: bool, replaying: bool) -> void:
	Props.set_v(PROP, paused or replaying)


static func active() -> bool:
	return Props.get_b(PROP)
