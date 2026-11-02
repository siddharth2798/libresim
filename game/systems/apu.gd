class_name Apu
extends Node
## The APU of an aircraft whose config.json has "apu" (fdm/apu_model.gd), as a system node: FdmNode adds
## it as a child. Reads controls/apu_master and controls/apu_start (held); publishes apu/running (source
## available), apu/n_pct, apu/starting, apu/ff_kgs; its fuel flow is burnt through fdm.extra_burn_kgs.
## Saved with a flight situation (group saveable): n and the start latch.

var fdm: FDM
var model: ApuModel


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)


func _physics_process(dt: float) -> void:
	if fdm == null or model == null:
		return
	model.update(dt, Props.get_b("controls/apu_master"), Props.get_b("controls/apu_start"), fdm.fuel_available and fdm.mb.fuel_kg() > 0.0)
	fdm.extra_burn_kgs = model.ff_kgs
	Props.set_v("apu/running", model.running)
	Props.set_v("apu/starting", model.starting)
	Props.set_v("apu/n_pct", model.n * 100.0)
	Props.set_v("apu/ff_kgs", model.ff_kgs)


func save_key() -> String:
	return "apu"


func save_state() -> Dictionary:
	return {"n": model.n if model else 0.0, "starting": model.starting if model else false}


func load_state(d: Dictionary) -> void:
	if model:
		model.n = float(d.get("n", 0.0))
		model.starting = bool(d.get("starting", false))
		model.running = model.n >= ApuModel.AVAIL_N
