class_name Gears
extends RefCounted
## Builds the gear of a config: RetractableGear when any contact is retractable, else the plain
## GearGround (the C172's). Use this instead of GearGround.new() so the right class is made.


static func make(cfg: Dictionary) -> GearGround:
	for g in cfg.gear:
		if g.get("retractable", false):
			return RetractableGear.new(cfg)
	return GearGround.new(cfg)
