# A320 FCU, FMA and autoflight: reference and truth table

What the real A320 family does, what libresim does, with sources. The same rows are run as a test:
`game/tests/fcu_truth_table.json` + `game/tests/test_fcu_truth_table.gd`. Sources are summarised, not quoted. The FlyByWire A32NX
documentation (FBW) is a simulator project built on Airbus references, so it is a secondary source; Airbus Safety First is primary.

Sources
- [SF] Airbus Safety First, "Inappropriate V/S Target during Autoflight Mode Reversion": https://safetyfirst.airbus.com/app/themes/mh_newsdesk/iframe.php?p=68662
- [FCU] FBW, Flight Control Unit: https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-briefing/flight-deck/glareshield/fcu/
- [SEL] FBW, selected vertical modes: https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-advanced-guides/flight-guidance/vertical-guidance/selected-modes/
- [MAN] FBW, managed vertical modes: https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-advanced-guides/flight-guidance/vertical-guidance/managed-modes/
- [FMA] FBW, FMA / first column / fifth column: https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-briefing/pfd/fma/ , .../pfd/first-column/ , .../pfd/fifth-column/
- [FE] The Flying Engineer, autoflight: https://theflyingengineer.com/projects/airbus-tech/autoflight/
- [AF] Aerofly, Airbus autopilots: https://www.aerofly.com/aircraft-tutorials/airbus-autopilots/
- [FMA1] FBW, FMA first column (thrust annunciations, colours, boxes): https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-briefing/pfd/first-column/
- [FMA5] FBW, FMA fifth column (A/THR blue = armed, white = active and the arming conditions): https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-briefing/pfd/fifth-column/
- [THR] FBW, thrust levers and pedestal (detents, A/THR limited by the lever, levers never move, instinctive disconnect): https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-briefing/flight-deck/pedestal/thrust-pitch-trim/
- [FEA] The Flying Engineer, autoflight (A/THR range IDLE to CL, MAN THR above CL, levers to idle disconnect, thrust lock, instinctive disconnect): https://theflyingengineer.com/projects/airbus-tech/autoflight/
- [SPDC] FBW, speed and Mach control (selected has priority over managed, the one automatic change is at go-around): https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-advanced-guides/flight-guidance/vertical-guidance/speed-control/
- [AL] FBW, Autoland (A32NX, standard operations; secondary, a simulator guide built on Airbus procedures): https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-advanced-guides/flight-guidance/autoland/ . FMA sequence CAT 3 DUAL, LAND at 350 ft, FLARE at 40 ft, THRUST IDLE at 30 ft, ROLL OUT at main gear touchdown; RETARD callout at 10 ft; "autopilot keeps the aircraft on the centreline", disconnect at taxi speed; limits (crosswind 20 kt, head wind 30 kt, tail wind 10 kt, glide path 2.5 to 3.25 deg); go-around and Autoland Warning Light rules. Mirrored older copies of the same guide say LAND 350 ft, FLARE 30 ft.
- [FMA4] FBW, FMA fourth column (CAT1, CAT2, CAT3 SINGLE = fail passive, one AP; CAT3 DUAL = fail operational, both APs; white; the aircraft's capability, independent of the airport): https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-briefing/pfd/fourth-column/
- [SKY] SKYbrary, Autoland (search snippet only, the page itself was not readable by the fetch tool): the A320 / A330 autoland steers on the runway, first with the rudder and, as the aircraft slows, with the nose wheel steering: https://www.skybrary.aero/index.php/Autoland
- [SF2] Airbus Safety First, "A focus on the landing flare" (search snippet only, the page was not readable): the FCOM flare height of the A320 family is about 30 ft RA in a stabilised approach (manual landing): https://safetyfirst.airbus.com/a-focus-on-the-landing-flare/amp
- [PPR2] PPRuNe, A320 roll out mode and autoland systems sequencing (search snippets only, anecdotal; the pages were refused by the fetch tool): https://www.pprune.org/tech-log/597969-a320-rollout-mode.html , https://www.pprune.org/tech-log/666383-320-automatic-rollout-function-after-autoland.html , https://www.pprune.org/tech-log/printthread-580594-a320-1-autoland-systems-sequencing.html
- [PPR] PPRuNe threads, secondary and anecdotal: A/THR arming and LVR CLB https://www.pprune.org/tech-log/669476-320-go-around-query.html ; speed/Mach switching https://www.pprune.org/tech-log/374966-a320-speed-mach-switching.html (page not readable by the fetch tool, search snippets only)

## The V/S preset time (the question that started this)

Turning the V/S/FPA knob without pulling stores a preselected value. It stays displayed for 45 s on the A320 family (10 s on the A300-600 and
A310), after which the window is dashes again [SF]. That is a primary Airbus figure, so the sim's 45 s is right; it is now
`AfPreview.VS_S` (game/systems/autoflight_preview.gd). It does not stay "until pulled". While it shows, the FMA is unchanged (the preset
is not a mode); a pull flies it. If a mode reversion to V/S happens inside the 45 s the guidance takes the preselected value, otherwise
the present vertical speed [SF] (the sim does the same).
Other selectors: the HDG window (45 s) and the SPD/MACH window (10 s) return to dashes if a value is turned while managed and not pulled
[FCU]. The ALT window never shows dashes and has no timeout [FCU]. HDG 45 s and SPD 10 s are FBW-only (UNVERIFIED); the A380X page of FBW
says 45 s for all of them.

## Knobs and windows (real, then libresim)

| Control | Real A320 | libresim now |
|---|---|---|
| SPD/MACH push / pull | push = managed speed, window dashes + dot; pull = selected speed, value, no dot [FCU] | same (`spd_managed`); a value turned while managed shows 10 s, dot stays |
| HDG/TRK push / pull | push = managed lateral (NAV), dashes + dot; pull = selected HDG, value, no dot [FCU] | same; push without a route does not engage NAV and is withdrawn (window keeps the heading); a value turned while managed shows 45 s |
| ALT push / pull | push = managed CLB/DES (dot in the ALT window); pull = open climb / descent OP CLB / OP DES; window never dashes [FCU][SEL][MAN] | same; pull while at the altitude keeps ALT |
| ALT turned only | in ALT the mode is unaffected; in ALT* a change over 250 ft gives V/S; a target on the wrong side of a climb or descent gives V/S at the present rate [SEL] | same. Before: the mode flipped to OP CLB / OP DES / CLB / DES, and the ALT hold followed the window, so the aircraft left the altitude while the FMA still said ALT. Now ALT holds the altitude memorised at engagement (`AfVertical.hold_m`) |
| ALT 100 / 1000 | selects the step of the ALT knob [FCU] | same (`alt_inc_1000`) |
| V/S pull | engages V/S on the displayed value [FCU][SEL] | same; with dashes it flies the present vertical speed (UNVERIFIED) |
| V/S push | level off, V/S 0, FMA V/S in green [FCU][SEL] | same |
| V/S turned in V/S | changes the target at once | same |
| AP1 / AP2 | light green while engaged; pressing engages or disengages [FCU] | same |
| A/THR | light green when armed or active [FCU]; column 5 A/THR cyan armed, white active [FMA5]. Armed by TOGA with a flight director on, FLX with a flight director and a flex temperature, or the button pushed with the levers beyond CL; active when the levers are in the engagement range (IDLE to CL) [FMA5][FEA] | same, see "Autothrust" below; the 2D FCU card lit it cyan (now green) and the FMA showed it always cyan (now white when active) |
| SPD/MACH | "changes the SPD target to the corresponding MACH target and vice versa"; Mach window 0.10 to 0.99, speed 100 to 399 [FCU] | the button flips `controls/fcu/spd_mach`; the autoflight converts the window value at the present pressure and flies the selected Mach (see "Speed and Mach" below) |
| LOC | arms the localizer (blue "LOC" on line 2 of the lateral column), LOC* then LOC at capture [FE][FMA] | same; the light follows the armed or captured mode, a press that arms nothing springs back |
| APPR | arms LOC and G/S together for an ILS (both blue), LOC* / G/S* then LOC / G/S [FE][FMA] | same; the ILS is the one NAV2 is tuned to, which the FMGC tunes to the arrival runway (`avionics/ils_autotune.gd`) unless the pilot typed a frequency on the MCDU RAD NAV page |
| EXPED | expedited climb to green dot speed or descent at 340 kt / M0.80 [SEL] | not modelled (button stays dark, no key) |
| HDG V/S - TRK FPA | switches the lateral and vertical selection to track and flight path angle [FCU] | display only: relabels the windows, converts the V/S window to degrees |
| METRIC ALT | altitude shown in metres [FCU] | display only |

## FMA

Five columns: thrust, vertical, lateral, approach capability, engagement status [FMA]. Engaged modes green, armed modes cyan/blue below them [FMA];
a changed mode is boxed in white for 10 s [FMA] (not modelled).

| Column | libresim text and colour |
|---|---|
| 1 thrust | SPEED / MACH / THR CLB / THR IDLE / THR LVR green; A.FLOOR, TOGA LK green in an amber box; MAN TOGA, MAN FLX, MAN MCT white in a white box, MAN THR white in an amber box, LVR CLB white and flashing [FMA1]; LVR ASYM amber |
| 2 vertical | line 1 engaged green (SRS, CLB, DES, OP CLB, OP DES, V/S, ALT*, ALT, ALT CRZ, G/S*, G/S, LAND, FLARE); line 2 armed cyan (ALT, G/S) |
| 3 lateral | line 1 engaged green (RWY, HDG, NAV, LOC*, LOC, ROLL OUT); line 2 armed cyan (LOC). Before: LAND here too below 400 ft (changed, see "Autoland") |
| 4 approach | white: CAT1 once the localizer is captured in an approach; CAT3 DUAL with both APs, the ILS, gear down and CONF 3 / FULL, and during an autoland [FMA4] |
| 5 status | AP1 / AP2 / AP1+2, 1FD2 white; A/THR white when active, cyan when armed only [FMA] |

## Glide slope capture (G/S* and G/S)

APPR arms LOC and G/S (blue); the localizer captures first (LOC*, then LOC within 25 m and 4 deg), then the glide slope: G/S* while the beam is
captured, G/S once the aircraft is within 8 m of the path [FE][FMA][AL]. libresim (`AfVertical._gs_logic`):
- **The bug that was fixed.** The capture window was a fixed height: above the path at most 15 m (50 ft), below it the closure rate times 6 s (at
  least 25 m). An aircraft that was more than 15 m above the path when it came level at the platform never captured: the beam sinks away
  faster than a level aircraft can meet it, so G/S* never appeared (LOC captured, the G/S signal valid, the FMA stuck on V/S with G/S armed).
  The air start puts the aircraft on the path at the start distance over the terrain under it, so on a slope or with a different threshold
  height it begins 15 m or more above the beam; any pilot input that leaves the aircraft a little high has the same effect.
- **Now.** Above the path the window is one dot (0.35 deg, half the 0.7 deg full scale of the radio: `AfVertical.GS_CAPTURE_ABOVE`), at least 15 m:
  79 m at 7 nm, 23 m at 2 nm. Below the path it is still the closure rate times 6 s (at least 25 m), which is "intercepting from below, level at the
  platform altitude" (the common case). G/S* pitches to the path with an intercept of at most 3 deg beyond the 3 deg path. Far above the beam
  (more than a dot) there is no capture and G/S stays armed until the pilot descends through the window, as on the real aircraft [UNVERIFIED: the
  exact capture criteria of the FMGC are not public; the 1 dot window is the sim's own].
- The localizer course gain was raised from 0.0004 to 0.0007 rad per metre (the old value took 35 s to remove an offset; in a 14 kt crosswind the
  aircraft arrived at the threshold 12 m off; now 3 m).

## Autoland (LAND, FLARE, ROLL OUT)

Sources: [AL] for the sequence and heights, [FMA4] for the capability words, [SKY] / [PPR2] for the roll out steering, [SF2] for the flare height.
Code: `systems/autoflight_land.gd` (`AfLand`), the hooks in `autoflight_logic.gd`, `fdm/fbw_pitch.gd`, `fdm/fbw_law.gd`, `fdm/fdm_node.gd`.

| Step | Real A320 (sources) | libresim |
|---|---|---|
| Conditions | ILS approach, LOC and G/S engaged, AP; CAT3 SINGLE (one AP, fail passive) or CAT3 DUAL (both APs, fail operational), the capability is the aircraft's, not the runway's [FMA4][AL]; CONF 3 or FULL [AL]; ILS facility CAT II / III or the crew treats the runway as CAT I [AL] | LAND needs **both APs**, the ILS received with its glide slope, gear down, CONF 3 or FULL (flap lever 4 or 5), LOC and G/S captured. Column 4 shows CAT3 DUAL then, CAT1 otherwise (also with one AP: the real aircraft would show CAT3 SINGLE and autoland with one AP; the owner asked for the two-AP rule). The ILS ground category (`category` in ils.json, 0 = unknown) is **not** used: the sim's ILS is perfect, and the FMA capability is the aircraft's |
| LAND | vertical column, green, 350 ft in [AL] (checked by 350 ft; engages near 400 ft) | below 400 ft radio altitude (wheels), vertical column LAND (green), the lateral column stays LOC. The mode latches: the APPR button no longer matters |
| FLARE | 40 ft in [AL] (30 ft in an older copy of [AL] and in [SF2] for a manual flare) | below 40 ft: vertical column FLARE. The flare law holds a sink rate that falls with the height: `sink = max(0.5 m/s, 0.33 /s x height)` read at the height the aircraft will have in 1 s, never more than the glide path sink; a flight path loop of 1 s. The fly-by-wire flare mode (attitude hold) is off while the AP flies, the autoland flares through the load factor it demands |
| Thrust | THRUST IDLE at 30 ft, callout RETARD at 10 ft, the pilot sets the levers to idle [AL] | A/THR commands idle from 30 ft (FMA THR IDLE), RETARD from 10 ft and on the roll out (levers stay where the pilot put them; with the levers at CL the engines still go to idle; A/THR goes on commanding idle on the ground while the levers are in the CL range or below). There is no RETARD voice call: the sim's GPWS has only tones |
| De-crab | the aircraft removes the crosswind crab at about 20 ft to 10 ft [AL] | from 20 ft the rudder (pedal equivalent `ap/cmd/yaw`) turns the nose to the runway axis, the roll law holds the track (wing low) |
| Touchdown | FMA ROLL OUT at main gear touchdown [AL] | `wow` (any wheel on the ground): lateral column ROLL OUT, vertical column empty, the AP stays on |
| Roll out | "the autopilot keeps the aircraft on the centreline" [AL]; steers on the runway with the rudder first, then the nose wheel as the aircraft slows [SKY]; the pilot sets reverse, brakes, and disconnects at taxi speed [AL] | `ap/cmd/yaw` (rudder at speed, nose wheel pedal steering below about 130 kt through the existing gear model) holds the runway axis from the ILS geometry (heading error plus offset, damped by the yaw rate); `ap/cmd/ground_pitch` lowers the nose at about 1.5 deg/s. The pilot brakes, spoilers and reversers as before. The AP drops quietly below **20 kt** of ground speed, or at once when the pilot disconnects it (instinctive button; a sidestick takeover also disconnects it, with the warning) |
| Signal lost | Autoland Warning Light below 200 ft RA if both APs are lost, the localizer is lost above 15 ft, the glide slope above 100 ft, the deviations exceed 1/4 dot (LOC) or 1 dot (G/S) above 15 / 100 ft, or the RAs differ by 15 ft [AL] | localizer lost above 15 ft, or glide slope lost above 100 ft, in LAND / FLARE: the AP disconnects with the warning (involuntary: it rings until the button is pressed). Below those heights the autoland flies on without the signal. The warning light itself and the deviation, RA and long-flare monitors are not modelled |
| Go-around | TOGA, SRS, rotate, A/THR [AL] | TOGA in LAND or FLARE is a go-around exactly as on the glide slope before: SRS, heading hold, MAN TOGA; the autoland ends. TOGA on the roll out starts the takeoff modes (RWY, SRS) |
| Without the second AP, the ILS or CONF 3 / FULL | no autoland | as before: the AP disconnects at 50 ft with the voluntary-style warning (`limits.autoflight.land_disconnect_ft`, 0 = off); a single AP touching down drops quietly |

Radio altitude: the autoflight now uses the height of the lowest wheel (`fdm/agl_m` less `fdm/wheel_depth_m`, 0 on the runway). The PFD radio altitude
(`instruments/pfd/ra_ft`) shows the same, so FLARE at 40 on the PFD and the GPWS-style heights agree (before it showed the CG height: 12 ft on the runway).

Measured (closed loop, real A320 FDM and fly-by-wire law, flat runway, `tests/debug_autoland_sweep.tscn`, 24 landings at VABB 27 and VAPO 28; calm, and winds of
8 to 20 kt from every side with light to moderate turbulence, 56.5 to 66 t, 128 to 152 kt): touchdown 440 to 678 m past the threshold, worst offset from the
axis 3.9 m, worst sink 199 ft/min (typical 80 to 150), pitch 3.9 to 9.1 deg, worst offset on the roll out 4.9 m, no crash, no run off the runway axis. Tolerances of
the tests: touchdown 300 to 900 m past the threshold, within 5 m of the axis, sink under 300 ft/min, pitch under 10 deg, within 7 m of the axis on the roll out
(`tests/test_autoland_calm.gd`, `test_autoland_wind.gd`, `test_autoland_modes.gd`, `test_glide_slope_capture.gd`, `test_autoland_logic.gd`, the autoland rows of
`tests/fcu_truth_table.json`). A muted run in the real flight scene (VAPO 28, 14 kt crosswind) gave LAND at 125 ft CG height, FLARE, touchdown at 103 ft/min, pitch 8 deg
and a roll out on the axis. Not measured: a runway shorter than the stopping distance (the pilot's brakes and reversers decide; the rig has a flat runway of no stated length).

## Autothrust (A/THR) arming and the levers

Modelled (`systems/autoflight_thrust.gd`, tests `tests/test_autothrust.gd` and the truth table rows):
- Detents IDLE, CL, FLX/MCT, TOGA. The levers never move with the autothrust; the lever position is the most thrust A/THR may command, except in alpha floor [THR][FEA]. libresim: the engines take `ap/cmd/lever_<n>`, `controls/throttle_<n>` is the pilot's and is never written by the autoflight.
- A/THR active range: IDLE to CL with both engines [FEA][FMA5]. Beyond CL it is armed: A/THR cyan, MAN THR (white text, amber box) when the lever is in no detent [FEA][FMA1]. Back in CL it is active again, THR CLB or SPEED/MACH.
- Takeoff arming: levers set to TOGA with a flight director on, or to FLX/MCT with a flight director on and a flex temperature entered, arm A/THR; the FMA shows MAN TOGA / MAN FLX <temp> and A/THR cyan [FMA5][FEA][PPR]. Bringing the levers to CL activates it [FMA5][PPR]. libresim arms only on the move into the detent (a pilot who disarms it with the levers still in TOGA keeps it off; the real rule is not documented for that case).
- LVR CLB flashes white after a takeoff or go-around at the thrust reduction altitude while the levers are beyond CL with A/THR armed, and goes when they are in CL [FMA1][PPR]. libresim uses 1500 ft above the field (the acceleration altitude) for both altitudes.
- The FCU button: pushed with the levers in the engagement range it activates A/THR, pushed with the levers beyond CL it arms it [FMA5]. Pushed again it disconnects [FCU].
- Levers to idle in flight disconnect A/THR [FEA] (secondary: PPRuNe says the same). The instinctive disconnect button on each lever disconnects it [THR][FEA]; libresim: `athr_disc`. SRS, CLB and OP CLB are THR CLB with A/THR active, DES / OP DES THR IDLE, other modes SPEED or MACH [FEA][SPDC].

## Speed and Mach

- The SPD/MACH button changes the target between speed and Mach; Mach range 0.10 to 0.99, display format not confirmed by [FCU] (libresim shows ".78", the usual Airbus look).
- libresim: in selected speed the window value is the target. A Mach target is converted to a CAS from the present static pressure each tick (`AtmosphereISA.cas_at_mach`; the sound speed cancels, so only pressure matters) and the autothrust, the pitch speed hold and the Vls / Vmax - 5 kt protections work on that CAS, so Mach is held as the altitude changes. TAS follows from the temperature. The conversion at the button press uses the same functions. Verified in `tests/test_autothrust.gd`: round trip below 0.01 kt and Mach 0.30 at sea level pressure equals the ISA sea level speed; closed loop with the real A320 FDM: Mach held within 0.02 in an open climb and descent with the test control law (worst seen 0.013 climb, 0.016 descent).
- The FMA column 1 says MACH instead of SPEED when the target is a Mach number, in green [FMA1].
- Selected speed takes priority over managed speed; the only automatic change from selected to managed is at go-around engagement [SPDC]. libresim has no go-around change (a go-around does not switch SPD to managed).
- Automatic changeover between speed and Mach: forum reports say the real aircraft switches the window by itself at a crossover that depends on weight and temperature (one example M.78 to 292 kt at FL303) [PPR]; no primary text was reachable. NOT modelled (see UNVERIFIED). The managed schedule already turns into MACH at Mach 0.78 (`AfSpeeds.managed`).

## Window dot rules
Managed: dashes + dot (SPD, HDG). ALT: value always, dot with managed vertical. V/S: dashes outside V/S unless a preset shows, no dot.
Selected: value, no dot [FCU]. Unpowered: blank.

## PFD roll scale

Checked 2026-11-25. No change to the sim was needed (`ui/displays/pfd.gd` `_roll_scale`). No Airbus primary text (FCOM DSC-31) was reachable,
so everything below rests on secondary sources.
- Sources: FBW attitude page https://docs.flybywiresim.com/pilots-corner/a32nx/a32nx-briefing/pfd/artificial-horizon/ ; FBW A32NX source,
  `PFD/AttitudeIndicatorHorizon.tsx`, `AttitudeIndicatorFixed.tsx`, `PFDUtils.tsx` (github.com/flybywiresim/aircraft, fbw-a32nx/src/systems/instruments/src/PFD/);
  training slides "Dragonair Certificate Program A320 Screening Flight" https://www.slideshare.net/slideshow/dragonair-certificate-program-a320-screening-flight/16284695 ;
  forum summary of sky pointer = fixed scale, moving pointer https://www.euroga.org/forums/two-different-ai-presentations-sky-pointer-or-ground-pointer/7111 (page not readable by the fetch tool, search snippet only).
- Pointer direction: the scale arc is fixed to the screen; the yellow roll index and the slip index sit on the sphere group and turn with it. In
  a right bank the sky leans left, so the pointer moves left along the arc (left bank: right). The sim does this (pointer at `-roll`, roll
  positive = right bank). Agreement: FBW code (rotates the group by minus the roll) and the training slides ("sky pointer moves against a fixed bank scale"). Direction itself is UNVERIFIED against Airbus text.
- Ticks: white, at 0, 10, 20, 30 and 45 degrees each side [FBW page]. The sim draws the same ticks (longer at 0, 30, 45) on a fixed arc.
- Limits: the FBW page shows green flight-control protection marks on the scale at plus and minus 67 degrees (amber X when normal law is lost),
  and most PFD symbols disappear above 45 degrees, returning below 40. FBW's code does not clamp the pointer; above 60 degrees it moves the
  pointer and slip index inward from the arc (up to about 5 px at 90 degrees). The sim clamps the pointer at plus and minus 60 degrees and has
  no 67 degree marks and no symbol declutter (UNVERIFIED which of these the real aircraft does, so left alone).
- Slip index: yellow trapezoid under the pointer, moves sideways relative to it. In flight it shows sideslip (beta; about 0.2 g per cm, stops at
  0.3 g); on the ground it shows lateral acceleration [FBW page]. FBW code moves it right for positive beta (relative wind from the right, i.e. the
  ball side of a right slip). The sim moves it right for a right slip (ball toward the low wing, `Adirs.slip_of`). The sim shows lateral
  acceleration in flight as well, not beta (a simplification).

## UNVERIFIED
- PFD roll scale: pointer direction against an Airbus FCOM, the 60 degree clamp, the 67 degree marks, the declutter above 45 degrees.
- HDG preview 45 s and SPD preview 10 s (FBW only; the Airbus FCOM text was not reachable). The dot staying lit during a preview.
- V/S pull with dashes flying the present vertical speed (Airbus training knowledge, no source fetched).
- V/S window content after a level-off push (sim: "+0000").
- Whether the V/S window has a managed dot (sim: none; FBW's table lists dashes and dot).
- Second press of LOC / APPR disarming (sim: it does; no source found), and the exact moment the approach capability (CAT1) appears.
- Glide slope capture: the FMGC capture criteria and the one-dot window above the path are the sim's own; whether the real aircraft captures from far above while descending in V/S at a given rate.
- Autoland: the height of LAND (sim 400 ft; [AL] says LAND by 350 ft), the height of FLARE (sim 40 ft [AL]; 30 ft in a copy of [AL] and for a manual flare [SF2]), THRUST IDLE at 30 ft and RETARD at 10 ft ([AL] only, a simulator guide); LAND in the vertical column and LOC staying in the lateral column until ROLL OUT (the column placement of LAND is not confirmed by an Airbus text; the sim used to show LAND in both); the one-dot capture, the CAT3 SINGLE autoland with one AP (sim: CAT1, no LAND), CAT2, the DH / NO DH line of column 4 and the ILS ground category (`category` in ils.json is read but not used); the flare law itself (the real law is not public; the sim's exponential flare onto a 0.5 m/s floor is tuned for 100 to 250 ft/min at touchdown and 300 to 900 m past the threshold); the roll out steering gains; the 20 kt automatic AP drop (the real aircraft keeps the AP until the pilot disconnects [AL]); the Autoland Warning Light and its monitors (RA difference, deviation limits, long flare); the 15 ft / 100 ft signal-loss heights (taken from [AL]); autobrake, reversers and ground spoilers (the pilot's, unchanged); the limits of [AL] (crosswind 20 kt, head wind 30 kt, tail wind 10 kt, glide path 2.5 to 3.25 deg, elevation 9,200 ft, weight at least 44 t) are not enforced; autoland with one engine out; a bounce after touchdown (ROLL OUT stays on and the AP keeps steering).
- AP2 pressed while AP1 is engaged outside an approach: real aircraft drops AP1 (not confirmed; sim allows AP1+2 always).
- Managed push of ALT without a flight plan (real: CLB / DES need NAV [MAN]; sim engages them anyway, there is no FMGC).
- The white mode-change box and EXPED are not drawn or modelled.
- Autothrust: the exact thrust reduction altitude (libresim: 1500 ft); the A/THR "A/THR LIMITED" caution with levers below CL in a climb mode; thrust lock (THR LK) when A/THR drops out with the levers in CL; the 15 s hold of the instinctive disconnect that removes A/THR for the flight; whether the button is refused with the levers at idle in flight (libresim: refused, because idle disconnects); what happens to an armed A/THR on the ground when the levers return to idle (libresim: stays armed); FLX arming needs a flex temperature (FBW only); an armed A/THR on the ground with the flight director off.
- Speed / Mach: the automatic changeover (see above); whether the managed speed window shows Mach; the ".78" format; that a go-around makes the selected speed managed [SPDC] (not modelled); the real Mach-to-CAS check against an Airbus crossover table.
