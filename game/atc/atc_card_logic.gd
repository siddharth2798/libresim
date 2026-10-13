class_name AtcCardLogic
extends RefCounted
## What the message card and the radio bar show, as pure logic (ui/atc_card.gd draws it): every
## released transmission (controller, note, radio message) goes into one calm card that stays
## 6-8 s after its last line (longer text stays longer); the pilot's own call and read-back join it as
## small muted lines instead of being shown on their own. The latest message of the controller also
## stays in the bar for BAR_LIFE seconds (a bare "readback correct" does not replace it). Time is passed in, so tests drive it directly.

const BAR_LIFE := 20.0
const MIN_LIFE := 6.0
const MAX_LIFE := 8.0
const MAX_LINES := 4

var lines: Array = []  # [{kind, who, text}] of the card on screen, oldest first
var left := 0.0        # s the card still has
var bar_who := ""
var bar_text := ""
var bar_left := 0.0


## A transmission was released ({kind, who, text, ack?}). True when it started a new card, false when
## it joined the card that is still on screen.
func feed(e: Dictionary) -> bool:
	var fresh := left <= 0.0 or lines.is_empty()
	if fresh:
		lines = []
	lines.append({"kind": str(e.kind), "who": str(e.who), "text": str(e.text)})
	if lines.size() > MAX_LINES:
		lines = lines.slice(lines.size() - MAX_LINES)
	left = life_for(lines)
	if str(e.kind) != "pilot" and not bool(e.get("ack", false)):
		bar_who = str(e.who)
		bar_text = str(e.text)
		bar_left = BAR_LIFE
	return fresh


func tick(dt: float) -> void:
	left = maxf(left - dt, 0.0)
	bar_left = maxf(bar_left - dt, 0.0)
	if left <= 0.0:
		lines = []
	if bar_left <= 0.0:
		bar_text = ""
		bar_who = ""


func alive() -> bool:
	return left > 0.0 and not lines.is_empty()


## The bar's line: "Pune Ground: ..." while the latest message is fresh, else "".
func bar_line() -> String:
	return "%s: %s" % [bar_who, bar_text] if bar_text != "" else ""


## How long a card stays after its last line: 6 s plus reading time for what the controller said, at most 8 s.
static func life_for(card_lines: Array) -> float:
	var chars := 0
	for l in card_lines:
		if str(l.kind) != "pilot":
			chars += str(l.text).length()
	return clampf(5.0 + float(chars) * 0.03, MIN_LIFE, MAX_LIFE)


## The card's header: the controller who is speaking ("Pune Ground"), else "ATC note" for a note,
## else "Radio" for the radio's own messages.
static func head_of(card_lines: Array) -> Dictionary:
	for kind in ["atc", "advisory", "system"]:
		for l in card_lines:
			if str(l.kind) == kind:
				match kind:
					"atc":
						return {"text": str(l.who), "tone": "ok"}
					"advisory":
						return {"text": "ATC note", "tone": "warn"}
					_:
						return {"text": "Radio", "tone": "dim"}
	return {"text": "", "tone": "dim"}
