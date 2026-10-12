# Airbus A320 for libresim: plan

Status: plan only (PLAN.md §8a "Airbus A320 (final stages)" and M10). Nothing built yet.

## Source: FlightGear "A320-family" (GitHub `legoboyvdlp/A320-family`, mirrored at git.nayala.duckdns.org/fly/A320-family)

- A very complete A320 for FlightGear: variants A320-200 (CFM56-5B4, IAE V2527) and A320neo (LEAP-1A26, PW1127G).
- Licence: **GNU GPL version 2** (README.copyright.md: "under the terms of version 2", no "or later"). Copyright Josh Davidson (flight dynamics lead), Jonathan Redpath, merspieler, Matthew Maring, Thorsten Herrmann, Semir Gebran, and the contributors of the 3D, sound and display work (see its `Docs` and `README.copyright.md`).
- Layout we care about: `FDE/` (JSBSim flight dynamics: aero, mass, gear), `Engines/` (JSBSim turbofans), `Systems/` (JSBSim systems: FBW, FADEC, FCS, fuel, hydraulic, electrical, APU, FWC), `Models/` (AC3D exterior and flight deck, animations), `Sounds/` (engine, cockpit, GPWS, hydraulic), `Nasal/` (displays, MCDU, FMGC logic).
- The repo is about 700 MB (liveries, textures, sounds). We fetch only what we need (sparse checkout, like `data/raw/fg/c172p`).
- Licence handling: libresim code is GPL-2.0-or-later, and docs/LICENSING.md already vendors GPL-2.0-only fgdata models, so the precedent exists. The A320 data and model are GPL-2.0-only; the combined distribution is then GPL-2.0. **Recommendation:** ship the A320 as a separate "aircraft pack" (downloaded by `run.sh`, not in the base release), so the base stays GPL-2.0-or-later and the pack is clearly GPL-2.0 with its authors credited.
- Real airline liveries are trademarks: use the generic/house livery only.

## Scope (recommended: "flyable A320")

In: A320-200 CFM first (neo later); exterior + flight deck model; FDM from the JSBSim data; CFM56 turbofan with FADEC-like thrust and thrust-lever detents; fly-by-wire normal law with protections; autopilot and flight director (FCU modes: HDG, ALT, V/S, SPD/MACH, LOC, APPR with the ILS we already have); autothrust; slats/flaps, spoilers and speedbrake, reversers, autobrake, nosewheel steering; PFD, ND, engine/warning and system displays (ECAM-lite); FCU, pedestal and a MCDU-lite (INIT, F-PLN, PERF); simplified APU/electrical/fuel/hydraulics as state plus failures; real sounds; start-screen entry, checklists, training lessons.

Out for now: full FWC/ECAM logic, pressurisation and oxygen, full FMGC with SIDs/STARs, cabin, passengers animations, the neo and IAE variants.

## Phases

| # | Phase | Deliverable / exit test | Size |
|---|-------|-------------------------|------|
| P0 | Decisions + licence | Scope, pack vs bundle, credits and LICENSING rows written | S |
| P1 | Data tools | `tools/19_a320_fetch.sh` (sparse checkout to `data/raw/fg/a320`), extend `06_jsbsim_to_json.py` for the A320 FDE and CFM56 engine tables; JSBSim reference runs (`08_jsbsim_reference.py` style): stall speeds, Vref at 64 t, takeoff roll, climb rate, cruise fuel flow | M |
| P2 | FDM generalisation | `FDM` loads any aircraft folder; powerplant interface (piston+prop / turbofan); gear config (bogies, steering, autobrake); flaps and slats detents; spoilers; reversers; fuel tanks and APU. **C172 test cards stay green.** A320 test cards match JSBSim | L |
| P3 | Flight control laws + autopilot | FBW normal law (load-factor and roll-rate command, protections: alpha, bank, pitch, overspeed), ground/flare modes; autothrust; AP/FD with FCU modes. **Spike (2 days):** a small interpreter for JSBSim `fcs` components to run `a320-fbw.xml` directly (best fidelity); fall back to hand-written laws if it does not pay off | XL |
| P4 | 3D model | AC3D to glb (`tools/blender/convert_ac.py`), exterior and flight deck, animated surfaces, gear, doors, engine fans; generic livery; lights through `aircraft_lights.gd` | L |
| P5 | Cockpit + displays | Cockpit camera and clickable items (reuse the C172 interaction and zoom); PFD, ND (with route), E/WD, SD drawn in Godot SubViewports on the screen meshes; FCU, pedestal, MCDU-lite; sidestick and thrust-lever input mapping (joystick bindings already exist) | XL |
| P6 | Sounds | Data-driven per-aircraft sound set (generalise `aircraft_audio.gd`); real recordings from the A320-family set (GPL, credited per file in `sounds/SOURCES.md`) | M |
| P7 | Game integration | Aircraft card on the start screen (specs, minimum runway, only suitable airports offered), loadsheet-lite and fuel, checklists, failures (engine fire/failure, hydraulic), damage tuning for 70 t, pushback and jetway with an A320, A320 training lessons (takeoff, ILS approach), ATC airline phraseology | L |
| P8 | QA + release | Unit tests, e2e scenarios, frame-time budget in the cockpit, docs (USAGE, handbook, LICENSING, CREDITS, F12 credits screen), pack build in `tools/package` | M |

Order: P0, P1, P2 first (no visible change, but everything else depends on them), then P3 and P4 in parallel (different files), P5 after both, then P6 to P8.

## Risks

1. **Displays and MCDU** are Nasal/Canvas code in FlightGear, so they must be re-implemented in Godot (P5). Biggest unknown; start with PFD and E/WD, add ND and MCDU after.
2. **FBW parity** with FlightGear: the laws live in JSBSim systems XML fed by Nasal properties. The P3 spike decides between an interpreter and hand-written laws.
3. **Model conversion:** FlightGear effects and shaders are lost in conversion; materials need rework (as for the c172p). Polygon count and texture size need a budget for integrated GPUs.
4. **Licence:** GPL-2.0-only (above). Keep the pack separable and credit every author.
5. **Runways:** the A320 needs about 1,800 m or more. VABB, VAPO and VOCI qualify; short fields must not be offered.
6. Scope creep: freeze the scope above before P3.

## Decisions needed

1. Scope: "flyable A320" as above (recommended), or full systems depth.
2. Variant: A320-200 CFM first (recommended).
3. Packaging: separate downloadable pack (recommended) or bundled in the base release.
4. Cockpit: clickable switches (recommended for the pedestal, FCU and overhead essentials) or keys only.
