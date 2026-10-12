# Our FDM and controls compared with FlightGear / JSBSim

Our flight model runs the JSBSim c172p aerodynamics (`tools/06_jsbsim_to_json.py`) in our own 6-DOF integrator, with our own engine (IO-360, 180 hp), propeller tuning, gear and FCS. This page compares it with:
- **JSBSim c172p**: the standalone model in `data/raw/jsbsim/src`.
- **FlightGear's c172p**: the c172p-team aircraft, sparse-cloned to `data/raw/fg/c172p-team`.

Reproduce it with:
```bash
tools/.venv/bin/python tools/18_compare_fdm.py   # plots + metrics.md in /tmp/fdm_compare
```
- `game/tests/fdm_compare.gd` flies 11 scripted manoeuvres in our FDM.
- The script then flies the same manoeuvres in JSBSim, using the same pilot laws mirrored line for line, the same load (pilot 180 lb in the left seat, 100 lb fuel per tank) and the same aileron/rudder rigging.
- JSBSim's stock engine is a 160 hp IO-320. By default the reference uses JSBSim's `engIO360C` to match our power (`--engine io320` switches back).

## Controls

| | Ours | FlightGear (generic keyboard.xml / controls.nas, c172p) |
|---|---|---|
| Keyboard yoke and rudder | Rate-based at 1.6/s, ×2 when reversing. **Spring** (default): re-centres at 2.5/s on release. **Sticky** (option): stays put, and crossing centre stops there | Each key repeat steps 0.05 and the control stays. KP5 centres. With OS key repeat this works out at about 1.5/s after a delay |
| Joystick | Per-axis deadzone, expo, invert, half/trigger ranges (`core/input_bindings.gd`) | Per-device XML with dead-band/factor; no filtering unless the XML adds it |
| Mouse yoke | Y toggles. Absolute: mouse position × 1.3 = yoke | Relative motion × 4 per screen (`mice.xml`) |
| Input filtering | **New:** a first-order low-pass at 120 Hz on pitch/roll/yaw from any device. Off / light 0.05 s (default) / strong 0.12 s | None in the input layer |
| Surface actuators | **New:** rate limits from c172p's FCS: elevator 0.30 s, aileron 0.15 s and rudder 0.15 s for full −1..1 travel | c172p-team `<kinematic>` filters with the same times. Stock JSBSim c172p has none |
| Auto-coordination | **New option** (off by default): rudder += 0.5 × aileron | Option (off by default), factor 0.5 |
| Pitch trim | Keys/buttons slew at 0.15/s; trim axis supported | Slews at TRIM_RATE 0.045/s × speed |
| Aileron/rudder trim | Fixed rigging tabs: aileron 0.033, rudder 0.004 (no cockpit control) | c172p sets aileron-trim 0.022 and rudder-trim 0.02 (it uses a different aero model) |
| Brakes | Keys are on/off (B both, `,` `.` per side), with a parking brake; joystick brake axes | `applyBrakes` ramps to full in 0.5 s |
| Flaps | Detents 0/10/20/30, electric travel 2 s / 1 s / 1 s, needs the bus | Same `<kinematic>` traverse |

## Physics: identical manoeuvres

Conditions: default solo load, ISA, no wind (except the crosswind case), same rigging in both. "diff" is ours versus JSBSim.

| Manoeuvre | Metric | Ours | JSBSim | diff |
|---|---|---:|---:|---:|
| Cruise trim, 1500 ft, 100 KIAS | pitch / pitch-trim / RPM / hp | 0.40° / −0.19 / 2159 / 81 | 0.38° / −0.19 / 2186 / 85 | +3 % / 0 / −1 % / −5 % |
| Hands off from that trim | bank at 10 s / 60 s | 1.4° / 5.3° | 1.2° / 4.1° | small (both near neutral) |
| Takeoff, flaps 0 | liftoff distance / KCAS | 747 ft / 57.4 | 882 ft / 57.3 | **−15 %** / 0 |
| | distance to 50 ft | 1628 ft | 1887 ft | −14 % |
| Climb at 74 KIAS, full power | rate of climb | 1160 fpm | 991 fpm | **+17 %** |
| Aileron step, 0.5 | peak roll rate / time to 30° | 31.2°/s / 1.14 s | 31.3°/s / 1.14 s | 0 / 0 |
| Elevator doublet | peak q / phugoid period / damping ratio | 12.7°/s / 25.3 s / 0.13 | 12.8°/s / 25.3 s / 0.11 | −1 % / 0 / +13 % |
| Rudder doublet | dutch roll period / damping ratio / peak β | 2.72 s / 0.19 / 12.7° | 2.73 s / 0.19 / 12.9° | 0 / +3 % / −1 % |
| Stall, idle, clean | min KCAS / max α / height lost | 47.8 / 17.5° / 460 ft | 47.6 / 17.8° / 444 ft | 0 / −2 % / +4 % |
| Stall, idle, flaps 30 | min KCAS / max α | 43.7 / 15.0° | 43.5 / 15.5° | 0 / −3 % |
| Glide at 68 KIAS | sink / glide ratio | 840 fpm / 8.4 | 827 fpm / 8.5 | +2 % / −2 % |
| Landing, 50 ft at 61 KIAS, flaps 30 | air distance / touchdown KCAS / ground roll | 921 ft / 51.4 / 436 ft | 932 ft / 50.8 / 476 ft | −1 % / +1 % / −8 % |
| Crosswind takeoff, 10 kt from the right | liftoff distance / max lateral deviation | 748 ft / 4 ft | 887 ft / 30 ft | −16 % / −86 % |

The aerodynamics match within a few percent: roll, pitch, dutch roll, phugoid, stall, glide and flare. The differences that remain come from three places:
- **Takeoff and climb:**
  - Our propeller deliberately gets 17 % more thrust at low advance ratio (`propeller.ct_factor_vs_j`). JSBSim's 75in2f prop is only ~59 % efficient at Vy, and its overpowered engine hides that.
  - With the boost we match the C172S POH test cards (ground roll and climb within 10 %; `tests/test_fdm_cards.gd`). JSBSim with a true 180 hp engine climbs and accelerates more slowly than the POH.
  - We kept ours.
- **Crosswind ground roll:** JSBSim's BOGEY tyre model lets the aircraft weathervane more on the nose wheel (the heading drifts 4° into wind before rotation), while our gear holds the heading with the same steering input. A real C172 sits between the two.
- **Cruise throttle:** for the same power our throttle is 0.55 where JSBSim's is 0.75, because the two engine models map throttle to manifold pressure differently.

## The "keeps tilting to one side" report

**Measured in the pure FDM** (1500 ft, 100 KIAS, hands off, old rigging aileron 0.029 / rudder 0):

| | bank at 10 s | bank at 60 s | heading change in 60 s |
|---|---:|---:|---:|
| Ours | −2.4° | −8.1° | −56° |
| JSBSim c172p, same rigging | −2.6° | −9.1° | −62° |
| JSBSim c172p stock (no rigging) | −16.6° | −47.9° | full circle (spiral dive) |
| FlightGear c172p-team, its default trims (0.022 / 0.02) | −2.4° | −9.3° | −56° |

So our roll physics already matched JSBSim and FlightGear:
- The left roll comes from the 180 lb pilot 14 in left of centre: CG 3.4 cm left, about 285 N·m of lift moment.
- Propeller torque adds about 265 N·m in cruise and 470 N·m at climb power.
- Clβ/Clp/Clr are identical in both models.

**In the game it was much worse:** −6° at 10 s and −21° at 60 s, with the nose rising from 1.8° to 8.3° and speed falling from 95 to 78 KIAS in the first 5 s. **Root cause: the airborne start was not trimmed for the actual conditions:**
1. `place_airborne` trimmed at 90 kt **TAS** (labelled KIAS).
2. It used an ISA atmosphere, although the default weather is ISA+15 °C.
3. It ignored the wind. `set_airborne` set the velocity over the ground, so the default 8 kt wind (stronger aloft) hit the aircraft as a sudden headwind gust. The aircraft zoomed, slowed, and at low speed the rigging was too weak against the pilot's weight and the torque, so it rolled off left.

**Fixes:**
- `FDM.set_airborne` and `Trim` now treat airspeed as relative to the air mass (they add `wind_ned`).
- New `FDM.trim_level_cas()` trims at a calibrated airspeed.
- `FdmNode.place_airborne(…, wind_ned)` uses the current weather (QNH, temperature) and the wind at the start height (`flight.gd` passes `$Weather.wind_at`).
- The rigging was re-solved for zero roll and yaw acceleration at about 100 KIAS level with the solo pilot, the middle of 90–110 KIAS cruise: aileron **0.033**, rudder **0.004** (was 0.029 / 0). The required rigging is 0.038 / 0.006 at 90 KIAS, 0.033 / 0.004 at 100 KIAS, 0.029 / 0.002 at 110 KIAS, and 0.081 / 0.029 at Vy with full power. So in a climb you still hold right aileron and right rudder, as in the real aircraft.
- After the fixes, in-game hands off (90 KIAS, default weather with turbulence): −2.3° at 15 s and −6° at 60 s, with pitch and speed steady. That is a slow left-wing-heavy drift, as the real C172 shows solo.
- The attitude indicator shows about 60 % of the actual bank during that slow drift (gyro erection model). It is not a cause of the tilt.

## Smoothness

- **Render interpolation:** this was verified. `C172Model._process` and every camera use `FdmNode.render_transform()`, and the camera runs after the model (`process_priority` 10). `game/tests/debug_handsoff.tscn` logs the per-frame step of the aircraft and camera against simulated time: the aircraft is uniform to 1.5 % (turbulence included). Another agent moved the interpolation to 64-bit, which removes float32 quantisation far from the origin.
- **Chase camera:** the smoothing was `lerp(dt·4)`, which depends on the frame rate. It is now `1 − exp(−4·dt)`. Its per-frame step spread went from 4.7 % to 1.5 % in the same test (the frame rates also differed between the two runs).
- **Inputs:** keyboard ramps, joystick noise and mouse-yoke jitter were applied raw, at frame rate, to the 120 Hz FDM. Now there is a low-pass in `FdmNode._read_controls` and actuator rate limits in `FlightControls`, as in FlightGear's c172p FCS.
- **Keyboard:**
  - In spring mode you have to pulse the keys to hold a partial deflection, which feels jerky.
  - The new sticky mode behaves like FlightGear: the deflection stays where you leave it.
  - Spring stays the default because it is intuitive for new players.

## Files

- `tools/18_compare_fdm.py`: the JSBSim side, runner and options.
- `tools/fdm_compare_metrics.py`: metrics and plots.
- `game/tests/fdm_compare.gd`: our side.
- `game/tests/debug_handsoff.gd`: an in-game hands-off and stutter probe. Run it with `godot --headless --path game res://tests/debug_handsoff.tscn -- --airport=VAPO --air=1500`.

## Follow-up: speed sensitivity, landing gear, climb

**Hands-off versus speed** (3000 ft, ISA+15, calm, solo, bank and heading change after 60 s):

| Rigging | 90 KIAS | 100 KIAS | 110 KIAS |
|---|---|---|---|
| Ours, 0.035 / 0.005 | −5.6° / −39° | +5.8° / +35° | +15.5° / +85° |
| JSBSim c172p, 0.035 / 0.005 | −6.8° / −47° | +4.3° / +27° | +12.7° / +74° |
| JSBSim c172p, stock (no rigging) | −55° | −51° | −50° |
| Ours, **0.033 / 0.004** (chosen) | −9.6° / −67° | +1.0° / +6° | +9.8° / +55° |
| JSBSim c172p, **0.033 / 0.004** (same rigging as ours, ISA) | −10.7° / −76° | 0.0° / 0° | not run |

- A fixed tab balances the rolling moment at only one speed. The tab's moment grows with dynamic pressure, while the pilot's weight and the engine torque stay roughly constant.
- The JSBSim c172p's spiral mode is nearly neutral at these angles of attack (Clr rises steeply with α), so a small leftover moment turns into a steady bank.
- Our model reproduces JSBSim. The chosen rigging is neutral at 100 KIAS and keeps 90–110 KIAS within about ±10°.
- Pinned by `tests/test_fdm_handsoff.gd` (pure FDM, 100 KIAS: bank ≤ 5°, heading ≤ 25°; 90 KIAS: bank −6° to −15°, heading −40° to −105°) and by the e2e jobs `handsoff_calm` / `handsoff_fair` (90 KIAS, heading limit 105°) and `handsoff_100kt` (heading limit 25°). A hands-off heading change of about −70° at 90 KIAS is this behaviour, not a regression (JSBSim with the same rigging at 95 KCAS: −4.7° / −32°).

**Landing gear:**
- JSBSim's c172p wheels are about twice critically damped (main 23 350 N·s/m), so the damper force jumps to c·v at first contact. A 290 fpm touchdown spiked to 3.8–5.5 g, and over about 500 fpm it tripped the 3×-weight gear overload, which collapsed the gear. Once the airframe had dropped, the tail skid chattered and logged "Tail strike" about 160 times.
- Fixes:
  - Wheel damping is now 0.2× JSBSim, about 0.4 of critical (`GEAR_DAMPING` in tools/06).
  - Damping builds up over the first 3 cm of compression (`gear_ground.gd` `DAMP_RAMP`).
  - A contact must be clear of the ground for 0.5 s before it counts as a new touchdown or strike (`damage.gd` `REARM_S`).
- Drop tests at an 8° flare attitude, peak g with the wing still lifting (main leg force / weight):

| Touchdown | Before | After |
|---|---|---|
| 150 fpm | 1.7 g (0.9) | 1.2 g (0.5) |
| 290 fpm | 3.8 g (1.6) | 2.4 g (0.75) |
| 600 fpm | 8.4 g (3.7, gear overloaded and collapsed) | 4.5 g (1.7, no damage) |
| 900 fpm | 22 g | 6.6 g, hard landing |

- The tail skid touches at about 10° of nose-up pitch with the gear intact (3.3 m aft of and 0.6 m above the main wheels). The nose wheel touches first below about 3.5° of pitch.

**Climb:**
- Default solo load (1880 lb), ISA+15, sea level, full throttle: 834 / 953 / 1102 / 1188 / 1139 fpm at 62 / 68 / 74 / 84 / 94 KIAS.
- The POH gives 710 fpm at 2550 lb and 20 °C. Scaled to 1880 lb with the C172 drag polar (CD0 0.031, k 0.058), we expect about 1100–1150 fpm. Ours is within 6 %.
- At gross weight the test card gives 663 fpm against the POH's 730 (−9 %). So the propeller boost was left alone.
