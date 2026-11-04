class_name Callsign
extends RefCounted
## The pilot's call sign: the tail number painted on the aircraft AND the registration used on the radio.
## Pure helpers, no nodes. One rule for everyone (registration_paint.gd, atc_session.gd, CallsignField):
##   typed()    what the pilot chose: Session.setup.callsign ("" = never typed = "untouched"). It is saved with the setup
##              (user://last_flight.json) and may come from --callsign=.
##   default_of(def)   the aircraft's own registration: aircraft.json registration.text (C172 VT-LBR, A320 VT-ZZA),
##              else FALLBACK.
##   effective(def)    typed(), else default_of(def). So an untouched call sign follows the aircraft (switch C172 to
##              A320 and the tail goes from VT-LBR to VT-ZZA); a typed one stays when the aircraft changes.
## The old Options field kept the call sign in options.cfg (UserOptions "callsign", default VT-FSM): migrate_legacy() moves a
## value the pilot had typed there into Session.setup.callsign once, at start (interactive runs only), and puts the option back to
## its default; nothing reads that option any more.
## Session.setup.callsign only ever holds a valid, upper-case call sign (or "" or what --callsign= gave).
## Validation is AtcSpeech.normalize_callsign: letters and digits with one optional dash after the first 1-2
## characters, 3 to 7 letters / digits (MAX_CHARS with the dash). The painter scales any such text into the
## box of aircraft.json registration targets (aspect kept), so every valid call sign fits; "VT-ABCDE" is the longest.

const FALLBACK := "VT-FSM"  # when neither the pilot nor the aircraft names one (also the old Options default)
const MAX_CHARS := 8  # characters in the text field, dash included


## "" when `text` is not a valid call sign, else it upper-cased, spaces removed ("vt abc" -> "VTABC").
static func clean(text: String) -> String:
	return AtcSpeech.normalize_callsign(text)


## What a field may hold while typing: upper-case, only A-Z 0-9 and "-", at most MAX_CHARS. Never fails.
static func filter_typing(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "-":
			out += ch
	return out.substr(0, MAX_CHARS)


## A short reason a half-typed text is not (yet) a call sign; "" when it is one or the field is empty.
static func problem(text: String) -> String:
	if text.strip_edges() == "" or clean(text) != "":
		return ""
	return "3 to 7 letters or digits, one dash allowed, e.g. VT-ABC"


## The call sign the pilot typed ("" = untouched).
static func typed() -> String:
	return clean(str(Session.setup.get("callsign", "")))


## Pure: the call sign to adopt from the old Options value when the setup has none ("" = nothing to move: the setup already
## has one, or the old value is invalid or is the old default).
static func legacy_to_adopt(setup_callsign: String, legacy: String) -> String:
	var l := clean(legacy)
	if clean(setup_callsign) != "" or l == "" or l == clean(str(UserOptions.DEFAULTS.callsign)):
		return ""
	return l


## Once at start (Session._ready): move a call sign typed in the old Options field into the setup, reset the option, save.
static func migrate_legacy() -> void:
	if not Session.interactive():
		return
	var l := legacy_to_adopt(typed(), str(UserOptions.get_v("callsign")))
	if l == "":
		return
	Session.setup.callsign = l
	UserOptions.set_v("callsign", UserOptions.DEFAULTS.callsign)
	Session.save()


## The aircraft's own registration (aircraft.json registration.text), `fallback` when it has none.
static func default_of(def: AircraftDef, fallback := FALLBACK) -> String:
	var sec := def.section("registration") if def != null else {}
	return section_default(sec, fallback)


## The same from a registration section (RegistrationPaint.text_for has the section, not the definition).
static func section_default(section: Dictionary, fallback := FALLBACK) -> String:
	var t := clean(str(section.get("text", "")))
	return t if t != "" else fallback


## typed(), else the aircraft's default.
static func effective(def: AircraftDef) -> String:
	var t := typed()
	return t if t != "" else default_of(def)


## True when the pilot never typed one: the call sign follows the aircraft.
static func is_untouched() -> bool:
	return typed() == ""


## Store what the pilot typed (a valid call sign) or "" to go back to the aircraft's own. False and nothing stored when
## `text` is not empty and not valid.
static func store(text: String) -> bool:
	var t := clean(text)
	if t == "" and text.strip_edges() != "":
		return false
	Session.setup.callsign = t
	return true
