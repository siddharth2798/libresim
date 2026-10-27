# ATC (stage A1: a controller with memory)

The controller answers by text (and, if you switch it on, in the system voice). It knows where you are in a flight, replies only to calls that make sense, speaks up by itself at the right moments and gives short notes (never blocking) when you skip a clearance. Code: `game/atc/` (logic, no nodes), `game/ui/atc_panel.gd` (keys and wiring), `atc_box.gd` (the bar and the open list), `atc_card.gd` (message card), `atc_transcript.gd` (history). Phrases: `game/atc/phraseology.json`.

## The radio on screen

One obvious next action, nothing else unless you ask for it.

| Look | What it shows |
|---|---|
| **Bar** (always, free flight) | Top-left, level with the flight-data bar: `COM1 118.100 · Pune Tower` (green when a unit answers on that frequency, amber `no facility`, grey when there is nothing to call, red when COM1 is off or failed), the suggested call (`Next: ask Ground for taxi`, assist on), and for 20 s the latest controller message. Click it or press `` ` `` to open. |
| **Message card** | Every transmission you hear arrives as one calm card in the notification stack (top-centre, same style as the other cards): who is speaking and what they said at 16 px, your own call and read-back as small muted lines. It fades 6-8 s after its last line (longer text stays longer). `atc/atc_card_logic.gd` is the logic (tested), `ui/atc_card.gd` draws it. |
| **Taxi instruction** | "Taxi to the apron via P" after landing, "Taxi to runway 27 via A, B - hold short" (T or the Ground call), "Hold short - contact Tower" near the end of a runway route, pushback notes. One compact green-edged card in the same notification stack (top-centre, never over the view), 8-12 s (12 s the first time after landing, 6 s for a plain note), then it fades by itself. **Backspace** dismisses it at once; it also goes when the aircraft was standing and starts taxiing under it (after 4 s and 2 s of movement), when the route ends (stand reached, T clears it) or when a newer instruction replaces it. What stays is a tiny green line under the bar (`Taxi to the apron via P  ·  2177 m`, `Pushback in progress  ·  P to stop`) and a note in the History (`Taxi: ...`, italic). It used to be a centred label that stayed until the route ended. `atc/taxi_banner_logic.gd` is the logic (tested), `ui/taxi_banner.gd` draws it (owned by `GroundOps`), Props `ops/taxi_hint` and `ops/taxi_msg` feed the bar and the History. |
| **Open** | A list of at most 4 plain calls, the suggested one first and highlighted (`Ask Ground for taxi`, `Report ready for departure`, `Report final`, `Report going around`...). **Up/Down** move, **Enter** or **1-4** call, **Esc** or `` ` `` close; a click on a row calls it; the list closes by itself after a call. Small row: **Say again** (A), **History** (H), **Voice** on/off (V). With assist on a note says when the call will retune COM1 (`COM1 will tune to 121.900 (Pune Ground)`). |
| **History** | H (or the History button) replaces the list with the last 30 transmissions, scrollable (wheel or Up/Down), your own lines muted; H again goes back. |

While the radio is open its keys are taken before the rest of the game: Esc does not open the pause menu, H does not toggle the flight-data bar, 1-4 do not change the camera, and the arrow keys do not pitch the aircraft (`Props ui/radio_open`, read by `input/keyboard_controls.gd`). Nothing else is bound to a new letter while it is closed. Shift/Ctrl combinations (Shift+V avionics, Ctrl+H pitot heat) are left alone.

Where it sits (`atc/atc_layout.gd`): the left column beside the flight-data bar is free of other UI in free flight, whatever the panel layout (the 2D panel pieces are bottom-left/right and top-right, the message cards and the taxi card top-centre, the training card only in lessons), so the bar sits at (8, 10) with width `clamp(room left of the flight-data bar, 300, 440)`: 350 px at 1280x720, 440 px at 1920x1080. The open radio grows downwards from there (about 270 px, history 300 px); if something is open under it (checklist, training card, map) it moves to the first free spot instead (`place()`).

## Radio assist (Options, default on)

`UserOptions radio_assist` (Options page, Radio / ATC block; `AtcSession.assist_on()`, set on the controller as `assist` every tick). Logic: `atc/atc_assist.gd` (pure, tested in `tests/test_atc_assist.gd`).

| | Assist on | Assist off (realistic) |
|---|---|---|
| A call needs another unit | COM1 is tuned to it first: the card says `COM1 tuned to 118.100 Pune Tower.` (hook `tune`, the old frequency goes to standby) | the call is redirected or gets no reply, as before; the list offers `Tune COM1 to Pune Delivery 121.850` first |
| Suggestion | `controller.recommended(w)` heads the list, `next_hint(w)` feeds the bar | none (a dead radio is still explained) |
| Tune hints | the monitor's "tune COM1 to ..." reminders are not given (the next call does it) | given after a handover, as before |

`recommended()` follows the flight: parked -> ATIS (only when the airport has an ATIS unit and you have not heard it) -> clearance -> taxi; taxi near a runway / hold short -> ready for departure; lined up -> ask for takeoff clearance; en route within 25 nm -> ask for landing; inbound within 6.5 nm (or once the controller asked) -> report final; vacated -> taxi to parking. In the other states (taxiing far from the runway, rolling, climbing, on final) there is no call and `next_hint()` says what to do instead (`Next: taxi to runway 27, report ready`).

## State machine (`/atc/state`)

```
 ground    parked -> clearance -> taxi -> hold_short -> lined_up -> takeoff
 air                                                              departed -> enroute -> inbound -> final
 landing   landed -> vacated -> (taxi ->) parked
```

| Event | What happens |
|---|---|
| Pilot call (list) | the pilot's line, the reply 0.6-1.5 s later, the readback; the state changes when the reply is heard |
| Aircraft moves on its own | `atc_monitor.gd` follows it: parked -> taxi (moving), hold_short (stopped near a runway / holding position), lined_up (on the runway, aligned, stopped), takeoff (rolling above 30 kt), departed (airborne 1.5 s), enroute (15 km out), landed (touchdown), vacated (off the runway), parked (stopped at a stand after landing) |
| Jump of more than 400 m (F5, loaded flight) | state is rebuilt from the world (a loaded flight restores its own `/atc/*` first) |

Pilot calls (`atc_state.gd`, `INTENTS`): `atis`, `clearance`, `pushback`, `taxi`, `ready`, `inbound`, `final`, `goaround`, `taxi_stand`, plus `say_again` and `tune`. `AtcController.menu()` lists those allowed by `AtcState.available()` for the current state (at most six, with `Tune COM1` when assist is off and `Say again`); the screen shows `AtcController.actions()`: at most four calls, the suggested one first, no `Say again` (it has its own button).

Unprompted (monitor): "contact Tower" when you stop at the holding point on another unit, "cleared for takeoff" 3 s after you line up if "line up and wait" was given (or as you roll), "contact Approach" or "frequency change approved, squawk VFR" above 500 ft, "report final" at 5.5 nm, "cleared to land" when a busy runway frees up, "vacate runway, contact Ground" after touchdown, a reminder if COM1 is still on the old unit 25 s after a handover, a note when COM1 fails.

Notes (advisories): no takeoff clearance, no landing clearance below ~200 ft on the approach (a go-around is advised), entering a runway without a clearance. Calm wording, one note per kind per flight (armed again after parking), never blocking.

## Which unit answers (`atc_facilities.gd`, `facilities.json`)

Frequencies come from the airport data (ATIS, CLD/DEL, GND, TWR, APP; only 118-137 MHz units). Services are covered by the next unit when one is missing: clearance DEL > GND > TWR, ground GND > TWR, approach APP > TWR, no ATIS = the tower gives airport information (Pune has only a tower, which does everything).

| Mode | When | Behaviour |
|---|---|---|
| published | the airport has frequencies | the right unit must be tuned (assist on: the call tunes it); wrong unit of the same airport redirects ("contact Tower 118.1"); no unit on the frequency = no reply and a hint; with assist off the list offers *Tune COM1 to ...* |
| any | large/medium airport without frequencies, or listed in `controlled_unpublished` (VAJJ) | answered as "<name> Tower" on any frequency |
| uncontrolled | small fields and heliports without frequencies | only blind calls, logged; nobody answers; no clearances, no notes |
| none | no airport within 8 km (ground) / 80 km (air) | no calls |

A dead COM1 (failure `com1`) says it is dead (squawk 7600 text); an unpowered one says to switch on the master and avionics (no note unless you try to call).

## Training lessons

When a lesson is active (`Session.training != ""`) ATC is silent: the monitor sets `silent`, which suppresses every unprompted call and note, and clearances count as given (`/atc/cleared_takeoff`, `cleared_land` true). The state still follows the flight. The radio bar stays hidden in a lesson (` still opens the list; the reply to a call you make is a card as usual). Lesson steps, markers and grading never read `/atc/*`.

## Properties

`/atc/state`, `airport`, `runway`, `squawk` (stable per flight), `callsign`, `info` (ATIS letter), `cleared`, `cleared_takeoff`, `cleared_land`, `lineup_ok`, `handoff`, `pushed`, `arrived`, `flags`, `last_tx`, `last_instr`, `facility` (the unit COM1 is tuned to), `log` (last 30 transmissions), `stamp`. Saved flights include `atc/` (`core/situation.gd`); a restored copy is told apart by `stamp` and adopted. Set `atc/rwy_busy` true to make a runway occupied (the controller says "continue approach" and clears you when it frees up; there is no traffic to do it yet).

## Phrase file (`phraseology.json`)

`section -> key -> unit role (ATIS DEL GND TWR APP or *) -> template | [variants]`. Sections: `pilot` (your calls; `blind_*` for uncontrolled fields), `readback`, `controller`, `advisory`, `system`. Slots: `{callsign} {fac} {fac2} {apt} {rwy} {wind} {qnh} {squawk} {info} {vis} {temp} {clouds} {alt} {alt_limit} {freq} {freq2} {pos} {where} {join} {opt_via} {opt_info} {opt_route} {opt_wx}`; `opt_*` may be empty. The transcript uses the written form (`09`, `1012`, `118.1`); the voice uses the spoken form from `atc_speech.gd`: ICAO digits (zero one two tree four fife six seven eight niner, "decimal"), runway 09 = "zero niner", frequency 118.1 = "one one eight decimal one", QNH and squawk digit by digit, call sign phonetic; round hundreds and thousands in plain words (2500 ft = "two thousand five hundred").

Add a phrase: add a key in the right section (a role-specific entry beats `*`), use only known slots (`AtcPhraseology.SAMPLE`; the test `test_atc_every_phrase_fills_cleanly` fills every template written and spoken), then call it from `atc_replies.gd` (reply to a pilot call) or `atc_monitor.gd` (unprompted). Add a slot: fill it in `AtcController.slots()`, give it a sample value in `AtcPhraseology.SAMPLE`, and a format in `AtcPhraseology._slot()` if it is not plain text.

Add a facility or fix a name: `facilities.json` (`names`, `controlled_unpublished`, `departure_routes` = optional VFR departure text per airport, empty = generic clearance). Frequencies belong to the airport data (`tools/05_airports_navaids.py`).

## Settings

Call sign: `UserOptions` `callsign` (default VT-FSM; `Session.setup.callsign` overrides when present), validated by `AtcSpeech.normalize_callsign()`. Voice: `UserOptions` `atc_voice` (off by default), also V in the open radio. Radio assist: `UserOptions` `radio_assist` (on by default, see above). The Options page block is `atc/atc_options_box.gd` (`AtcOptionsBox`: call sign field with validation, the assist checkbox and the voice checkbox), added by `ui/menu/options_page.gd`.

## Tests and debug

`tests/test_atc.gd` (formatters, phrases, facility rules, geometry, panel placement), `tests/test_atc_flow.gd` (full departure and arrival with a fake world, `atc_fixture.gd`), `tests/test_atc_rules.gd` (advisories once, lessons silent, wrong frequency, uncontrolled fields, COM1 failure, ATIS letter, say again) and `tests/test_atc_session.gd` (save/load, the menu over every state, the session publishing `/atc/*`), `tests/test_atc_assist.gd` (suggested call and hint along a departure and arrival, assist on/off tuning, the short list) and `tests/test_atc_radio_ui.gd` (card lifetime logic, card text, bar placement, the box, the keys of the open radio, lessons, arrow keys not pitching, the option). `tests/debug_atc.tscn` plays a departure or arrival in the real scene and saves screenshots of every look at 1280x720 and 1920x1080 (see the header of `debug_atc.gd`); the `panels` e2e scenario opens and closes the radio.

## Next stages

- **A2 traffic:** AI aircraft in the pattern and on the ground; `rwy_free` and "line up and wait" become real, traffic calls ("traffic, Cessna on final") and sequencing.
- **A3 voice and radio sound:** recorded or neural voices (Piper) and real radio recordings (squelch, static). A1 has the OS text-to-speech only, no synthesized radio effects (project rule: real recordings only).
