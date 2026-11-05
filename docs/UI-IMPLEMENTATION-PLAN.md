# Start-screen rework

Goal: build the chosen design (`docs/ui-rework/final/`, local and gitignored; rules in its `BRIEF.md` and `README.md`) in the game, keeping every function in [USAGE.md](USAGE.md). Status: U0–U8 done.

## 1. The design

- **Free flight:** home, then five steps (Aircraft, Airport & start, Weather & time, Failures, Recording), then Fly. A left rail shows each step with its live value and a ready / check state. The footer shows the setup as clickable chips plus Next and Fly.
- **One filled button, Fly.** It turns amber ("Fly anyway") when the setup has a real problem and then asks to confirm. Reasons that ask: over weight, CG out, runway too short, tailwind above 5 kt, crosswind over the aircraft's limit (also for air starts). Low visibility only warns. Fly is never blocked.
- **Show the thing:** aircraft picture, clickable airport map with a search box, wind dial, sun strip, side view of an air start, list of armed failures. Options and Controls use tabs.

## 2. Decisions

- The call sign is editable on the Aircraft step (both aircraft) and in Options > Radio, kept in sync.
- Stands show the real OSM ref, otherwise a stable made-up name ("Gate n" / "Bay n", numbered in position order, skipping refs in use) with the nearest terminal as a hint. Computed at run time by `world/stand_names.gd`; the data tool and `airport_ops.json` are unchanged.
- Home keeps "Fly again" and "Continue: next lesson". Fira Sans for the whole UI. Designs B and C are not built.
- Max crosswind: C172 15 kt, A320 33 kt (`limits.max_crosswind_kt`). The Weather page wind line still turns red at a fixed 15 kt; the readiness check asks only above the limit.
- Minimum runway: C172 175.3 m (575 ft, C172S POH landing ground roll at sea level), A320 1,800 m (`ground.min_runway_m`). No margin for density altitude, wind or surface.

## 3. Phases (all done)

| Phase | What |
|---|---|
| U0 Font and theme | Fira Sans (Regular, Medium, SemiBold, Bold, v4.203) in `game/ui/fonts/` with `OFL.txt` and notice; `third_party/fira-sans/`; `MenuTheme` default font and tokens (accent `#59BFFF`, ink `#04131D`, dim `#AAB5C5`, panel, OK / WARN / BAD, 3 px `focus_box()` ring, `style_primary(b, primary, tone)` with dark ink on the filled button). Credits, `CREDITS.md`, `docs/LICENSING.md`, `make_release.sh` (licence in `licenses/`) updated. |
| U1 Readiness | `core/setup_checks.gd` (`SetupChecks.checks/worst/reasons/step_level`, items `{step, level, id, text}`) is the one readiness function: the five "bad" rules plus a "warn" for visibility under 1.6 km. Weight maths in `WeightBalance.fuel_total/takeoff_kg`. `ui/menu/fly_confirm.gd` is the "Fly anyway?" dialog (Go back focused; Esc = Go back). Data: `limits.max_crosswind_kt`, C172 `ground.min_runway_m`. |
| U2 Flow chrome | `flow_rail.gd` (readiness box and one button per step with badge, title, live value, `StatusDot`), `flow_chips.gd` (five chips on one row at any width, pure `fit_widths`), `flow_values.gd` (pure texts and levels), `status_dot.gd` (circle ready, triangle amber / red, ring neutral). `start_flow.gd` keeps `STEPS`, keys (1-5, PgUp/PgDn, Ctrl+Enter, Esc), `fly_requested`. The rail also lists the `SetupChecks` reasons (bad first), each jumping to its step. |
| U3 Home | Cards with "Fly again" (from `last_flight.json`) and "Continue" (next lesson after the highest-starred one; needs one lesson flown; help level "full"). `home_shortcuts.gd` (pure), `home_screen.gd`, `choice_card.gd`, `home_tile.gd`. Keys R and C. The Training card lists every lesson's stars. |
| U4 Aircraft | `Session.setup.callsign` ("" = untouched) is the one call sign for tail paint and radio (`core/callsign.gd`). `aircraft.json` `registration.text` is the aircraft's own (C172 VT-LBR, A320 VT-ZZA with `source: callsign`). `callsign_field.gd` is the shared field. `aircraft_details.gd` is the "Full specification" overlay. The page shows a weight badge and a bar against MTOW. |
| U5 Airport | `airport_search.gd` (LineEdit + unfocusable `PopupPanel` + `ItemList`, filter on ICAO, name, city; `game/world/airport_cities.json` supplies the city). `airport_diagram.gd` hit-testing (`airport_map_math.gd`), `runway_picked` / `stand_picked`. Split into `airport_data.gd`, `airport_start_panel.gd`, `stand_list.gd`, `glide_profile.gd` + `glide_math.gd`. Map, search and lists all end in `pick_airport / pick_runway / pick_stand / _put`. `Session.setup.stand` holds the name; `AirportOps.find_stand` resolves made-up names. |
| U6 Weather | `wind_dial.gd` + `wind_math.gd` (click / drag in 10 degree steps; head / cross wind via `SetupChecks.wind_components`; no dial on a stand start), `day_strip.gd` + `day_math.gd` (24 h bar, quarter-hour steps; one sky for the whole map, so it depends on the date, not the airport), `weather_choices.gd`. The month drop-down is always visible. |
| U7 Other pages | Shared controls `segmented.gd`, `switch_row.gd`, `page_styles.gd`, `menu_tabs.gd`, `option_rows.gd`, `options_graphics.gd`. Failures (three columns, `failures_logic.gd`, rebuilds when the aircraft changed), Recording, Training (`LessonCard`, `lesson_info.gd`), Saved flights (`SaveCard`, two-step delete `SavesLogic.Guard`, `SituationStore.dir` redirectable), Options (left rail: Sound, Graphics, Display & units, Flight controls, Radio / ATC, Training aids), Controls (Keyboard, Joystick & gamepad, Other keys; `controls_row.gd`, `key_bindings_section.gd`). |
| U8 Polish | UI scale 100-200 % (`HomeScreen.scale_for`, guard scroll area), focus order tests, Controls sticky tabs + "Controls for" aircraft switch + search (`ControlsFilter`, Ctrl+F), `LibresimSymbols.ttf` (12-glyph DejaVu Sans subset, renamed per the Bitstream Vera licence; `tools/make_symbols_font.py`, `third_party/dejavu-symbols/`) as fallback for glyphs Fira lacks, real flight start tests, e2e `tools/e2e.sh <run> menu` 52/52, README images regenerated. |

Tests per phase: `test_setup_checks`, `test_fly_confirm`, `test_flow_chrome`, `test_flow_reasons`, `test_home_shortcuts`, `test_callsign`, `test_airport_search`, `test_stand_names`, `test_stand_display`, `test_airport_map`, `test_wind_dial`, `test_day_strip`, `test_segmented_switch`, `test_menu_tabs`, `test_failures_page`, `test_recording_page`, `test_training_page`, `test_saves_page`, `test_menu_theme`, `test_font_glyphs`, `test_controls_filter`, `test_focus_order`, `test_real_flight_start`, `test_menu`, `test_menu_order`, `test_ui_scale`. Debug scenes (screenshots): `tests/debug_menu.tscn`, `debug_home`, `debug_weather`, `debug_u7a`, `debug_controls`, `debug_focus`, `debug_ui_walk`, `probe_real_start`.

## 4. Open items

- Free flight steps need 1040 to 1240 units of width and Training 868, so from 125 % UI scale at 1280x720 they scroll sideways. The pause screen's Options and Weather & time pages scroll sideways from 150 %. At 200 % at 1280x720 nearly everything scrolls and home needs 392 of 360 units of height.
- Painted stand numbers and stand boards on the ground show real refs only; a made-up name is not painted.
- The Training "Where you start" diagram draws an air start off the map at its edge.
- The weather dial does not draw the limit ring. Glyphs `⇄` (radio stack) and `∩` (attitude gauge) use the default font.
- Not verified in a live window: gamepad, real mouse clicks and typed keys (only signals, the focus chain and screenshots), Linux and Windows rendering of the symbol fallback, the full e2e sweep.
- The MP4 text with ffmpeg present was not seen (`ffmpeg -version` aborts on the development machine).
- `tools/e2e.sh` on macOS backs up the wrong user folder (see USAGE).
- `make_release.sh` has no staging-only mode and starts with `rm -rf build/`.

## 5. Risks

- Layout drift between a browser mock-up and Control nodes: keep the prototype open beside each screenshot; use `size_flags` and `UiScale`, not fixed sizes.
- Files under 300 lines: split pages that grow near the limit.
- Start-flow regressions (`Session.setup` keys are saved in `last_flight.json`): keep key names, add keys only with defaults, keep the save guard test.
- Font licence: ship the unmodified files with `OFL.txt` and the notice, and credit them in the credits screen and `CREDITS.md`.
- Headless tests cannot judge looks: logic is tested headless, looks by windowed screenshots reviewed by a person.
