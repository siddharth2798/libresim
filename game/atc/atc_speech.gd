class_name AtcSpeech
extends RefCounted
## Radio number and spelling formatters (ICAO Annex 10 style), used for the transcript
## (written form) and for the optional voice (spoken form).
## Digit strings (runway, frequency, QNH, squawk, headings, wind) say each digit with the
## ICAO pronunciations: zero one two tree four fife six seven eight niner, "decimal" for the
## point. Round hundreds and thousands (altitude, cloud base) use plain number words:
## 2500 = "two thousand five hundred". Letters use the phonetic alphabet.

const DIGITS := ["zero", "one", "two", "tree", "four", "fife", "six", "seven", "eight", "niner"]
const PLAIN := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
	"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
const TENS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
const NATO := {
	"A": "Alpha", "B": "Bravo", "C": "Charlie", "D": "Delta", "E": "Echo", "F": "Foxtrot", "G": "Golf",
	"H": "Hotel", "I": "India", "J": "Juliett", "K": "Kilo", "L": "Lima", "M": "Mike", "N": "November",
	"O": "Oscar", "P": "Papa", "Q": "Quebec", "R": "Romeo", "S": "Sierra", "T": "Tango", "U": "Uniform",
	"V": "Victor", "W": "Whiskey", "X": "X-ray", "Y": "Yankee", "Z": "Zulu"}
const CALLSIGN_RE := "^[A-Z0-9]{1,2}-?[A-Z0-9]{2,5}$"

static var _digit_run: RegEx
static var _taxiway: RegEx


## "118.1" -> "one one eight decimal one"; letters become phonetic words; other characters are skipped.
static func digits(text: String) -> String:
	var out: Array[String] = []
	for ch in text:
		if ch >= "0" and ch <= "9":
			out.append(DIGITS[int(ch)])
		elif ch == ".":
			out.append("decimal")
		elif NATO.has(ch.to_upper()):
			out.append(NATO[ch.to_upper()])
	return " ".join(out)


## 0..99 in plain words.
static func words(n: int) -> String:
	if n < 20:
		return PLAIN[maxi(n, 0)]
	return TENS[int(n / 10.0)] + ("" if n % 10 == 0 else "-" + PLAIN[n % 10])


## Runway ident: "09" -> "zero niner", "27L" -> "two seven left".
static func runway(ident: String) -> String:
	var num := ""
	var suffix := ""
	for ch in ident:
		if ch >= "0" and ch <= "9":
			num += ch
		else:
			suffix = {"L": "left", "R": "right", "C": "centre"}.get(ch.to_upper(), "")
	return (digits(num) + (" " + suffix if suffix != "" else "")).strip_edges()


## Feet (or metres) rounded to 100: 2500 -> "two thousand five hundred", 800 -> "eight hundred".
static func altitude(value: float) -> String:
	var v := int(round(value / 100.0)) * 100
	if v < 100:
		return "zero"
	var th := int(v / 1000.0)
	var hu := int((v % 1000) / 100.0)
	var parts: Array[String] = []
	if th > 0:
		parts.append((digits(str(th)) if th >= 10 else words(th)) + " thousand")
	if hu > 0:
		parts.append(words(hu) + " hundred")
	return " ".join(parts)


## 118.1 -> "118.1", 122.95 -> "122.95", 118.1 -> never "118.100" (the panel header shows three decimals).
static func frequency_text(mhz: float) -> String:
	var t := "%.3f" % mhz
	while t.ends_with("0") and not t.ends_with(".0"):
		t = t.substr(0, t.length() - 1)
	return t


static func frequency(mhz: float, spoken: bool) -> String:
	var t := frequency_text(mhz)
	return digits(t) if spoken else t


## Wind direction is rounded to 10 degrees; under 2 knots it is "calm".
static func wind(dir_deg: float, kt: float, gust_kt: float, spoken: bool) -> String:
	if kt < 2.0:
		return "calm"
	var d := int(round(dir_deg / 10.0)) * 10 % 360
	if d == 0:
		d = 360
	var spd := str(int(round(kt)))
	var out := ""
	if spoken:
		out = "%s degrees %s knots" % [digits("%03d" % d), digits(spd)]
	else:
		out = "%03d degrees %s knots" % [d, spd]
	if gust_kt > kt + 3.0:
		var g := str(int(round(gust_kt)))
		out += " gusting " + (digits(g) if spoken else g)
	return out


static func visibility(m: float, spoken: bool) -> String:
	if m >= 10000.0:
		return "one zero kilometres or more" if spoken else "10 kilometres or more"
	if m >= 5000.0:
		var km := int(round(m / 1000.0))
		return "%s kilometres" % (digits(str(km)) if spoken else str(km))
	var metres := int(round(m / 100.0)) * 100
	return "%s metres" % (altitude(metres) if spoken else str(metres))


static func temperature(c: float, spoken: bool) -> String:
	var n := int(round(c))
	var t := str(absi(n))
	return ("minus " if n < 0 else "") + (digits(t) if spoken else t)


static func qnh(hpa: float, spoken: bool) -> String:
	var t := str(int(round(hpa)))
	return digits(t) if spoken else t


## Written as given ("VT-FSM"); spoken phonetically ("Victor Tango Foxtrot Sierra Mike").
static func callsign(cs: String, spoken: bool) -> String:
	return digits(cs) if spoken else cs


## Any other text for the voice: runs of digits are read digit by digit.
static func speak_text(s: String) -> String:
	if _digit_run == null:
		_digit_run = RegEx.create_from_string("\\d+")
	var out := ""
	var last := 0
	for m in _digit_run.search_all(s):
		out += s.substr(last, m.get_start() - last) + digits(m.get_string())
		last = m.get_end()
	return out + s.substr(last)


## Taxiway designators in a route text for the voice: " via A, B2" -> " via Alpha, Bravo two".
static func taxiways(s: String) -> String:
	if _taxiway == null:
		_taxiway = RegEx.create_from_string("\\b([A-Z])(\\d*)\\b")
	var out := ""
	var last := 0
	for m in _taxiway.search_all(s):
		out += s.substr(last, m.get_start() - last) + NATO[m.get_string(1)]
		if m.get_string(2) != "":
			out += " " + digits(m.get_string(2))
		last = m.get_end()
	return out + s.substr(last)


## Upper-case, no spaces; "" if it does not look like a registration (VT-FSM, N172SP, G-ABCD).
static func normalize_callsign(s: String) -> String:
	var t := s.strip_edges().to_upper().replace(" ", "")
	var re := RegEx.create_from_string(CALLSIGN_RE)
	return t if re.search(t) != null and t.replace("-", "").length() <= 7 else ""
