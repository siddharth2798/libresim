extends Node
## System text-to-speech door (core/speech_service.gd): the probe is lazy and cached, speak() is
## silent when no voice exists, and nothing touches the engine's TTS at start-up while the voice
## options are off (that used to print 'Parameter "synth" is null' on every game start).


class FakeBackend extends SpeechBackend:
	var tts := true
	var warmup := true
	var lib := true
	var voice_list: Array = ["v0", "v1"]
	var clock := 0
	var touches := 0
	var lists := 0
	var said: Array = []

	func has_tts() -> bool:
		return tts

	func needs_warmup() -> bool:
		return warmup

	func lib_present() -> bool:
		return lib

	func now_ms() -> int:
		return clock

	func touch() -> void:
		touches += 1

	func voices() -> Array:
		lists += 1
		return voice_list

	func say(text: String, voice: String, pitch: float, rate: float, interrupt: bool) -> void:
		said.append([text, voice, pitch, rate, interrupt])

	func engine_calls() -> int:
		return touches + lists + said.size()


var _saved := {}


func _options(voice_on: bool) -> void:
	UserOptions.get_v("callouts_voice")  # load defaults / the file, then change in memory only (never saved)
	for k in ["callouts_voice", "atc_voice"]:
		if not _saved.has(k):
			_saved[k] = UserOptions._v[k]
		UserOptions._v[k] = voice_on


func _restore() -> void:
	for k in _saved:
		UserOptions._v[k] = _saved[k]
	_saved.clear()
	SpeechService.reset()


func test_speech_probe_is_lazy_and_cached() -> String:
	var be := FakeBackend.new()
	SpeechService.reset(be)
	if SpeechService.status() != SpeechService.Status.UNKNOWN or be.engine_calls() != 0:
		return "status() must not start the probe"
	SpeechService.request()
	SpeechService.request()
	if SpeechService.status() != SpeechService.Status.PENDING or be.touches != 1 or be.lists != 0:
		return "warm-up should run once, voices not listed yet (touches %d, lists %d)" % [be.touches, be.lists]
	be.clock = SpeechService.WARMUP_MS
	var ok := SpeechService.available()
	for i in 5:
		SpeechService.status()
		SpeechService.request()
	var res := "" if ok and be.lists == 1 and be.touches == 2 else "ready %s, voices listed %d x, touches %d" % [ok, be.lists, be.touches]
	SpeechService.reset()
	return res


func test_speech_is_silent_without_a_voice() -> String:
	var be := FakeBackend.new()
	be.lib = false
	SpeechService.reset(be)
	SpeechService.speak("hello")
	SpeechService.speak("again", SpeechService.Kind.PILOT, true)
	var res := ""
	if SpeechService.status() != SpeechService.Status.NONE or SpeechService.available():
		res = "no library should end in NONE"
	elif be.engine_calls() != 0:
		res = "no engine TTS call is allowed when libspeechd is missing (%d)" % be.engine_calls()
	elif SpeechService.note() == "" or not SpeechService.note().contains("espeak-ng"):
		res = "note should say how to install a voice"
	var be2 := FakeBackend.new()
	be2.voice_list = []
	SpeechService.reset(be2)
	SpeechService.request()
	be2.clock = 1000
	SpeechService.speak("hello")
	if res == "" and (SpeechService.status() != SpeechService.Status.NONE or not be2.said.is_empty()):
		res = "an empty voice list should end in NONE and stay silent"
	var be3 := FakeBackend.new()
	be3.tts = false
	SpeechService.reset(be3)
	SpeechService.speak("hello")
	if res == "" and (SpeechService.status() != SpeechService.Status.NONE or be3.engine_calls() != 0):
		res = "no TTS feature should end in NONE without engine calls"
	SpeechService.reset()
	return res


func test_speech_nothing_at_startup_when_options_off() -> String:
	var be := FakeBackend.new()
	SpeechService.reset(be)
	_options(false)
	var co := Callouts.new()
	add_child(co)
	co._process(0.1)
	co.speak("airspeed alive")
	co._show("rotate", 0)
	var v := AtcVoice.new()
	v.poll()
	v.speak({"kind": "atc", "spoken": "test"})
	var avail := v.available()
	var missing := v.missing()
	var note1 := SpeechNote.new("atc_voice")
	var note2 := SpeechNote.new("callouts_voice")
	add_child(note1)
	add_child(note2)
	note1.refresh()
	note2.refresh()
	var shown := note1.visible or note2.visible
	for n in [co, note1, note2]:
		n.queue_free()
	var calls := be.engine_calls()
	var st := SpeechService.status()
	_restore()
	if calls != 0 or st != SpeechService.Status.UNKNOWN:
		return "text-to-speech touched with voices off (%d engine calls, status %d)" % [calls, st]
	return "" if not avail and not missing and not shown else "voice off must report nothing (available %s, missing %s, note shown %s)" % [avail, missing, shown]


func test_speech_voice_on_without_voice_is_inert() -> String:
	var be := FakeBackend.new()
	be.lib = false
	SpeechService.reset(be)
	_options(true)
	var co := Callouts.new()
	add_child(co)
	co.speak("rotate")
	co._show("rotate", 0)
	var v := AtcVoice.new()
	v.poll()
	v.speak({"kind": "atc", "spoken": "test"})
	var note := SpeechNote.new("callouts_voice")
	add_child(note)
	note.refresh()
	var shown := note.visible
	var missing := v.missing()
	for n in [co, note]:
		n.queue_free()
	var calls := be.engine_calls()
	_restore()
	if calls != 0:
		return "%d engine calls without a speech library" % calls
	return "" if shown and missing else "the Options note and the radio hint should show (note %s, hint %s)" % [shown, missing]


func test_speech_voice_choice_and_pitch() -> String:
	var be := FakeBackend.new()
	be.warmup = false  # Windows / macOS: voices listed at once
	SpeechService.reset(be)
	SpeechService.speak("one", SpeechService.Kind.CONTROLLER)
	SpeechService.speak("two", SpeechService.Kind.PILOT)
	SpeechService.speak("three", SpeechService.Kind.CALLOUT, true, 1.15)
	var res := ""
	if be.touches != 0 or be.lists != 1 or be.said.size() != 3:
		res = "immediate platforms: touches %d, lists %d, said %d" % [be.touches, be.lists, be.said.size()]
	elif be.said[0][1] != "v0" or be.said[1][1] != "v1" or be.said[2][1] != "v0":
		res = "controller and callouts use the first voice, the pilot the second: %s" % [be.said]
	elif not is_equal_approx(be.said[1][2], 1.0) or not is_equal_approx(be.said[2][3], 1.15) or not be.said[2][4]:
		res = "pitch / rate / interrupt not passed through: %s" % [be.said]
	var one := FakeBackend.new()
	one.warmup = false
	one.voice_list = ["only"]
	SpeechService.reset(one)
	SpeechService.speak("pilot", SpeechService.Kind.PILOT)
	if res == "" and (one.said.size() != 1 or one.said[0][1] != "only" or not is_equal_approx(one.said[0][2], 0.88)):
		res = "a single voice should be used for the pilot with a lower pitch: %s" % [one.said]
	SpeechService.reset()
	return res
