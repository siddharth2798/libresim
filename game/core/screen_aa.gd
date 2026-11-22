class_name ScreenAA
extends RefCounted
## Screen-space edge smoothing (Viewport.screen_space_aa) for the graphics presets. One rule on every machine:
## - each preset names its filter in the key `post_aa` ("smaa" | "fxaa" | "off"): the filter used when no temporal
##   method runs. Every preset says "smaa": SMAA 1x keeps texture detail that FXAA blurs, for a small extra cost
##   that scales with the render scale (Godot runs it before the bilinear upscale, so Low pays for 0.7² of the pixels);
## - TAA and FSR2 already smooth edges over time, so with either one the filter is off (never two post AA passes);
## - Options > Graphics "Edge smoothing" (UserOptions "edge_smoothing": Auto | SMAA | FXAA | Off) replaces the preset's
##   filter; Auto keeps it. --aa=<smaa|fxaa|off> replaces both for one run (before / after benches and screenshots).
## SMAA and FXAA run on the Forward+ and Mobile renderers (Vulkan, Direct3D 12, Metal). The Compatibility renderer
## (OpenGL fallback on GPUs without those) ignores screen_space_aa; only MSAA works there.

const MODES := {"off": Viewport.SCREEN_SPACE_AA_DISABLED, "fxaa": Viewport.SCREEN_SPACE_AA_FXAA,
	"smaa": Viewport.SCREEN_SPACE_AA_SMAA}
const DEFAULT := "smaa"
## Options > Graphics "Edge smoothing" -> filter ("" = the preset's own).
const CHOICES := {"Auto": "", "SMAA": "smaa", "FXAA": "fxaa", "Off": "off"}

static var _cli := _read_cli()


static func _read_cli() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aa="):
			var m := a.substr(5).to_lower()
			if MODES.has(m):
				return m
			push_warning("--aa=%s: want smaa, fxaa or off" % m)
	return ""


## The filter a preset spec names. Specs from before `post_aa` carried a bool `fxaa`: on maps to the filter that
## replaced FXAA in the presets (SMAA), off stays off.
static func filter_of(spec: Dictionary) -> String:
	if spec.has("post_aa"):
		var f := str(spec.post_aa).to_lower()
		return f if MODES.has(f) else DEFAULT
	return DEFAULT if bool(spec.get("fxaa", false)) else "off"


## The "Edge smoothing" option as a filter ("" = Auto). Unknown or missing values (an options file from before the
## option, a hand edit) are Auto; old lower-case values are accepted.
static func choice_filter(choice: Variant) -> String:
	var c := str(choice) if choice != null else "Auto"
	if CHOICES.has(c):
		return CHOICES[c]
	return c.to_lower() if MODES.has(c.to_lower()) else ""


## The filter that runs: off under TAA / FSR2 (`temporal`), else --aa=, else the option, else the preset.
static func filter_for(spec: Dictionary, temporal: bool, choice: Variant = "Auto") -> String:
	if temporal:
		return "off"
	if _cli != "":
		return _cli
	var c := choice_filter(choice)
	return c if c != "" else filter_of(spec)


## The Viewport.screen_space_aa value for filter_for().
static func mode_for(spec: Dictionary, temporal: bool, choice: Variant = "Auto") -> Viewport.ScreenSpaceAA:
	return MODES[filter_for(spec, temporal, choice)]
