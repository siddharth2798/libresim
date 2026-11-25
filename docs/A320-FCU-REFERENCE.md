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
| A/THR | light green when armed or active [FCU]; column 5 A/THR cyan armed (levers above CLIMB), white active [FMA] | same; the 2D FCU card lit it cyan (now green) and the FMA showed it always cyan (now white when active) |
| LOC | arms the localizer (blue "LOC" on line 2 of the lateral column), LOC* then LOC at capture [FE][FMA] | same; the light follows the armed or captured mode, a press that arms nothing springs back |
| APPR | arms LOC and G/S together for an ILS (both blue), LOC* / G/S* then LOC / G/S [FE][FMA] | same |
| EXPED | expedited climb to green dot speed or descent at 340 kt / M0.80 [SEL] | not modelled (button stays dark, no key) |
| HDG V/S - TRK FPA | switches the lateral and vertical selection to track and flight path angle [FCU] | display only: relabels the windows, converts the V/S window to degrees |
| METRIC ALT | altitude shown in metres [FCU] | display only |

## FMA

Five columns: thrust, vertical, lateral, approach capability, engagement status [FMA]. Engaged modes green, armed modes cyan/blue below them [FMA];
a changed mode is boxed in white for 10 s [FMA] (not modelled).

| Column | libresim text and colour |
|---|---|
| 1 thrust | SPEED / MACH / THR CLB / THR IDLE / THR LVR green; A.FLOOR, TOGA LK green; MAN TOGA, MAN FLX, MAN MCT, MAN THR and LVR CLB white [FMA]; LVR ASYM amber |
| 2 vertical | line 1 engaged green (SRS, CLB, DES, OP CLB, OP DES, V/S, ALT*, ALT, ALT CRZ, G/S*, G/S, LAND); line 2 armed cyan (ALT, G/S) |
| 3 lateral | line 1 engaged green (RWY, HDG, NAV, LOC*, LOC, LAND); line 2 armed cyan (LOC) |
| 4 approach | white (CAT1 once the localizer is captured in an approach) |
| 5 status | AP1 / AP2 / AP1+2, 1FD2 white; A/THR white when active, cyan when armed only [FMA] |

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
- AP2 pressed while AP1 is engaged outside an approach: real aircraft drops AP1 (not confirmed; sim allows AP1+2 always).
- Managed push of ALT without a flight plan (real: CLB / DES need NAV [MAN]; sim engages them anyway, there is no FMGC).
- The white mode-change box, EXPED and the A/THR "TOGA LK" amber box are not drawn or modelled.
