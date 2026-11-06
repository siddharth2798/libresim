# Airbus A320 for libresim: plan

Goal: a flyable A320-family twin-jet. P0 to P9 are done; the A320 is selectable and flyable. P10's pack script is in. The base release still includes the aircraft, and there is no pack download URL. Current state, what is crude or missing, and how to test: [A320-STATUS.md](A320-STATUS.md). Licence audit: [LICENSING.md](LICENSING.md), `third_party/a320-family/SOURCE.md`.

The A320 drove the per-aircraft data design (`AircraftDef`, `aircraft.json`). Each fix is a data-driven mechanism (a new `aircraft.json` section or hook), with C172 behaviour and tests unchanged.

## Source
FlightGear "A320-family" (https://github.com/legoboyvdlp/A320-family, branch `dev`). Development there is on hold.
- Variants: A320-200 (CFM56-5B4, IAE V2527) and A320neo (LEAP-1A26, PW1127G). We use the A320-200 CFM.
- Pinned commit: `fec1ecba767c8fffd145337b27012e89c01e3ade`. `tools/22_a320_fetch.sh` makes a sparse checkout in `data/raw/fg/a320` (about 2.5 MB: `FDE/ Engines/ Systems/`, top-level files, `Docs/THANKS.md`).
- Used: `FDE/` (flight dynamics), `Engines/` (turbofans), `Systems/` (FBW, FADEC, FCS, spoilers, fuel, hydraulic, electrical, APU), later `Models/` (exterior and flight deck). Not fetched: `Sounds/`, `Fonts/`, `Nasal/`, `WebPanel/`.
- What the converter takes and leaves: [tools/A320_DATA_NOTES.md](../tools/A320_DATA_NOTES.md).

## Licence verdict
- The licence is GPL-2.0 only ("version 2", no "or later"; the maintainer confirms it in PR #425). Shipping it makes the combined distribution GPL-2.0. libresim is v2-or-later, so this is allowed; it cannot become GPLv3. A separate pack only isolates it. We do not rely on an "aggregate" argument.
- **JSBSim FDE, engine and system XML (data):** used under GPL-2.0 with notices: upstream copyright lines kept, licence text shipped, a dated notice of changes (`third_party/a320-family/SOURCE.md` change log, `derived_from` in every generated file), source published.
- **3D models and textures:** used under the repository's published GPL-2.0, with some provenance risk (the base aircraft is Immersive Design Group's A32X; its original repository has no licence statement and the model headers could not be read). The owner decided to send no provenance question upstream, rely on the published licence and comply fully. Blender edits are for quality, polygon budget and trademark hygiene, never to hide the source. Mitigation: the A320 is a separate, withdrawable pack, and its model can be replaced by an own generic twin-jet (P8 path B) without code changes.
- **Not cleared, not fetched, not shipped, not credited as used:** all sounds (no per-file provenance, TTS voices of an unchecked service, two sound PRs rejected over provenance); all fonts (the ECAM font is credited only as "GPL" and comes from FlyByWire, whose tree is GPLv3 code plus CC-BY-NC assets); Nasal / Canvas / WebPanel code (a close GDScript port would be a GPL-2.0-only derivative, so we write our own from public behaviour); the splash screen; the CC0 sample listed in `THANKS.md`.
- **Not OK:** real airline liveries (AAL, AUA, DAL, SWR ship upstream), Airbus / airline / engine-maker logos and decals, navdata, anything from FlyByWire A32NX.
- **Trademarks:** "Airbus" and "A320" are Airbus trademarks. The UI says "A320-family twin-jet airliner" with a non-affiliation disclaimer, a generic house livery, and logos stripped from textures.

## Scope
In: A320-200 CFM; exterior and flight-deck model; FDM from the JSBSim data; CFM56 with FADEC-like thrust and lever detents; hand-written fly-by-wire normal law with protections; AP / FD / ATHR with FCU modes (HDG, ALT, V/S, SPD/MACH, LOC, APPR with the existing ILS); slats / flaps, spoilers, speedbrake, reversers, autobrake, nosewheel steering; PFD, ND, E/WD, SD, FCU, pedestal, MCDU-lite; simplified APU / electrical / fuel / hydraulics as state plus failures; own or verified sounds; start-screen entry, checklists, training lessons.

Out for now: full FWC / ECAM logic, pressurisation, oxygen, full FMGC with SIDs / STARs, cabin and passengers, the neo and IAE variants.

## Phases
| # | Phase | Result | Status |
|---|---|---|---|
| P0 | Decisions, licence gate | This plan; `third_party/a320-family/` (LICENSE, README.copyright.md, THANKS.md, SOURCE.md); rows in `docs/LICENSING.md`; `CREDITS.md` entry | done |
| P1 | Data pipeline | `tools/22_a320_fetch.sh` (also `./run.sh --a320`); `tools/06_jsbsim_to_json.py a320` writes `game/aircraft/a320/{config,aero}.json`; `tools/23_a320_reference.py` writes `tools/a320_reference.json` (JSBSim oracle numbers); `tools/test_jsb_convert.py`; `tools/A320_DATA_NOTES.md` | done |
| P2 | FDM generalisation | `FDM.new(AircraftDef)` for any aircraft folder; engine interface `Powerplant` / `Thruster` / `PowerUnit`; N engines and tanks with per-engine controls and failures; gear `role` / `brake_group`; aero inputs (mach, slat, spoiler, speedbrake, gear position, ground effect); turbine thrust tables, TSFC, N2 / EGT, FADEC detents, reverse thrust, relight / start; THS trim, flap / slat detents; gear retract, steering, autobrake, anti-skid; hand-written normal law `fdm/fbw_law.gd` tuned against the JSBSim reference (oracle, not interpreted at runtime); APU, hydraulics, electrical, fuel transfer, autoflight; `tests/test_generic_aircraft.gd`. C172 test cards stay green | done. Gaps: bleed air, pipe-tank feed; takeoff roll about 30 % shorter and stall speed 10-12 % above public figures, as in JSBSim |
| P3 | Controls | `aircraft.json` `controls` section (actions, axis to property map, lever detents); per-engine lever writers; table-driven `joystick_controls.gd` and key handlers; new actions (thrust detents, reverse, speedbrake, gear, autobrake, engine master / mode, APU, rudder trim, tiller, FCU); controls page, HUD card and key reference filtered by aircraft | done |
| P4 | Gauges and displays | `panel.json` loader with non-square rects and `span`; display scripts in `ui/displays/` (PFD, ND, E/WD, SD, FCU, MCDU-lite) through the SubViewport -> quad -> click-forwarding pipeline; new publishers (air data, Vls / Vsw / Vmax, radio altitude, attitude, per-engine N1 / N2 / EGT / FF / oil, FMA / FD). Own drawing, written from public behaviour | done. No ND VOR / ILS / PLAN modes. MCDU files a lateral route (INIT, F-PLN, DIR) and selects NAV. Synthetic runway fixes, managed vertical and a top of descent. ATS routes from the AAI eAIP expand in FROM/TO. No published SID/STAR |
| P5 | Replay and saves | `ReplayChannels` from an `aircraft.json` `replay` section; situations get `engines/ ap/ apu/ fcu/` prefixes and a `save_state()/load_state()` hook on systems | done |
| P6 | Ground ops | `pushback {straight_m, radius_m, speed_mps}`; tug size; `ground.cg_to_door_m`; taxi half-width and max speed; follow-me gap; service-vehicle offsets; jetway docking; stand class and runway filtering (`min_runway_m`: the A320 needs about 1,800 to 2,100 m; VABB, VAPO, VOCI qualify) | done. Docking has exceptions: long ways, right-side gates |
| P7 | ATC airline profile | `aircraft.json` `atc {profile: airline, wake, telephony, callsign_style}`; airline calls from IFR clearance to stand; fictional telephony, no real airline names; GA profile unchanged | done |
| P8 | Model, cockpit, sounds | Path A (taken): upstream model converted and improved under its GPL-2.0 (pivots, PBR materials, GPU budget, screen meshes, generic livery, no marks, registration areas) with scripted headless Blender in `tools/blender/`. Path B (fallback): own generic twin-jet (`tools/blender/build_airliner.py`). Sounds: own or verified CC0 / CC-BY only, per-file `sounds/SOURCES.md`; per-engine mixing in `aircraft_audio.gd` | done, path A. Engine layers are a turbojet stand-in. Original stall horn and lite GPWS beeps (altitude, sink rate, autopilot disconnect) |
| P9 | Game integration | `aircraft.json` / `config.json` / `aero.json` (limits per setting, damage thresholds for about 70 t, payload in kg, fixed `registration`, `radio_type`, cameras, ground footprint 37.6 x 34.1 x 11.8 m); per-aircraft callouts (V1, rotate, 100 kt, retard, minimums); airliner failure list; checklists; aircraft page fuel in kg | done. Training lessons stay C172-only |
| P10 | QA, packaging, release | `tools/package/make_pack.sh` for a separate A320 pack (own LICENSE GPL-2.0, `README.copyright.md`, NOTICE, source offer); `run.sh` optional download; docs (USAGE "Adding an aircraft", handbook, F12 credits) | pack script done (`make_pack.sh`, `test_make_pack.sh`, USAGE, CREDITS). No download URL: `./run.sh --a320` fetches the JSBSim clone only. `make_release.sh` still packages the whole game, A320 included |

## Risks
1. Displays and MCDU are Nasal / Canvas upstream, so they are re-implemented in Godot. PFD and E/WD first, ND and MCDU after.
2. FBW laws live in JSBSim systems XML fed by Nasal properties. Decision: hand-written normal law with JSBSim as oracle. `tools/A320_DATA_NOTES.md` says what running `a320-fbw.xml` headless needs, if the interpreter route is revisited.
3. Model conversion loses FlightGear effects and shaders; materials need rework within a polygon and texture budget for integrated GPUs.
4. GPL-2.0-only plus the model provenance risk. Keep the pack separable and credit every author.
5. The A320 needs about 1,800 m or more; short fields must not be offered.

## Decisions
1. Model: upstream model under its published GPL-2.0, improved in Blender, notices kept, separate withdrawable pack; own generic twin-jet as fallback.
2. Control laws: hand-written normal law, JSBSim as oracle.
3. Scope: "flyable A320".
4. Naming: "A320-family twin-jet airliner", non-affiliation disclaimer, generic livery.
5. Packaging: separate GPL-2.0 pack.
6. Variant: A320-200 CFM56 first; neo / IAE later.
7. Provenance: no upstream question; rely on the published licence and comply fully.
