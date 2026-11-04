# Start-screen rework: Godot implementation plan

Goal: build the chosen design (`docs/ui-rework/final/`, local and gitignored; rules and decisions in its `BRIEF.md` and
`README.md`) in the real game, keeping every function in `docs/USAGE.md`. Written 2026-11-04. Status: planned, no code yet.

## 1. What is being built (the chosen design, short)

- **Free flight = A's flow with B's map**: home, then five steps (Aircraft, Airport & start, Weather & time, Failures,
  Recording), then Fly. A left rail shows each step with its live value and a ready / check state; the footer shows the
  setup as clickable chips plus Next and Fly.
- **One filled button, Fly.** It turns amber ("Fly anyway") when the setup has a real problem and then asks for
  confirmation. Reasons that ask: over weight, CG out, runway too short, tailwind above 5 kt, crosswind over the aircraft's
  limit (also for air starts). Low visibility only warns. Fly is never blocked.
- **Show the thing**: aircraft picture, clickable airport map with an airport search box, wind dial, sun strip, side view
  of an air start, list of armed failures. Options and Controls use tabs instead of one long scroll.
- **Owner decisions** (2026-11-04): call sign editable on the Aircraft step (both aircraft) and in Options > Radio, kept in
  sync; stands show the real OSM ref, otherwise a made-up stable name ("Gate n" / "Bay n") with the nearest terminal as a
  hint; home keeps "Fly again" and "Continue: next lesson"; Fira Sans for the whole UI; directions B and C are not built.

## 2. What exists today (facts)

`game/ui/menu/`: `start_screen.gd` (screen switch, Fly), `home_screen.gd` + `choice_card.gd`, `page_frame.gd` (prompt, glass
panel with scroll, footer Back / summary / primary), `start_flow.gd` (STEPS table, stepper pills, Fly now, keys 1-5 /
PgUp / PgDn / Ctrl+Enter), pages `aircraft_page` (+ `aircraft_chip`, `aircraft_hero`, `wb_chart`), `airport_page` (+
`airport_diagram`, a `_draw` Control with no input), `conditions_page` (+ `preset_row`, `slider_row`), `failures_page`,
`recording_page`, `training_page`, `saves_page`, `options_page`, `controls_page` (+ `controls_row`, `key_bindings_section`,
`keyboard_reference`), `menu_theme.gd` (tokens, `style_primary`, `style_quiet`). A page is an `HBoxContainer` script with a
`changed` signal; the setup lives in `Session.setup` (`core/session.gd`). Tests: `test_menu.gd`, `test_menu_order.gd`,
`test_ui_scale.gd`, `tests/debug_menu.tscn`, showcase scenes for screenshots.

Gaps found while planning (each is a task below):
- No UI font is shipped (default Godot font); `CREDITS.md` / `docs/LICENSING.md` say Fira Sans is not shipped.
- The A320 `aircraft.json` registration has `source: "fixed"`, so the call sign cannot paint its tail: it needs `callsign`
  with `VT-ZZA` as the default.
- No readiness logic exists as one function; the checks are spread over pages.
- Crosswind limits are not data. The prototype assumed C172 15 kt and A320 33 kt; the game code uses 15 kt.
- `airport_ops.json` stands carry the OSM ref only; the made-up names and nearest-terminal hint come from the data tool.
- `airport_diagram.gd` has no hit-testing; there is no search box, wind dial, day strip or glide profile control.

## 3. Phases (one commit each, files < 300 lines, tests in each)

| Phase | Content | Done when |
|---|---|---|
| U0 Font and theme (**done 2026-11-04**) | Fira Sans (Regular, Medium, SemiBold, Bold TTF) in `game/ui/fonts/` with `OFL.txt` and notice, `third_party/fira-sans/` (README: source URL, v4.203), `MenuTheme.make()` default font, new tokens (accent `#59BFFF`, dim `#AAB5C5`, dark ink on filled accent, 3 px focus ring, type scale), credits screen + `CREDITS.md` + `docs/LICENSING.md` + `tools/package/make_release.sh` (licence in `licenses/`) | font loads headless, theme default font is Fira, credits text updated, `test_ui_scale` still passes, a screenshot of home |
| U1 Readiness logic (DONE 2026-11-04, see note below the table) | pure `SetupChecks` (class in `core/` or `ui/menu/`): `checks(setup) -> [{step, level, text}]` (ok / warn / bad) for weight, CG (existing `weight_balance.gd`), runway length (`ground.min_runway_m`), tailwind > 5 kt, crosswind over limit, low visibility; data `limits.max_crosswind_kt` per aircraft in `aircraft.json` (values to be confirmed, see section 5); Fly-anyway modal (`ConfirmationDialog`-style, lists only "bad" reasons) | headless tests per rule and per aircraft, air-start variants, modal lists the right reasons |
| U2 Flow chrome (DONE 2026-11-04, see note below the table) | rail (VBox of flat Buttons: number badge, title, live value, status dot), footer chips (HFlow of flat Buttons that jump to a step), Next, Fly with ready / amber states; `start_flow.gd` keeps STEPS, keys (1-5, PgUp/PgDn, Ctrl+Enter, Esc) and `fly_requested`; `page_frame.gd` stays the frame of Training, Saved flights, Options, Controls | `test_menu_order` + new flow tests pass, every chip jumps, Fly ready vs amber vs confirm, screenshots at 1280x720 and 1920x1080 |
| U3 Home | "Fly again" (last flight from `last_flight.json`) and "Continue: next lesson" (training progress), card styling | tests for both shortcuts (present only when data exists), screenshot |
| U4 Aircraft step | call sign field on the page (both aircraft) synced with Options > Radio (`Session.setup.callsign`), A320 `registration.source` -> `callsign` with default `VT-ZZA`, "Full specification" overlay, hero, W&B as is | typing a call sign changes the registration plan of both aircraft (test with `RegistrationPaint.plan`), Options field follows, an untouched default follows the aircraft |
| U5 Airport step | search box (LineEdit + PopupPanel + ItemList, filter on `text_changed`, Up/Down/Enter/Esc), `airport_diagram.gd` `gui_input` hit-testing (runway ends, stands) and selection signals, stand list with natural sort, side view of the air start, stand names: data tool change so `airport_ops.json` has the real ref, else a stable "Gate n" / "Bay n" (numbering per airport in position order, skipping refs in use) plus the nearest terminal | click and search select the same start, names are identical on every run of the data tool, tests on the data and on hit-testing, screenshot at three airports |
| U6 Weather step | wind dial, day strip, glide-path profile controls (`_draw`, models: `wb_chart.gd`), segmented presets, "Advanced" for clouds / QNH | values round-trip into `Session.setup`, headless tests for the maths (wind components, sun times), screenshots |
| U7 Remaining pages | Failures (armed list), Recording, Training, Saved flights, Options (tabs, post-effects, Radio call sign), Controls (tabs, key rebinding unchanged) restyled with the shared components; nothing removed | `test_menu`, `test_controls_data`, `test_input*` pass, each page screenshot |
| U8 Polish and docs | UiScale 100 to 150 %, keyboard and gamepad focus order, tooltips, `docs/USAGE.md` (new screens, keys), `CLAUDE.md` status line, e2e sweep (`tools/e2e.sh`), README images | full suite green, e2e green, screenshots match the prototype layout |

**U2 build note (done 2026-11-04).** The Free-flight flow now has the chosen chrome: `ui/menu/flow_rail.gd` (`FlowRail`: readiness box plus one flat Button per step with number badge, title, live value and `StatusDot`; Up / Down stay in the rail; the rail scrolls in a very small window), `flow_chips.gd` (`FlowChips`, an `HFlowContainer` of five pill Buttons that wrap rather than overflow), `flow_values.gd` (`FlowValues`, pure: live value, chip text, level, tooltip, Fly label) and `status_dot.gd` (shape plus colour: circle ready, triangle amber / red, ring neutral). `start_flow.gd` shrank to wiring (137 lines): same `STEPS`, keys, `fly_requested`, `back_pressed`; the footer is Back, chips, Next (`primary_btn`, hidden on the last step; `on_primary()` on the last step still flies) and the one `fly_btn` (accent "Fly now", amber "Fly anyway" via `style_primary(b, true, MenuTheme.WARN)`, never disabled; `start_screen._fly` still asks when bad). It repaints on a page's `changed`, on every `show_step` and, as a safety net, in `_process` when `Session.setup.hash()` changed. `page_frame.gd` only gained a `content` member (Training, Saved flights, Options and Controls look as before). Forced by the 240 px rail: the Failures rows (`failures_page.gd` label / dropdown / spin minimums 230 / 150 / 120 to 150 / 140 / 110) and the Weather page column gaps (28 to 20 px) were narrowed so no page is wider than the panel at 1280 px (page minimum widths now 882 / 812 / 916 (More weather open) / 880 / 423; space 924). Tests: `tests/test_flow_chrome.gd` (11); `test_menu.gd` changed in two places (Next is hidden on the last step instead of the main button reading FLY; the Fly button shows on every step). `tests/debug_menu.gd` gained `FREESIM_OVERWEIGHT`, `FREESIM_FLOW_ONLY`, `FREESIM_TAG`. Rail value for the aircraft is the fuel (as asked); the chip and tooltip carry the takeoff weight. Open for U3-U7: (U4) the Aircraft page can drop its own over-weight colouring in favour of the rail dot, and its Details block is the first thing cut at 720 px high; (U5) the airport page still uses its own list / diagram widths (812 px minimum, a three-column layout fits); (U6) the Weather page is the tightest (916 of 924 px with More weather open) and its wind line still colours crosswind red above a fixed 15 kt; (U7) the Failures page two-column grid and the Recording page need their rework to use the narrower panel; focus-ring look on rail entries and chips was not checked by screenshot (keyboard focus needs a live window); the rail has no list of reasons at its bottom (the prototype has one), reasons are tooltips only.

**U1 build note (done 2026-11-04).** `core/setup_checks.gd` (`SetupChecks.checks/worst/reasons/step_level`, items `{step, level, id, text}`) is the one readiness function: the five "bad" rules (over weight, CG out, runway too short on a runway start, tailwind above 5 kt, crosswind above `limits.max_crosswind_kt`; wind on runway and air starts, not on stand starts) and the "warn" for visibility under 1.6 km. The weight maths moved into `WeightBalance.fuel_total/takeoff_kg`, which `aircraft_page.gd` now calls too; CG is `WeightBalance.compute`. `ui/menu/fly_confirm.gd` (`FlyConfirm`) is the "Fly anyway?" dialog (Go back focused, Esc = Go back, signals `confirmed` / `cancelled`); `start_screen.gd` `_fly` asks only when the worst level is "bad" (Free flight only; `dry_run` / `flights_started` are test hooks). Tests: `tests/test_setup_checks.gd` (12, the rules) and `tests/test_fly_confirm.gd` (5, the dialog and `_fly`). Rail, chips and the amber Fly button are U2. Data added: `limits.max_crosswind_kt` (C172 15, A320 33) and C172 `ground.min_runway_m` 175.3; `GroundChoice.runway_score` and the airport page's "too short" flag now also apply to the C172 for runways under 175.3 m. Open for U2: the Weather page's wind line still colours crosswind red above a fixed 15 kt (kept as it was, see section 5).

**U0 build note (done 2026-11-04).** Fira Sans Regular / Medium / SemiBold / Bold (v4.203, byte-identical to the Google Fonts files, sha256 in `third_party/fira-sans/README.md`) are in `game/ui/fonts/` with `OFL.txt`, `OFL-upstream-bBoxType.txt` and `FONT-NOTICE.txt`; `packaging/licenses/fira-sans-OFL.txt` is picked up by the existing `cp` in `make_release.sh` (no other packaging script lists licence files; flatpak and AppImage copy the staged folder). `MenuTheme` caches the four `FontFile`s (`font(weight)`, `use_font(control, weight, size)`), sets `Theme.default_font` to Regular, and now holds the design tokens (`ACCENT` `#59BFFF`, `ACCENT_INK` `#04131D`, `TEXT`, `DIM` `#AAB5C5`, `FAINT`, `PANEL` rgba(9,13,19,.82), `PANEL_2`, `OK` / `WARN` / `BAD`, `HOVER_FILL`, `SIZE_*`) and `focus_box()` (3 px accent ring, no fill) on Button, OptionButton, CheckBox, CheckButton, MenuButton, sliders, LineEdit and SpinBox. `style_primary(b, primary := true, tone := ACCENT)` has opaque fill, lighter hover and dark ink (about 9:1 on the accent; `tone := WARN` gives the amber "Fly anyway" with the same dark ink); the stepper "here" pill (`start_flow.gd`) and Saved flights "Fly from this save" no longer put white on the accent. The credits screen appends the Fira credit line, `CREDITS.md` and `docs/LICENSING.md` say the font is shipped. Tests: `test_menu_theme.gd` (10), `test_attribution.gd` (+3). Not changed: in-flight HUD and gauge drawing (`ThemeDB.fallback_font`), individual page layouts (U2 to U7). Seen in screenshots: no clipping from the wider font except the long-standing ellipsis in the airport list (`VABB  Chhatrapati Shivaji M...`) and the Controls name column (`Thrust lever 2 (lever 1 ...`), both for U5 / U7.

Order: U0 and U1 are independent (can run in parallel), U2 needs both, U3 to U7 need U2 (pairs can run in parallel:
U3 + U4, U5 + U6, then U7), U8 last. Each phase ends with a showcase screenshot (`tests/debug_showcase.tscn`, windowed,
`--audio-driver Dummy`) next to the prototype page for a visual check.

## 4. Shared components to write (new `ui/menu/` files)

Segmented (HBox of toggle Buttons in a ButtonGroup), Switch (CheckButton with custom icons), chip (flat Button, radius 999
+ status dot), rail step, wind dial, day strip, glide profile, airport search (LineEdit + popup), confirm modal. All use
`MenuTheme` tokens; none of them holds state outside `Session.setup`.

## 5. Decisions to confirm with the owner before U1 and U5

1. CONFIRMED by the owner 2026-11-04 (U1): max crosswind C172 15 kt, A320 33 kt (`limits.max_crosswind_kt`); the
   existing fixed 15 kt red colour of the Weather page wind line is kept as it was, so for the A320 the line turns red
   at 15 kt while the readiness check only asks above 33 kt.
2. CONFIRMED by the owner 2026-11-04 (U1): minimum runway C172 175.3 m (575 ft, "in ideal conditions": the C172S POH
   landing ground roll at sea level), A320 1800 m (`ground.min_runway_m`). The check adds no margin for density altitude,
   wind or surface.
3. Stand names change `airport_ops.json` (the airport-ops data tool is re-run locally; only the stand table changes).
   OK to regenerate it and commit the generated names? (still open, U5)

## 6. Risks

- Layout drift between a browser mock-up and Control nodes: keep the prototype open beside each screenshot; use
  `size_flags` and `UiScale` rather than fixed sizes.
- Many files under 300 lines: pages that are already near it (`airport_page.gd` 272, `conditions_page.gd` 251) are split
  while they are reworked (U5, U6).
- Regression risk in the start flow (Session.setup keys are saved in `last_flight.json`): keep key names, add keys only
  with defaults, and keep the save guard test.
- Font licence: ship the unmodified files with `OFL.txt` and the notice, credit in the credits screen and `CREDITS.md`.
- Headless tests cannot judge looks: pure logic is tested headless, looks by windowed screenshots reviewed by a person.
