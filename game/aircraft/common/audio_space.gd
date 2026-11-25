class_name AudioSpace
extends RefCounted
## Pure helpers for where a sound is heard from (audio_layers.gd): distance fall-off and Doppler shift of the
## aircraft's exterior layers in the outside views, and the volume easing of loops. No audio server, no Props
## (tests/test_audio_space.gd).

const SOUND_MPS := 340.0  # speed of sound near sea level
const REF_M := 15.0  # an exterior layer plays at its full volume up to this distance (about the chase camera)


## Linear gain of a source `d` metres away: 1 up to ref_m, then inverse distance (-6 dB per doubling) scaled by
## rolloff (1 = physical, less = carries further), never below `floor`.
static func distance_gain(d: float, ref_m := REF_M, rolloff := 1.0, floor := 0.0) -> float:
	if d <= ref_m or ref_m <= 0.0:
		return 1.0
	return maxf(ref_m / (ref_m + rolloff * (d - ref_m)), floor)


## Pitch factor heard from a source closing at `closing_mps` (positive = coming nearer): c / (c - v), clamped.
static func doppler(closing_mps: float) -> float:
	var v := clampf(closing_mps, -0.8 * SOUND_MPS, 0.8 * SOUND_MPS)
	return clampf(SOUND_MPS / (SOUND_MPS - v), 0.5, 2.0)


## One step of first-order easing toward `target` with time constant `tau` seconds (tau or dt 0 = snap).
static func ease(cur: float, target: float, dt: float, tau: float) -> float:
	if tau <= 0.0 or dt <= 0.0:
		return target
	return lerpf(cur, target, 1.0 - exp(-dt / tau))


## Closing speed (m/s) from two distances `dt` apart, low-passed with the previous estimate (tau 0.25 s) so frame
## jitter does not warble the pitch.
static func closing_speed(prev_d: float, d: float, dt: float, prev_v: float) -> float:
	if dt <= 0.0 or prev_d < 0.0:
		return prev_v
	return lerpf(prev_v, (prev_d - d) / dt, 1.0 - exp(-dt / 0.25))
