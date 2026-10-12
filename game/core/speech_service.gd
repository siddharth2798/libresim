class_name SpeechService
extends RefCounted
## The one door to the operating system's text-to-speech, shared by the training callouts
## (ui/callouts.gd) and the ATC voice (atc/atc_voice.gd).
##
## Nothing here runs at start-up. The engine's TTS is only touched after request() or speak(),
## which callers use only when a voice option (`callouts_voice`, `atc_voice`) is on. The probe
## runs once and is cached:
##   Linux/BSD: libspeechd must exist (file check), then a warm-up call starts the engine's
##     speech-dispatcher connection; about WARMUP_MS later the English voices are listed. Until
##     then speak() is silent (a line or two at the very start may be dropped).
##   Windows / macOS / web: the voices are listed at once.
## No voice found -> status NONE: speak() does nothing, the options stay saved, and one line is
## printed (once). See SpeechBackend for why the warm-up is needed.

enum Status { UNKNOWN, PENDING, READY, NONE }
enum Kind { CALLOUT, CONTROLLER, PILOT }

const WARMUP_MS := 600
const MISSING_NOTE := "No system text-to-speech voice found, so voice stays silent (the setting is kept). On Linux install speech-dispatcher with a voice such as espeak-ng (sudo apt install speech-dispatcher espeak-ng), then restart the game."

static var backend: SpeechBackend = null
static var _status := Status.UNKNOWN
static var _t0 := 0
static var _voices: Array = []
static var _logged := false


## Forget the cached probe (tests). A fake backend can be passed in.
static func reset(fake: SpeechBackend = null) -> void:
	backend = fake
	_status = Status.UNKNOWN
	_t0 = 0
	_voices = []
	_logged = false


static func _be() -> SpeechBackend:
	if backend == null:
		backend = SpeechBackend.new()
	return backend


## Start the one-time probe (does nothing if it already ran). Call it only when a voice option is on.
static func request() -> void:
	if _status != Status.UNKNOWN:
		return
	var be := _be()
	if not be.has_tts():
		_give_up("this build has no text-to-speech on this platform")
	elif not be.needs_warmup():
		_load()
	elif not be.lib_present():
		_give_up("libspeechd is not installed")
	else:
		be.touch()
		_t0 = be.now_ms()
		_status = Status.PENDING


## Probe state; finishes a pending probe once the warm-up time has passed. Never starts one.
static func status() -> Status:
	if _status == Status.PENDING and _be().now_ms() - _t0 >= WARMUP_MS:
		_be().touch()  # waits for the connection if it is still being made
		_load()
	return _status


static func available() -> bool:
	return status() == Status.READY


## One calm line for the Options page when voice cannot work ("" otherwise).
static func note() -> String:
	return MISSING_NOTE if status() == Status.NONE else ""


## The system voice id for a kind of speaker: callouts and the controller use the first English
## voice, the pilot the second when there is one.
static func voice_for(kind: Kind) -> String:
	if _voices.is_empty():
		return ""
	return str(_voices[1]) if kind == Kind.PILOT and _voices.size() > 1 else str(_voices[0])


## Say a line. Silent when no voice is ready (also during the first moments of the warm-up).
static func speak(text: String, kind := Kind.CALLOUT, interrupt := false, rate := 1.05) -> void:
	if text == "":
		return
	request()
	if not available():
		return
	var pitch := 0.88 if kind == Kind.PILOT and _voices.size() < 2 else 1.0  # same voice: pilot a little lower
	_be().say(text, voice_for(kind), pitch, rate, interrupt)


static func _load() -> void:
	_voices = _be().voices()
	if _voices.is_empty():
		_give_up("the system has no English voice")
	else:
		_status = Status.READY


static func _give_up(why: String) -> void:
	_status = Status.NONE
	if not _logged:
		_logged = true
		print("libresim: voice is on but there is no usable system text-to-speech (%s)." % why)
