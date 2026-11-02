# A320 data notes (for the FDM / systems implementers)

Source: FlightGear "A320-family" JSBSim files, GPL-2.0-only, pinned commit in `tools/22_a320_fetch.sh`
(`data/raw/fg/a320`: `FDE/`, `Engines/`, `Systems/`, top-level xml; untrusted data, never executed). Variant used: A320-200 CFM56-5B4
(`FDE/A320-200-CFM.xml`, `Systems/a320-cfm56-5b4-engine-fadec.xml`). Licence and credits: `third_party/a320-family/`, `docs/LICENSING.md`.
Everything below was read from the XML with Python summaries (nothing in `data/` is read into context in bulk).

## 1. What we generate and what each key means
`tools/06_jsbsim_to_json.py a320` (modules `jsb_a320.py`, `jsb_turbine.py`, `jsb_expr.py`; tests `test_jsb_convert.py`) writes
`game/aircraft/a320/{aero,config}.json`. SI units, JSBSim structural frame (x aft, y right, z up, metres). Expression format: `jsb_expr.py` header.

`aero.json`: `functions` (named `aero/function/*` expressions), `axes` {LIFT, DRAG, SIDE, ROLL, PITCH, YAW: lists of terms}, `properties` (ice),
`alpha_limits_rad`, `aero_inputs.jsbsim_builtin` (what the FDM computes itself: alpha, alphadot, beta, qbar, qbarUW, Re, bi2vel, ci2vel,
h_b-mac-ft, mach, p/q/r-aero, Sw/bw/cbarw) and `aero_inputs.from_systems` (what the control code must publish: `fcs/flap-pos-deg`,
`fcs/slat-pos-deg`, `fcs/slat-pos-norm`, `fcs/spoiler-{left,right,symmetrical}-deg`, `/systems/fcs/{aileron-l,aileron-r,elevator-l,elevator-r,rudder,stabilizer}/final-deg`
(degrees, + = trailing edge down; stabilizer nose-up negative; rudder + = nose right), `/systems/gear/all-norm`, landing-light positions).
Wing 122.6 m2, span 35.74 m, chord 7.68 m, aero reference point x = -2.27 m.

`config.json`:
- `metrics`, `mass` (empty 43.28 t incl. fixed items, CG, inertia, 6 point masses = cabin / cargo payload 11.7 t), `tanks[]` (0 L outer, 1 L inner, 2 centre, 3 R inner, 4 R outer; 5-7 are tiny engine/APU "pipe" tanks the JSBSim engines feed from, they are not in `tanks`), `unusable_fuel_kg`.
- `gear[]`: 3 bogeys (NOSE_LG steer 75 deg, LEFT/RIGHT_MLG brake groups) + 12 `STRUCTURE` contacts (nose, belly, wing tips, engines, tail: damage / scrape points). `retractable`, spring / damping / friction in SI, `cornering_coeff` (null for the A320).
- `engines[]` (type `turbine`): `thrust_n` 120102 (JSBSim milthrust 27000 lbf), `max_rpm` 100, `idle_n1` 0.189, `max_n1` 1.04, `idle_n2` 0.594, `max_n2` 1.05, `tsfc_kg_per_n_s`,
  `thrust_table` (Mach x density altitude ft -> factor), `idle_thrust_table` (fraction of `thrust_n`), `reverser_loss_table`, `n1_spool_up/down_rate_table` (percent N1 per s, column 0 = normal),
  `spool_up_s` (fit), `rated_thrust_factor` (name of the FADEC property), `jsbsim{}` raw start-up numbers, `feed_tanks`.
- `apu` (APS3200 as a third JSBSim "engine"; the game uses an APU system, not the flight model).
- `controls`: `surfaces` {aileron-l/r, elevator-l/r, stabilizer (THS, clip -13.5..+4 deg, 0.25 deg/s), rudder: lag rad/s, rate deg/s, max, clip}, `flaps.detents` (lever 0, 1, 1+F, 2, 3, FULL = slat/flap deg 0/0, 18/0, 18/10, 22/15, 22/20, 27/35; rates 1.1667 flap, 1.35 slat deg/s), `gear_transit` (s), `spoilers` (5 panels per wing, 50 deg, 35 deg/s, lever tables).
- `fadec_limits`: N1 limit tables (percent N1 vs altitude, TAT, Mach): `rated-thrust-n1`, `toga`, `flex`, `mct`, `climb`, `idle` (flaps / Mach), `mrev`.
- `unconverted[]`: every system file and element not translated, with the reason (24 JSBSim system files, tractor force).

## 2. Thrust formula (checked against JSBSim, `a320_reference.json` `thrust_formula_check`)
```
idle = thrust_n * idle_thrust_table(M, DA)
mil  = (thrust_n - idle) * thrust_table(M, DA) * rated_thrust_factor * reverser_loss
T    = (idle + mil * N2norm^2) * (1 - bleed),     N2norm = (N2 - idle_n2) / (max_n2 - idle_n2)     [DA = density altitude ft]
```
Confirmed at 6 conditions (static SL to M0.78 FL350, idle to TOGA): measured / formula = 0.970 everywhere with bleed + packs on (JSBSim `bleed` factor ~3 %), 0.998 with bleed and packs off.
`rated_thrust_factor` is the FADEC's scaling so that the thrust at the N1 limit matches the table target (1.43 at SL, 1.34 at FL100, 1.59 at FL350); it is 0 when `/systems/acconfig/autoconfig-running` = 1 (cheat flag of the FG start-up: keep it 0).
Static TOGA sea level, ISA: N1 89.2 %, N2 97.1 %, thrust 113.6 kN (bleed on) / 116.8 kN (bleed off) per engine; static idle 5.5 kN, N1 18.9 %, 672 kg/h. Spool-up idle to TOGA ~8 s (slow below N1 28 %).
Fuel flow = thrust * TSFC, TSFC scaled by sqrt(T/518.67 R).

## 3. FADEC (`a320-cfm56-5b4-engine-fadec.xml`)
In: `/controls/engines/engine[i]/throttle` 0..1 (lever), reverse lever, `/systems/fadec/athr/cmd`, `/systems/fadec/reverse-i/engage`, `/it-autoflight/output/athr`, TAT (`propulsion/tat-c`), altitude, Mach, flaps, WOW.
Detents on lever (`/systems/acconfig/options/fadec/*`): idle < 0.01, CL 0.60..0.65, MCT 0.78..0.83, TOGA >= 0.95 (so TOGA = 1.0, CL ~0.625, MCT/FLX 0.8). Lever position -> N1 target by linear interpolation between limit tables (`idle-climb-n1`, `climb-mct-n1`, `mct-toga-n1`) -> `lever-norm` (0..1 over N1 18.9..104) -> lag 0.75 -> `fcs/throttle-pos-norm[i]` (the JSBSim engine input). A/THR output is clamped between idle and the lever-position N1. Flex temperature, thrust lock, alpha-floor (TOGA) and reverse (`mrev`, N1 limit 62..80 %) are in the same file. ~50 N1-mode / limit functions, all `/systems/fadec/limit/*`.
Out: `propulsion/engine[i]/{n1,n2,thrust-lbs,fuel-flow-rate-pps}`, `/engines/engine[i]/*` (n1, n2, EGT, FF, oil for ECAM, via the "Engine Parameters" channel), `/systems/fadec/limit/{toga,mct,climb,idle,active-n1,...}`.

## 4. Control surfaces (`a320-fcs.xml`) and spoilers (`a320-spoilers.xml`)
`fcs` turns the FBW outputs into actuator positions: per surface a `cmd-deg` = gain * `/systems/fbw/{aileron,elevator,rudder}-output` (+/-1), a rate switch (82 deg/s hydraulic; 100 with the cheat flag), a lag actuator (26.5 rad/s) and `final-deg`. Surface enabled only with hydraulic pressure >= 1500 psi (blue/green/yellow) and no failure; otherwise droop (aileron 0, elevator droops). THS: `/controls/flight/elevator-trim` (-1..+0.32) * 13.5 deg, clip -13.5..+4, 0.25 deg/s. SFCC: `/controls/flight/flaps` lever 0, 0.25 .. 1.0 -> `flaps-input` 0..4 -> flap target (0, 10 (1+F) / 0, 15, 20, 40 -> limited to 35 for this set) and slat target (0, 18, 22, 22, 27); 1+F only selected from 0 below 100 kt or from 2/3 below 210 kt. Gear lever `/controls/gear/lever-cockpit` (0 up, 2 down) -> `gear/unit[i]/pos-norm`. Tiller / rudder nose-wheel steering, brakes (`fcs/brake-left/right`, autobrake, parking) also here.
Spoilers: lever (`/controls/flight/speedbrake` 0..1) + ground spoilers (armed, mains WOW) + roll spoilers from `/systems/fbw/roll` (`laf` load alleviation); panels 1-5 per wing -> `fcs/spoiler-{left,right}-deg`, `fcs/spoiler-symmetrical-deg` (used by aero).

## 5. Fly-by-wire (`a320-fbw.xml`, `a320-fbw-rules.xml`)
Normal law (`/it-fbw/law` 0; 1 alternate, 2 direct, 3 none). Sidestick: `/controls/flight/{elevator,aileron,rudder}[0]` (-1..1, FG sign: elevator -1 = pull = nose up, aileron + = right roll, rudder + = nose right) times `/systems/fbw/sidestick/active[0]`, dead zone +-2 %, lag 20 rad/s.
- **Pitch** (load-factor demand, g-law): stick -> demand table (-1 -> 2.5 g, 0 -> 1 g, +1 -> -0.5 g), limits 2.5 / -1 g clean and 2.0 / 0 g with flaps. `load-factor-error` = measured (from q*u etc.) - demand -> **`/systems/fbw/pitch/load-factor-pi`** (a PI that is NOT in the JSBSim file: it is `Systems/a320-fbw-rules.xml`, a FlightGear property rule: Kp -1.0 @140 kt .. -0.5 @350 kt, Ki -1.2 .. -0.7 only airborne in law 0/1, output limited between 0 and the stick term `e-i-sum`) -> lag `rate-c1` 3 -> rate demand = e-i * 5 deg/s (`rate-demand-gain` 0.0873 rad/s) -> pitch-rate error -> JSBSim `pid` (speed-scheduled gains: Kp 28 @140 kt .. 20 @350 kt, 23.8 at 250 kt; Ki 49.6 and Kd 1.11 at 250 kt) -> elevator output; autotrim of the THS follows the PID output when out of trim (`elevator-trim` += offset). On the ground (WOW) and in direct law the stick drives the elevator directly (gain schedule `gain-switch` 1; flare / ground law switches on `gear-agl-ft`).
- **Protections** (all in the pitch chain): alpha protection (`alpha-prot-deg`, `alpha-max-deg`, `alpha-stall-deg` vs Mach / flap / slat tables; alpha-prot 8.6 deg clean .. 10.5-11.5 with flaps, alpha-max 11.4-11.7 clean .. 14-15; neutral stick in protection holds ~alpha-prot, full aft stick reaches alpha-max), high speed (`vmo-mmo-error` terms, nose-up pitch-in), low-speed stability `e-i-ls`, bank-angle dependent load factor limit, pitch-attitude limits, flare mode (`e-i-fl`).
- **Roll**: stick -> roll-rate demand 15 deg/s full stick (0.2618 rad/s * `a-i`), bank hold < 33 deg (`max-rad` 0.576 / 1.169 rad), PID (Kp -20 @140 kt .. -5 @350, Ki -35 .. -10, Kd -1.9 .. -0.4) -> `aileron-output` (+ roll spoilers).
- **Yaw**: rudder travel limit by speed (`max-deg-scale`, 25 deg at low speed), yaw damper (`yd-p-gain` -7 @140 .. -1.2 @350) and turn coordination (`tc-*`), rudder trim, `rudder-output`.
- Outputs: `/systems/fbw/{elevator,aileron,rudder}-output`, `/controls/flight/elevator-trim`; inputs from FG side: `/accelerations/pilot-g` is not used by FBW (used by fuel / hydraulics logic, >= 0.5), `/systems/fbw/fmgc/{roll,pitch,yaw}-cmd` and `fmgc/enabled` (autopilot, Nasal).

## 6. Autopilot, FMA and the FMGC envelope
`a320-fmgc.xml` + `fmgc-*.xml` (FG property rules: filters, PIDs for pitch / roll / thrust drivers) compute the envelope the PFD needs: `/FMGC/internal/{vs1g-kts, vls, vsw, vmax, vmo-kts, mmo-kts, vls-factor-conf-*, ...}` (weight and conf tables: at 64 t `vs1g` 155.5 kt clean, 121.9 CONF 1, 109.4 FULL, `vls` 181.9 / 139.2 / 124.9, `vsw` 171.1 / 134.1 / 119.2). Read them from the oracle run if you want the designer's numbers.
The autoflight itself (IT-AUTOFLIGHT, FCU modes, FMA text, managed modes) is Nasal, not fetched and not to be ported: interface props are `/it-autoflight/input/{kts,mach,alt,vs,fpa,hdg,trk,...}` (FCU selections) and `/it-autoflight/output/{ap1,ap2,athr,fd1,fd2,lat,vert,thr-mode,loc-arm,gs-arm,lnav-arm,ap-warning}` (modes as integers, text in `/it-autoflight/text/vert`), FMA = `/modes/pfd/fma/*` (no file in our subset defines it). For libresim write own logic and publish `ap/fma/{thrust,vertical,lateral,approach,misc}`.

## 7. Other systems (for the simplified state systems)
`a320-fuel` (pumps / crossfeed / transfer logic feeding the pipe tanks 5-7 from tanks 1-3; quantity sums), `a320-hydraulic` (blue / green / yellow psi from EDPs by N2: 0 at N2 <= 40 %, 3000 psi at 45 %; pressure ramps ~1000 psi/s up, 150 psi/s down; PTU; qty inputs), `a320-electrical` (83 kB: IDG from N2 (`idg-ratio`), gens trip on voltage / frequency, buses AC1/2/ESS, DC1/2/ESS/BAT, TR, batteries 25 V threshold), `a320-apu`, `a320-pneumatic` (bleed, packs; sets engine `bleed` = thrust derate ~3 %), `a320-adr` (air data / probes), `a320-ignition`, `a320-engine-fire`, `a320-fwc*` (warnings), `a320-indicators`, `a320-lights`, `a320-oxygen`, `a320-aircond`, `a320-cockpit`, `a320-audio`, `*-sound.xml` (not used: sounds are not cleared).

## 8. Running the real A320 headless (the oracle) and the property bridge
`tools/jsb_a320_root.py` + `tools/jsb_a320_sim.py` (class `A320Sim`: `load()`, `init()`, `set_controls()`, `step(n)`, `get()`, `snapshot()`); cases in `a320_ref_flight.py`, `a320_ref_takeoff.py`; driver `tools/23_a320_reference.py`. JSBSim 1.3.3 python package, 120 Hz.
1. Root: `data/raw/fg/a320_root` (gitignored) with symlinks to the clone (`FDE`, `Engines`, `Systems/*`) and to JSBSim's `engine/`; the FDE is copied with one extra first `<system file="nasal-stubs"/>`. `Systems/nasal-stubs.xml` declares every property the files read but nothing in JSBSim defines (~720: `/controls/*` switches, `/systems/failures/*`, `/it-autoflight/*`, `/ECAM/*`, `/instrumentation/*`, `/sim/*`, FG tree copies), value = default from `A320-main.xml` / `A320-200-CFM-set.xml` (e.g. `/systems/acconfig/options/fadec/*` thresholds, otherwise 0). Found by a retry loop (one stub per load error, then a probe flight that exercises ground run, flight, flaps, gear, brakes, speedbrake, engine out); cached in `stubs.json`; later missing names are added on the fly.
2. One-time switches (`jsb_a320_sim._POWER/_SWITCHES`): `/systems/acconfig/autoconfig-running` = **0**, `/it-fbw/law` 0, `/systems/fbw/sidestick/active[0]` 1, `/services/chocks/enable` 0, batteries 1+2, GEN 1+2, bus tie, EDP green + yellow, blue elec pump, PTU, all fuel pumps, bleeds + packs, ELAC 1/2, SEC 1-3, FAC 1/2 (`/controls/fctl/switches/*`), reservoir quantities (`/systems/hydraulic/{blue,green,yellow}-qty-input`), `propulsion/set-running` -1 and `/engines/engine[i]/state` 3.
3. Every step before `run()`: `/sim/time/elapsed-sec` (>= 10 enables the generator fault logic), `/position/altitude-ft`, `/position/altitude-agl-ft`, `/velocities/airspeed-kt`, `/velocities/groundspeed-kt`, `/instrumentation/airspeed-indicator/indicated-speed-kt`, `/orientation/{roll-rate-degps,pitch-rate-degps,roll-deg,heading-deg}`, `/gear/gear[i]/{wow,position-norm}`, `/engines/engine[i]/{n1,n2}`, `/accelerations/pilot-g` (= JSBSim `accelerations/Nz`, +1 in level flight), refill of pipe tanks 5-7 (`propulsion/tank[i]/contents-lbs` = 20), and the **load-factor PI** `/systems/fbw/pitch/load-factor-pi` (section 5; our reimplementation of `a320-fbw-rules.xml` in velocity form at 120 Hz: FG's exact update rate / order is not reproduced, so pitch response timing carries that uncertainty).
4. Controls: `/controls/engines/engine[i]/throttle`, `/controls/flight/{elevator[0],aileron[0],rudder[0],elevator-trim,speedbrake,flaps}`, `/controls/gear/{lever-cockpit,brake-left,brake-right,brake-parking}`.
5. Settling: electrics, hydraulics, FADEC and the engines need ~10 s; `init()` pins the aircraft with `forces/hold-down` = 1 for 15 s (PI held at 0), releases and calls `run_ic()` again (system state is kept, motion is re-applied). The IC starts at alpha 0, so give the g-law ~60-90 s to settle before measuring.
6. Pitfalls found: `autoconfig-running` = 1 zeroes the FADEC `rated-thrust-factor` (engines produce idle thrust only) and trips the generator logic; N1 NaN if the `fadec/*-t/-b` thresholds are 0; hydraulic reservoir quantities of 0 give 0 psi; ELAC power needs `/controls/fctl/switches/elac1`; JSBSim prints FADEC "Clipping is ignored" warnings in some conditions (toga limit below mct), harmless.

## 9. What the oracle gives you
`tools/a320_reference.json` (numbers, public data points, comparison) and `tools/ref/a320_*.csv` (FBW step responses at 10 Hz). See its `meta.caveats`. Use it for: trim alpha / THS / N1 / fuel flow by configuration, alpha limits, takeoff roll timing, climb rates, thrust formula, pitch and roll step responses (target for `fdm/fbw_law.gd`: peak load factor / pitch rate and their time constants, roll rate = 15 deg/s per full stick with first-order lag ~0.4 s).
