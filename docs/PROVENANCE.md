# Provenance: is libresim a fork of FlightGear?

Audit date 2026-10-13, repository at commit `d4641ce` plus the working tree. Read-only audit of the code, using scripts and reading the upstream sources. Scripts and downloaded upstream files were kept outside the repository.

## Verdict

**libresim is not a fork of FlightGear, and it is not a fork or port of JSBSim.** It is a separate program, written in GDScript on the Godot engine. It contains no FlightGear or JSBSim source code (no C++, no Nasal, no SimGear, no shared git history).

It does **reuse FlightGear-project and JSBSim material as data**, and by size that material is almost the whole repository:

| Measure | FlightGear / JSBSim origin | Everything else |
|---|---:|---:|
| Bytes of the git repository (86.6 MB) | **96.7 %** (67.1 % if the vendored originals in `third_party/` are left out) | 3.3 % |
| Files, ignoring 335 `.import`/`.uid` files (487 files) | **20.1 %** (12.3 % without `third_party/`) | 79.9 % |
| Bytes of the runtime `game/` folder, without tests (59.9 MB) | **97.2 %** | 2.8 % |
| Lines of code (29,873 lines of GDScript, Python, shell, shaders) | **0 % copied or translated.** 0.6 % (173 lines) re-implement JSBSim's published behaviour | 99.4 % |

Where the derived material is:
- The **3D Cessna 172P exterior, cockpit, textures and 23 sounds** are from the FlightGear c172p aircraft (GPL-2.0-or-later). Textures and sounds are byte-identical copies; the `.glb` models are Blender conversions of the `.ac` models.
- Four **airport models** (pushback tug, fire truck, jetway, bus) and 7 **sounds** are from FlightGear's `fgdata` (GPL-2.0).
- The **aerodynamic model, mass, inertia, gear, tank, engine and propeller data** are JSBSim's `c172p`, `engIO360C` and `prop_75in2f` files (LGPL-2.1), converted to JSON. All 335 numbers in `c172_aero.json` and all 112 propeller table values appear verbatim in the JSBSim files.

Everything that makes it a program is original: the 6-DOF integrator, piston engine, gear, systems, instruments, radios and GPS, ATC, training, weather, terrain streaming, UI and tests. The one honest nuance is that the flight dynamics **data** and the aircraft **model** are not ours, and three small files (`aero.gd`, `table.gd`, `propeller.gd`, 173 code lines) are re-implementations of how JSBSim evaluates that data.

Confidence: **high (about 95 %)** that this is not a fork or derivative of FlightGear's code. About 90 % that no JSBSim or FlightGear source was translated line by line. The residual uncertainty is cross-language: a mechanical test cannot see a hand translation, so that part rests on reading the code (section "Per-module derivation").

## Method

1. **Inventory.** `git ls-files` (822 files) classified by path and extension. `cloc` is not installed, so a small Python counter gave lines, with "code" meaning non-blank lines that are not comment-only. Percentages are given by bytes, by files and by code lines, because each answers a different question.
2. **History.** `git log`: 62 commits by one author, from 2026-09-30 (root commit "M0: project skeleton, plan, data fetch notes") to 2026-10-13. There is no upstream remote and no imported history.
3. **Upstream sources fetched** (into scratch space, never executed): 212 JSBSim C++ files (`src/**`, master, 70,103 lines), JSBSim `c172p.xml`, `engIO360C.xml`, `eng_io320.xml`, `prop_75in2f.xml`; 30 Nasal and XML files of the c172p team's aircraft (tag `version/2024.1.3`: `c172p.xml`, Nasal, Systems, sound, keyboard, checklist), plus its tutorials and `CONTRIBUTING.md` for text checks; 25 FlightGear core C++ files (`src/Instrumentation`, `src/Systems`, `src/Aircraft/controls.cxx`, `src/Input`, `src/Environment`, `release/2024.1`) and 5 FlightGear reference files (`controls.nas`, `keyboard.xml`, `mice.xml`, ...).
4. **Mechanical similarity** (all 311 code files against that whole corpus): lower-cased identifiers and numbers as tokens, 5-gram and 8-gram overlap; exact-line overlap (whitespace removed, 14+ characters); and a renamed-structure 12-gram (identifiers replaced by `ID`, numbers by `NUM`). Numeric literals of 4+ significant digits were matched separately. Positive control: an upstream Nasal file copied verbatim scores 100 % on all four; the same file with every identifier renamed scores 0 % on the first three and 94.8 % on the renamed-structure test. So the tests do catch copying inside one language.
5. **Manual comparison** of each core module with the matching upstream file: structure, formulas, constants, names, comments.
6. **Asset identity.** MD5 comparison of shipped textures and sounds with the upstream files.

Limits: the 5-gram, 8-gram and line tests compare tokens, so they say nothing about a GDScript file that is a hand translation of C++ (the token streams differ). Only the structural reading can judge that. FlightGear's full repositories (all of `flightgear`, `simgear`, `fgdata` Nasal) were not searched, only the files that could correspond to our modules.

## Inventory

Counts are for tracked files. "Code" is non-blank, non-comment lines.

| Category | Files | MB | % bytes | Lines (code) |
|---|---:|---:|---:|---:|
| **A. Original code and data** | | | | |
| A1 game code (`game/**/*.gd`, no tests) | 175 | 0.75 | 0.87 | 20,282 (15,951) |
| A2 tests (`game/tests/*.gd`) | 68 | 0.36 | 0.42 | 8,865 (7,477) |
| A3 shaders | 18 | 0.04 | 0.04 | 879 (712) |
| A4 tools and packaging scripts (py, sh) | 46 | 0.29 | 0.33 | 6,551 (5,529) |
| A5 scenes (`.tscn`) | 27 | 0.01 | 0.02 | 409 |
| A6 own JSON (aircraft, hull, checklists, ATC, lessons) | 6 | 0.04 | 0.04 | 404 |
| **B. Vendored third party** | | | | |
| B1 `third_party/c172p` (FlightGear c172p source, GPL) | 27 | 21.62 | 24.95 | |
| B2 `third_party/fgdata` (fgdata source, GPL-2) | 11 | 3.98 | 4.59 | |
| B3 Godot licence texts (`packaging/licenses`) | 2 | 0.10 | 0.12 | |
| **C. Derived or copied assets** | | | | |
| C1 c172p `.glb` models and textures (`game/aircraft/c172/models`) | 20 | 46.98 | 54.22 | |
| C2 sounds (`game/aircraft/c172/sounds`, 23 c172p team, 7 fgdata) | 30 | 8.74 | 10.09 | |
| C3 fgdata vehicles (4 `.glb` and 4 textures) | 8 | 2.41 | 2.78 | |
| C4 JSBSim-derived JSON (`c172_aero.json`, `c172_config.json`) | 2 | 0.03 | 0.03 | 1,945 |
| **D. Own art** | | | | |
| D1 logo, icon, splash (`game/branding`, generator) | 13 | 0.16 | 0.19 | |
| D2 own Blender vehicles (fuel truck, GPU, baggage tug and cart, follow-me) | 5 | 0.46 | 0.53 | |
| D3 menu background screenshot (`game/ui/menu/menu_bg.jpg`) | 1 | 0.24 | 0.28 | |
| **E. Docs and licence texts** | 16 | 0.34 | 0.39 | 4,047 |
| Other (project file, desktop entries, SVG, misc) | 12 | 0.03 | 0.03 | |
| Noise: `.import` and `.uid` | 335 | 0.07 | 0.08 | |
| **Total** | **822** | **86.64** | **100** | |

Reading the table:
- B1 and B2 are the unmodified originals of C1 and C3 (shipped to satisfy the GPL's corresponding-source rule), so the converted and original forms are counted twice. That is why the headline gives the figure with and without them.
- FlightGear/JSBSim origin = B1 + B2 + C1 + C2 + C3 + C4 = 83.8 MB (96.7 %), 98 of 487 files.
- Within C1, the 18 textures are byte-identical to `third_party/c172p`; the two `.glb` files are modified conversions (hinge pivots, FlightGear-only parts removed, normal maps). Three textures are stored twice (interior 4.0 MB, panel 3.1 MB, panel_parts 1.1 MB, once as `exterior_*` and once as `interior_*`), which is repository bloat, not an extra derivation.
- Within C2, all 30 `.wav` files are byte-identical to files in the c172p repository (23) or fgdata (7). Some are third-party recordings that the c172p team already licensed (CC0, CC-BY); see `sounds/SOURCES.md`.
- The own-art files in D contain no upstream material, but D3 is a screenshot of the sim (see "Gaps").

### When each derived item entered the history

| Commit | Date | Added |
|---|---|---|
| `043c787` M1 | 2026-10-10 | `tools/06_jsbsim_to_json.py`, `c172_aero.json`, `c172_config.json` |
| `c045e68` M3 | 2026-10-10 | `game/fdm/aero.gd`, `table.gd`, `propeller.gd`, `engine_piston.gd`, ... |
| `c215dc5` | 2026-10-10 | c172p `.glb` and textures, `third_party/c172p`, `LICENSE`, `docs/LICENSING.md` |
| `6fc63e5` | 2026-10-10 | 30 sounds and `aircraft_audio.gd` |
| `9feb0d4` Phase A | 2026-10-10 | fgdata vehicles, `third_party/fgdata` |
| `6fd7fcf` | 2026-10-10 | `checklists.json` (own text, see below) |

`CREDITS.md` has existed since the first commit (2026-09-30); the licence file and `docs/LICENSING.md` were added with the first FlightGear asset (`c215dc5`), so every derived asset has had a credit and a licence row since it entered.

## Per-module derivation

Codes: **O** original implementation; **S** implements a standard published model (physics or maths that anyone would write the same way); **J** re-implements JSBSim's published design in our own code (no source copied, same behaviour, same property names and data format); **PORT** translation of upstream source. **No PORT was found.**

| Module (lines) | Class | Evidence |
|---|---|---|
| `fdm/aero.gd` (104) | **J** | Evaluates JSBSim's `<function>` trees (product, sum, difference, quotient, abs, min, max, table, property) over JSBSim's property names (`aero/qbar-psf`, `fcs/elevator-pos-rad`, `aero/bi2vel`, ...), then sums per axis as `FGAerodynamics::Run` does. The stall-hysteresis block (`alpha > max` sets 1, `alpha < min` sets 0) and the `bi2vel`/`ci2vel` definitions follow `FGAerodynamics.cpp` lines 157 to 176. Different language and layout, 2 shared identifiers. The closest module to a port, but not a translation. |
| `fdm/table.gd` (34) | **J**/S | 1-D and 2-D linear interpolation with end clamping, the same behaviour as `FGTable::GetValue`. Different code (bracket search plus `lerpf`; JSBSim indexes a flat array). Any interpolation does this. |
| `fdm/propeller.gd` (75) | **J** | The same chain as `FGPropeller::Calculate`: advance ratio, helical tip Mach, `Ct x CtFactor x CtMach`, `T = Ct n^2 D^4 rho`, momentum-theory induced velocity `0.5(-V + sqrt(V^2 + 2T/(rho A)))`, RPM from excess torque / inertia, P-factor as a shift of the thrust point with factor `Sense x P_Factor x angle / tangentialVel`. These are textbook (Stevens and Lewis, McCormick) except the P-factor form, which is JSBSim's own and is repeated here (our angle omits the induced-velocity term). No line is copied; names differ (`advance_ratio`, `tip_mach`, `v_induced`); table names (`C_THRUST`, `CT_MACH`...) come from the data file. The closest thing to a port in the repo, at 58 code lines. |
| `fdm/engine_piston.gd` (132) | **O** | Air-mass-flow model: volumetric efficiency, manifold pressure, mixture efficiency, friction, pumping, own EGT/CHT/oil models and failure cases. JSBSim's `FGPiston` works from fuel flow, ISFC, a mixture-efficiency table and FMEP/PMEP. Only 5 engine parameters (max hp, displacement, idle and max rpm, spark-fail drop) are read from `engIO360C.xml`; they are Lycoming IO-360 facts as well. Shared identifiers are config key names. |
| `fdm/gear_ground.gd` (81) | **O**/S | Spring-damper normal force with a damping ramp, saturated Coulomb friction and brake blending. `FGLGear` uses a different friction and slip formulation. Takes contact points, spring and damping values from the JSBSim data (damping scaled by 0.2). 2 shared identifiers. |
| `fdm/mass_balance.gd` (87) | **S** | Weighted CG and parallel-axis theorem. JSBSim's structural frame (x aft, y right, z up) and its mass data are used, which is a convention and data. 1 shared identifier. |
| `fdm/atmosphere_isa.gd` (49) | **S** | ICAO standard atmosphere, troposphere only, with QNH and temperature offset. `FGStandardAtmosphere` is table-based with layers. Constants (288.15, 101325, 0.0065, 287.053, 9.80665) are standard. |
| `fdm/trim.gd` (60) | **O** | Three-variable Newton iteration on one-step accelerations. JSBSim's `FGTrim`/`FGTrimAnalysis` use a different method (Nelder-Mead). |
| `fdm/flight_controls.gd` (79) | **O** | Pilot to surface mapping with rate limits. Surface ranges come from the JSBSim `aerosurface_scale` data; the three travel times (0.30, 0.15, 0.15 s) are the c172p team's `<kinematic>` values (credited). |
| `fdm/fdm.gd`, `fdm_node.gd`, `damage.gd`, `obstacle_*.gd` (about 900) | **O** | Own integrator (semi-implicit Euler with a quaternion; JSBSim's defaults are Adams-Bashforth for translation), wind, ground, damage and collision model. Nothing comparable in JSBSim. |
| `systems/electrical.gd`, `fuel.gd`, `vacuum.gd`, `pitot_static.gd` | **O** | Small simplified models (battery state of charge, feed fractions, suction vs RPM, POH airspeed calibration). The c172p team's Nasal electrical system is a different, much larger design. At most 2 shared identifiers per file. |
| `systems/failure_*.gd`, `replay*.gd`, `callout_logic.gd` | **O** | No counterpart upstream. |
| `instruments/*.gd` | **O** | Gyro erection by specific force, pendulous compass, lagged ASI/altimeter/VSI. FlightGear's instruments are separate C++ classes with different models; 1 to 2 generic shared identifiers. |
| `avionics/*.gd` | **O** | VOR/LOC/GS/DME/ADF with a terrain line-of-sight check; own GPS and database. FlightGear's `navradio.cxx` (984 lines) shares 4 generic identifiers. |
| `core/props.gd` (40) | **O** | A flat dictionary of path to value. The idea of a property tree is FlightGear's and JSBSim's; the code is trivial and ours. Many property names follow the same style (`systems/electrical/bus_volts`). |
| `input/*.gd`, `core/key_bindings.gd` | **O** | Default keys use common flight-sim habits (arrows and keypad for the yoke, B for brakes, S for the starter), which FlightGear's defaults also use. Conventions are not copyrightable. "Sticky" mode and the 0.5 auto-coordination factor copy FlightGear's behaviour, not code. |
| `aircraft/c172/aircraft_audio.gd` (101) | **O** + values | Original code. 5 numeric constants (engine volume and pitch curve, wind volume, altitude factor and pitch) are the c172p team's `c172-sound.xml` values (`0.000294118`, `0.205882353`, `0.000434783`, `0.0035`, `1.25`). Credited. |
| `tools/06_jsbsim_to_json.py` (151) | **O** (derives data) | Our converter from JSBSim XML to JSON. Its output (C4) is derived data. |
| `tools/blender/convert_*.py` | **O** (derive assets) | Our scripts that convert the FlightGear `.ac` models to `.glb`. Hinge axes were read from `c172p.xml`. |
| `aircraft/c172/checklists.json` | **O** | "Abbreviated from the Cessna 172S POH". 26 of 62 item phrases (all of 2 to 6 words, such as "Mixture - RICH", "Parking brake - SET") also occur in FlightGear's `c172-checklists.xml`, because both follow the POH. The 5-word overlap of the whole file is 2.3 %. Not shown to be derived. |
| `training/lessons.json`, `atc/phraseology.json`, docs | **O** | 0.1 %, 0.0 % and 0.0 % five-word overlap with the c172p tutorials and checklists. |

### Mechanical results

| Test (311 code files vs the whole upstream corpus) | Result |
|---|---|
| Token 5-gram overlap, weighted by lines | 0.01 % |
| Token 8-gram overlap | 0.00 % |
| Exact normalised line overlap | 0.01 % (highest file 1.9 %: two generic loop and `if` lines in a shader) |
| Renamed-structure 12-gram, weighted | 1.4 %. Four files above 10 % (`speech_backend.gd` 26 %, `replay_channels.gd` 18 %, `situation_fdm.gd` 15 %, `debug_vehicles.gd` 12 %). They are long lists of strings and repeated setter calls, not shared logic. |
| Numeric literals (4+ digits) found in upstream | Only unit and physical constants (0.3048, 47.880259, 101325, 287.053, 9.80665, 3386.389, 1852, 3600), plus the 5 sound constants above |
| `c172_aero.json` numbers found verbatim in JSBSim `c172p.xml` | 335 of 335 (all 35 functions: 4 shared + 31 per axis) |
| Propeller table values found in JSBSim `prop_75in2f.xml` | 112 of 112 |
| Shipped textures byte-identical to upstream | 22 of 22 (18 c172p, 4 fgdata) |
| Shipped sounds byte-identical to upstream | 30 of 30 |

What is copyright-relevant here: the **data** files and **assets** are copies or conversions, so the upstream licences apply to them. The **code** has no verbatim or renamed copying. The overlap in constants, formulas (ISA, momentum-theory induced velocity, bilinear interpolation, parallel axis) and names such as `Ct`, `P_Factor` or `StarterRPM` is the same physics and the same data-file vocabulary, which copyright does not protect. The three J files are the only places where our structure follows JSBSim's design closely; they are our own expression in a different language, and JSBSim is LGPL-2.1, which the GPL-2.0-or-later licence can absorb anyway (see next section).

## Licence consequences

| Item | Upstream licence | libresim's stated licence | Consistent? |
|---|---|---|---|
| c172p model, textures, 23 sounds | GPL-2.0-or-later (upstream `CONTRIBUTING.md`: "licensed under the GPL version 2 or later"). The `LICENSE` file is plain GPL-2 text. Some files CC-BY or CC0 (`Thanks`) | GPL-2.0-or-later | Yes. The "or later" evidence is in `CONTRIBUTING.md`, which is not vendored. |
| JSBSim `c172p`, engine and propeller data | LGPL-2.1 (`COPYING`); C++ headers say "version 2 or any later version"; the XML data files carry no licence header | Converted into GPL-2.0-or-later | Yes. LGPL-2.1 section 3 allows applying the ordinary GPL to a copy. |
| JSBSim-style code (3 files) | none copied | GPL-2.0-or-later | Yes. |
| fgdata models (4) and 7 sounds | Repository `COPYING` is GPL-2 text and the README says "This project is GPL'd". No per-file version and no per-file author (history was rewritten to a clean history) | listed as GPL-2.0 in `docs/LICENSING.md` | Mostly. See caveat 1. |
| CC-BY sounds (Morsule, algefaen) | CC-BY (version not stated by the c172p team) | credited | Fine as separate files with attribution. They are not relicensed. |
| Sentinel-2 imagery, OSM data | CC BY-NC-SA 4.0 / ODbL | not in git (`data/` ignored) | Yes, except the screenshot (caveat 3). |
| ESA WorldCover 2021 v200 (land-class tiles) | CC BY 4.0 | not in git (`data/` ignored); credited in CREDITS.md, the F12 screen and the attribution line | Yes. No third-party texture assets are used for the per-class ground detail (procedural shader). |

Caveats:
1. **"Or later" needs a caveat for the whole distribution.** If any bundled fgdata file is GPL-2.0 only, anyone who receives the complete distribution gets it under GPL-2.0, not "or later". fgdata gives no "or later" statement, and `CREDITS.md` currently labels the 7 fgdata sounds "GPL-2.0-or-later" while `docs/LICENSING.md` labels the fgdata models "GPL-2.0". Say in the README: "libresim's own code is GPL-2.0-or-later; bundled FlightGear data files are GPL-2.0 (some or later), so the complete distribution is GPL-2.0."
2. **No per-file licence notice.** No libresim source file has an SPDX line or copyright header, and the root `LICENSE` is the plain GPL-2 text. The "or later" choice exists only in README, CREDITS and LICENSING. To make it effective, add a copyright line with the standard "either version 2 of the License, or (at your option) any later version" notice (README or per-file SPDX `GPL-2.0-or-later`).
3. **Sim screenshots contain Sentinel-2 imagery.** `game/ui/menu/menu_bg.jpg` (tracked) and the new `docs/screenshots/` (untracked at audit time) show terrain textured with Sentinel-2 imagery (CC BY-NC-SA 4.0), OSM-derived buildings and the c172p model. They contradict the "no imagery in git" checkbox in `docs/LICENSING.md` and are not GPL artwork. Replace them with a screenshot of unrestricted terrain, or keep them clearly under CC BY-NC-SA with attribution, and avoid shipping them in a commercial package.
4. **JSBSim's `c172p.xml` header** says the model "is meant for educational and entertainment purposes only" and "is not to be sold" (author recorded as unknown). The repository licence is LGPL-2.1, which allows sale, so this is a courtesy note rather than a restriction, but it is another reason to keep libresim free and non-commercial (the imagery already requires that).
5. **Upstream copyright holders are not individually named for fgdata.** The four models carry no author in the files, and fgdata's git history was rewritten (2015 "clean history"), so the original authors could not be determined. They are credited as "FlightGear contributors".
6. The c172p team's own sounds (flap motor, tyres, clicks, doors, scratch) are listed by the team as GPL-2.0-or-later without naming recording authors.

## Gaps found

Fixed in this audit (additions only, same style):
- `CREDITS.md`: JSBSim principal authors (from JSBSim's `AUTHORS`); the three flight-model files written from JSBSim's design; the c172p-team tuning values (actuator times, sound curves).
- `docs/LICENSING.md`: rows for the JSBSim-design files, the c172p-team tuning values, and the sim screenshots.

Found and left for the owner (not changed, per the audit brief):
- `CREDITS.md` heading "Inspiration (ideas only; no code or assets taken)" lists FlightGear and JSBSim. The wording is now too strong, since values and data were taken; rename it, for example "Inspiration and references".
- `CREDITS.md` and `docs/LICENSING.md` disagree on the fgdata licence (caveat 1).
- The checkbox "no imagery ... redistributed through the repo" is untrue for the screenshots (caveat 3).
- `third_party/c172p` should also hold upstream `CONTRIBUTING.md`, the source of the "or later" statement.
- `PLAN.md` says "Port validated JSBSim C172 tables". This is accurate for the data but may read as code porting; consider "reuse".

Not determined:
- Per-file authors of the fgdata vehicle models, and the recording authors of the c172p team's own sounds.
- Whether the c172p team's CC-BY recordings are CC-BY 2.0, 3.0 or 4.0.
- Anything in FlightGear repositories that was not fetched (full `flightgear`, `simgear`, `fgdata` Nasal). No module of ours has a plausible counterpart there beyond the files compared.

## Suggested README paragraph

> libresim is not a fork of FlightGear and contains no FlightGear or JSBSim source code. It is a separate simulator written in GDScript on the Godot engine, with its own flight-dynamics integrator, engine, systems, instruments, radios, ATC and world streaming. It does reuse FlightGear-project work as data and assets: the c172p 3D model, cockpit, textures and sounds (GPL-2.0-or-later, by the c172p team) and four fgdata airport models (GPL-2.0), plus JSBSim's c172p aerodynamic, mass and propeller data (LGPL-2.1), which libresim converts to JSON and retunes. By file size most of the repository is those assets; by lines of code essentially none of it is. See [CREDITS.md](CREDITS.md), [docs/PROVENANCE.md](docs/PROVENANCE.md) and [docs/LICENSING.md](docs/LICENSING.md).

## Reproducing

The counting and similarity scripts were throwaway Python in a scratch directory. To redo the audit: classify `git ls-files` by path (rules in the inventory table), fetch JSBSim `src/**` and the c172p team files named in "Method", and compare as described there. Asset identity is `md5sum` of `game/aircraft/c172/{models,sounds}` and `game/world/models/vehicles` against `third_party/` and the upstream `Sounds/` folders.
