class_name AtcVoice
extends RefCounted
## Optional voice for the radio transcript ("ATC voice" in UserOptions, off by default): the
## operating system's text-to-speech through core/speech_service.gd, the same door as
## ui/callouts.gd (nothing is touched while the option is off). The controller and the pilot get
## different voices if the system has more than one English voice (else the pilot is a little
## lower in pitch). The spoken text is the transmission in ICAO form (atc_speech.gd): "runway
## zero niner, wind two seven zero degrees".
## No radio squelch / static effects here: the project rule is real recordings only, no
## synthesized placeholders. TODO stage A3: recorded or neural (Piper) voices with real radio
## effects, replacing this system voice.


## Is a system voice ready? Only asks (and starts the probe) while the ATC voice option is on:
## with it off this is false without touching the engine's text-to-speech.
func available() -> bool:
	if not enabled():
		return false
	SpeechService.request()
	return SpeechService.available()


## Called a few times a second while the radio runs: with the option on, starts the one-time probe
## and lets it finish early (listing the voices takes ~0.4 s once) instead of at the first call.
func poll() -> void:
	if enabled():
		SpeechService.request()
		SpeechService.status()


## True while the option is on, the probe has finished and found no voice (for the panel hint).
func missing() -> bool:
	return enabled() and SpeechService.status() == SpeechService.Status.NONE


static func enabled() -> bool:
	return bool(UserOptions.get_v("atc_voice"))


## Say one released transmission ({kind, spoken, ...}); system notes are not spoken.
func speak(entry: Dictionary) -> void:
	if not enabled() or str(entry.get("kind", "")) == "system":
		return
	var pilot := str(entry.get("kind", "")) == "pilot"
	SpeechService.speak(str(entry.get("spoken", "")), SpeechService.Kind.PILOT if pilot else SpeechService.Kind.CONTROLLER)
