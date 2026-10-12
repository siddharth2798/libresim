class_name SpeechBackend
extends RefCounted
## The only place that touches DisplayServer text-to-speech and the file system probe for it.
## core/speech_service.gd owns the policy (when to probe, caching); tests swap this class for a
## fake (tests/test_speech.gd).
##
## Why a warm-up exists (Godot 4.7, Linux): the first tts_* call creates the speech-dispatcher
## client and connects to the daemon on a background thread. tts_get_voices_for_language() right
## after that first call sees no connection yet and prints 'ERROR: Parameter "synth" is null.
## at: get_voices (platform/linuxbsd/tts_linux.cpp:197)' even when espeak-ng works. tts_is_speaking()
## creates the client without that error, and it takes the client's lock, so a second call waits
## for the connection to finish.

## Where the dynamic loader would find libspeechd (Godot opens libspeechd.so.2 itself).
const LIB_DIRS := ["/usr/lib", "/usr/lib64", "/lib", "/lib64", "/usr/local/lib", "/app/lib", "/run/current-system/sw/lib",
	"/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu", "/usr/lib/arm-linux-gnueabihf", "/usr/lib/riscv64-linux-gnu",
	"/usr/lib/i386-linux-gnu", "/lib/x86_64-linux-gnu", "/lib/aarch64-linux-gnu"]
const LIB_NAME := "libspeechd.so.2"


func has_tts() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


## Only the speech-dispatcher platforms connect asynchronously and can lack the library.
func needs_warmup() -> bool:
	return OS.get_name() in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]


## Is libspeechd installed? File checks only; never calls into the engine's TTS code.
func lib_present() -> bool:
	var dirs: Array = LIB_DIRS.duplicate()
	for d in OS.get_environment("LD_LIBRARY_PATH").split(":", false):
		dirs.append(d)
	for d in dirs:
		if FileAccess.file_exists(str(d).path_join(LIB_NAME)):
			return true
	return false


func now_ms() -> int:
	return Time.get_ticks_msec()


## Harmless engine call that creates the TTS client (and waits for its connection on a second call).
func touch() -> void:
	DisplayServer.tts_is_speaking()


func voices() -> Array:
	return DisplayServer.tts_get_voices_for_language("en")


func say(text: String, voice: String, pitch: float, rate: float, interrupt: bool) -> void:
	DisplayServer.tts_speak(text, voice, 70, pitch, rate, 0, interrupt)
