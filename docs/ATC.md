# ATC (stage A1: a controller with memory)

Press `` ` `` in flight. The controller answers by text (and, if you switch it on, in the system voice). It knows where you are in a flight, replies only to calls that make sense, speaks up by itself at the right moments and gives short notes (never blocking) when you skip a clearance. Code: `game/atc/` (logic, no nodes), `game/ui/atc_panel.gd` + `atc_transcript.gd` (screen and keys). Phrases: `game/atc/phraseology.json`.

## State machine (`/atc/state`)

```
 ground    parked -> clearance -> taxi -> hold_short -> lined_up -> takeoff
 air                                                              departed -> enroute -> inbound -> final
 landing   landed -> vacated -> (taxi ->) parked
```

| Event | What happens |
|---|---|
| Pilot call (menu) | the pilot's line, the reply 0.6-1.5 s later, the readback; the state changes when the reply is heard |
| Aircraft moves on its own | `atc_monitor.gd` follows it: parked -> taxi (moving), hold_short (stopped near a runway / holding position), lined_up (on the runway, aligned, stopped), takeoff (rolling above 30 kt), departed (airborne 1.5 s), enroute (15 km out), landed (touchdown), vacated (off the runway), parked (stopped at a stand after landing) |
| Jump of more than 400 m (F5, loaded flight) | state is rebuilt from the world (a loaded flight restores its own `/atc/*` first) |

Pilot calls (`atc_state.gd`, `INTENTS`): `atis`, `clearance`, `pushback`, `taxi`, `ready`, `inbound`, `final`, `goaround`, `taxi_stand`, plus `say_again` and `tune`. The menu lists only those allowed by `AtcState.available()` for the current state, at most six, keys 1-6.

Unprompted (monitor): "contact Tower" when you stop at the holding point on another unit, "cleared for takeoff" 3 s after you line up if "line up and wait" was given (or as you roll), "contact Approach" or "frequency change approved, squawk VFR" above 500 ft, "report final" at 5.5 nm, "cleared to land" when a busy runway frees up, "vacate runway, contact Ground" after touchdown, a reminder if COM1 is still on the old unit 25 s after a handover, a note when COM1 fails.

Notes (advisories): no takeoff clearance, no landing clearance below ~200 ft on the approach (a go-around is advised), entering a runway without a clearance. Calm wording, one note per kind per flight (armed again after parking), never blocking.

## Which unit answers (`atc_facilities.gd`, `facilities.json`)

Frequencies come from the airport data (ATIS, CLD/DEL, GND, TWR, APP; only 118-137 MHz units). Services are covered by the next unit when one is missing: clearance DEL > GND > TWR, ground GND > TWR, approach APP > TWR, no ATIS = the tower gives airport information (Pune has only a tower, which does everything).

| Mode | When | Behaviour |
|---|---|---|
| published | the airport has frequencies | the right unit must be tuned; wrong unit of the same airport redirects ("contact Tower 118.1"); no unit on the frequency = no reply and a hint; the menu offers *Tune COM1 to ...* |
| any | large/medium airport without frequencies, or listed in `controlled_unpublished` (VAJJ) | answered as "<name> Tower" on any frequency |
| uncontrolled | small fields and heliports without frequencies | only blind calls, logged; nobody answers; no clearances, no notes |
| none | no airport within 8 km (ground) / 80 km (air) | no calls |

A dead COM1 (failure `com1`) says it is dead (squawk 7600 text); an unpowered one says to switch on the master and avionics (no note unless you try to call).

## Training lessons

When a lesson is active (`Session.training != ""`) ATC is silent: the monitor sets `silent`, which suppresses every unprompted call and note, and clearances count as given (`/atc/cleared_takeoff`, `cleared_land` true). The state still follows the flight. The panel never opens by itself in a lesson (only after you pick a call yourself). Lesson steps, markers and grading never read `/atc/*`.

## Properties

`/atc/state`, `airport`, `runway`, `squawk` (stable per flight), `callsign`, `info` (ATIS letter), `cleared`, `cleared_takeoff`, `cleared_land`, `lineup_ok`, `handoff`, `pushed`, `arrived`, `flags`, `last_tx`, `last_instr`, `facility` (the unit COM1 is tuned to), `log` (last 30 transmissions), `stamp`. Saved flights include `atc/` (`core/situation.gd`); a restored copy is told apart by `stamp` and adopted. Set `atc/rwy_busy` true to make a runway occupied (the controller says "continue approach" and clears you when it frees up; there is no traffic to do it yet).

## Phrase file (`phraseology.json`)

`section -> key -> unit role (ATIS DEL GND TWR APP or *) -> template | [variants]`. Sections: `pilot` (your calls; `blind_*` for uncontrolled fields), `readback`, `controller`, `advisory`, `system`. Slots: `{callsign} {fac} {fac2} {apt} {rwy} {wind} {qnh} {squawk} {info} {vis} {temp} {clouds} {alt} {alt_limit} {freq} {freq2} {pos} {where} {join} {opt_via} {opt_info} {opt_route} {opt_wx}`; `opt_*` may be empty. The transcript uses the written form (`09`, `1012`, `118.1`); the voice uses the spoken form from `atc_speech.gd`: ICAO digits (zero one two tree four fife six seven eight niner, "decimal"), runway 09 = "zero niner", frequency 118.1 = "one one eight decimal one", QNH and squawk digit by digit, call sign phonetic; round hundreds and thousands in plain words (2500 ft = "two thousand five hundred").

Add a phrase: add a key in the right section (a role-specific entry beats `*`), use only known slots (`AtcPhraseology.SAMPLE`; the test `test_atc_every_phrase_fills_cleanly` fills every template written and spoken), then call it from `atc_replies.gd` (reply to a pilot call) or `atc_monitor.gd` (unprompted). Add a slot: fill it in `AtcController.slots()`, give it a sample value in `AtcPhraseology.SAMPLE`, and a format in `AtcPhraseology._slot()` if it is not plain text.

Add a facility or fix a name: `facilities.json` (`names`, `controlled_unpublished`, `departure_routes` = optional VFR departure text per airport, empty = generic clearance). Frequencies belong to the airport data (`tools/05_airports_navaids.py`).

## Settings

Call sign: `UserOptions` `callsign` (default VT-FSM; `Session.setup.callsign` overrides when present), validated by `AtcSpeech.normalize_callsign()`. Voice: `UserOptions` `atc_voice` (off by default), also V in the open menu. The Options page block is `atc/atc_options_box.gd` (`AtcOptionsBox`: call sign field with validation and the voice checkbox); add `right.add_child(AtcOptionsBox.new())` to `ui/menu/options_page.gd` (not done in A1: that folder was being reworked).

## Tests and debug

`tests/test_atc.gd` (formatters, phrases, facility rules, geometry, panel placement), `tests/test_atc_flow.gd` (full departure and arrival with a fake world, `atc_fixture.gd`), `tests/test_atc_rules.gd` (advisories once, lessons silent, wrong frequency, uncontrolled fields, COM1 failure, ATIS letter, say again) and `tests/test_atc_session.gd` (save/load, the menu over every state, the session publishing `/atc/*`). `tests/debug_atc.tscn` plays a departure or arrival in the real scene and saves screenshots (see the header of `debug_atc.gd`); the `panels` e2e scenario opens and closes the panel.

## Next stages

- **A2 traffic:** AI aircraft in the pattern and on the ground; `rwy_free` and "line up and wait" become real, traffic calls ("traffic, Cessna on final") and sequencing.
- **A3 voice and radio sound:** recorded or neural voices (Piper) and real radio recordings (squelch, static). A1 has the OS text-to-speech only, no synthesized radio effects (project rule: real recordings only).
