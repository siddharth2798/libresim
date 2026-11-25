# Audio: audit and plan

Status 2026-11-25. Covers every sound in the flight scene: the C172, the A320 and the world around them.
Code: `game/aircraft/common/` (`aircraft_audio.gd`, `audio_layers.gd`, `audio_curves.gd`, `audio_space.gd`,
`gpws_player.gd`), `game/world/tyre_squeal.gd`, `game/core/audio_settings.gd`. Data: `aircraft.json` "audio".

## 1. Audit (before this work, main at 137acc3)

### How sound was made

- **Buses** (`core/audio_settings.gd`): Master, Engine, Environment, Cockpit, Radio, UI; created at run time, volumes and
  mutes in `user://audio.cfg`, Options sliders, game buses held while the pause screen is up. Good; unchanged.
- **C172**: a hard-coded path in `aircraft_audio.gd` (173 lines of formulas and a list of watched switches), with only the
  engine and wind numbers in `aircraft.json`. Against the project rule "aircraft behaviour is data".
- **A320**: the data-driven layer engine (`audio_layers.gd` + pure `audio_curves.gd`), 24 layers in `aircraft.json`
  "audio.layers", plus `gpws_player.gd` (stall horn, three GPWS tones). A copy of the layers sat in
  `a320/audio_section.json`, marked "DRAFT, not wired", although the same list was wired in `aircraft.json`.
- **Touchdown squeal**: positional (`AudioStreamPlayer3D` per wheel, `world/tyre_squeal.gd`). The only 3D sound.
- **Assets**: C172 = real recordings from c172p / FlightGear fgdata (GPL-2.0+, CC0, CC-BY); A320 = cuts of CC0 / CC-BY
  recordings (`tools/25_a320_sounds.py`) and four original tones (`tools/a320_tones.py`). All credited in `SOURCES.md`.

### What had sound

| System | C172 | A320 |
|---|---|---|
| Engine / propeller / fans | idle + run loops by RPM, crank loop, start / cut one-shots, windmill | per-engine idle / power by N1, whine by N2, start / shutdown / reverse one-shots, panned L / R |
| APU | n/a | stand-in: the jet idle / start / shutdown cuts pitched up |
| Avionics | gyro by vacuum, avionics fan (fixed level) | none |
| Warnings | stall horn (on / off) | stall horn loop, altitude / sink / AP-disconnect tones |
| Hydraulics, pumps | n/a | one pump loop "any engine running" |
| Flaps / gear motors | flap motor (electric), trim wheel | flap / slat hydraulic whine while moving, gear transit loop and lock clunk |
| Tyres | roll + rumble by ground speed, touchdown squeal (3D) | same |
| Wind / airflow | wind by TAS, fading with altitude | wind by TAS, spoiler buffet |
| Cockpit ambience | rain on canopy / windshield | packs hiss, rain |
| Switches | 11 switches click, magnetos, fuel selector, flaps, parking brake | parking brake, gear lever, flap lever only |

### What had none

- A320: **PTU bark**, electric hydraulic pumps (blue / yellow), **master warning (continuous repetitive chime) and master
  caution (single chime)** although the E/WD publishes `ewd/master_warning` / `ewd/master_caution`, avionics ventilation
  fan, gear and flap airflow noise, **overhead pushbutton clicks** (only 3 cockpit controls clicked).
- C172: turn-coordinator gyro (electric, `systems/electrical/tc_powered`), flap airflow, throttle load on the engine
  sound (same RPM sounded the same at idle in a dive and at full throttle in a climb).
- Both: **turbulence**: bumps in rough air or inside a cumulus made no sound at all; **thunder**: lightning flashed in silence.
- World: **airport items were silent**: the pushback tug, the follow-me car, the GPU and fuel truck of the ramp crew, the
  jetways moving to the door. The touchdown squeal was the only world sound.
- Both: **distance and Doppler** in the outside views. Every loop except the touchdown squeal was a flat
  `AudioStreamPlayer`: the tower and fly-by cameras heard the engine at chase-camera level 3 km away.

### What sounded poor

- **Hard on / off**: gates switched a layer from silence to full volume in one frame (stall horn, gear transit, flap motor,
  pumps), a click at both ends. No attack / release.
- **APU**: a jet-engine cut pitched up, starting and stopping as fixed one-shots that did not follow `apu/n_pct`.
- **Pumps and packs** were tied to "an engine is running", not to the pumps, switches and air sources that drive them.
- **Seat-belt chime** watched `controls/seatbelt_sign`, a property nothing publishes (the sign is `controls/signs/seatbelts`):
  it never chimed.
- **C172 avionics fan** had a fixed level and a hard switch.
- Loops are long enough (recordings of 5-18 s) and cross-faded (A320); the C172 fgdata loops are short but seamless. Not
  changed.

## 2. Plan and what was done

Each step lists its test (`game/tests/test_audio_layers.gd`, `test_audio_space.gd`).

1. **One sound engine for every aircraft (done).** The C172 moves onto the layer engine: its formulas become volume / pitch
   tables in `c172/aircraft.json` "audio.layers"; the hard-coded path in `aircraft_audio.gd` goes. An aircraft without
   layers is silent (with a warning). Test: the C172 tables match the old formulas at sample RPM / airspeed points.
2. **Schema additions (done)** in `audio_curves.gd`:
   - `mods`: extra volume factors `[{drive, volume}]` multiplied in (wind fading with altitude, engine load from manifold
     pressure, airflow over extended gear and flaps).
   - `smooth`: attack / release time constant in seconds; the node eases volume toward the target instead of snapping.
   - `attenuate`: the layer is an exterior source; in outside views its volume falls with camera distance and its pitch
     takes the Doppler shift (`audio_space.gd`, pure).
   - `clicks`: `{file, gain, props: [...]}` shorthand that expands into one change-triggered click per switch property,
     cockpit only.
3. **Distance and Doppler (done)**: `audio_space.gd` gives `distance_gain(d, ref_m, rolloff)` (inverse distance from
   `ref_m`, floor 0) and `doppler(closing_mps)` (c / (c - v), clamped 0.5..2). The node reads the camera and the aircraft
   each frame, smooths the closing speed, and applies both to `attenuate` layers outside the cockpit.
4. **Generated sounds (done)**: `tools/29_generated_sounds.py` (numpy, seeded, deterministic) writes original sounds,
   libresim's own work, credited in each `SOURCES.md` and `/CREDITS.md`:
   - A320: `ptu_bark_loop.wav` (the PTU's low pulsing growl), `apu_loop.wav` (turbine whine plus intake rush; pitch and
     volume follow `apu/n_pct`, so spool-up and run-down are the loop itself), `master_warning_loop.wav` (continuous
     repetitive chime), `master_caution.wav` (single chime), `avionics_fan_loop.wav` (cockpit ventilation blower).
   - C172: `tc_gyro_loop.wav` (turn-coordinator gyro whine).
5. **A320 layers (done)**: PTU bark on `hyd/ptu_active`; blue and yellow electric pumps from their switches and AC buses;
   engine-driven pump whine from N2; APU on the generated loop; packs from the pack switches and an air source; avionics
   fan from the AC buses; master warning loop / master caution chime from the E/WD; gear and flap airflow; overhead clicks;
   seat-belt and no-smoking chime on the real properties.
6. **C172 layers (done)**: the old set, plus turn-coordinator whine, throttle load, flap airflow, smoothing on the stall
   horn, flap motor and gyros, and distance / Doppler outside.
7. **Turbulence and clouds (done)**: a `turbulence` layer on both aircraft (rumble and rattle) driven by `["abs", ["rate",
   "fdm/load_factor"]]`, the bumps the airframe actually feels, so rough air, cumulus and storm cells (whose turbulence
   `world/cloud_physics.gd` scales up) are heard as they are felt, in flight only and faded in with airspeed. Rain in a
   cloud or under it was already heard (`environment/precip`). Thunder (`world/thunder.gd`, under WeatherFx): each
   lightning strike is put at a random 0.8-6 km and its generated peal plays that distance / 340 m/s later, quieter and
   duller the further. Wind noise already follows gusts through the airspeed.
8. **Airport items (done)**: `world/world_sound.gd` (kinds table, pure speed -> volume / pitch), `vehicle_sound.gd` (a 3D
   engine loop on the pushback tug and the follow-me car, revving with their speed; the GPU generator and the fuel /
   hydrant pump run while the ramp crew is out), `jetway_sound.gd` (drive motor and warning beeper at the cab while the
   bridge or canopy moves). Generated `diesel_loop`, `car_loop`, `jetway_motor_loop`, `thunder` in `world/sounds/`.
   Parked vehicles at other stands stay silent (dozens of players for sounds nobody hears).
9. **Docs (done)**: `docs/USAGE.md` (sound section, schema), `SOURCES.md`, `/CREDITS.md`.

## 3. Not done (follow-ups)

- Surface-dependent tyre sound (grass / dirt rumble): needs the FDM to publish the surface under each wheel.
- Real turbofan recordings for the A320 engines (the engine layers are a turbojet; Freesound candidates with licences are
  listed in `a320/sounds/SOURCES.md`, they need an API key).
- Engine roughness (carb ice, lean mixture) and the C172 primer and door sounds: no property publishes them yet;
  `coughing.wav`, `primer-*.wav`, `door-*.wav` stay unused.
- Brake squeal at low speed, nose-wheel thump over centre-line lights, cabin announcements.
- Radio bus: radio static / squelch tail for ATC (with ATC A3).
- A320 MASTER WARN / MASTER CAUT pushbuttons to silence the chimes (the E/WD has no acknowledge yet): the continuous
  repetitive chime runs until the warning clears.
- Airport ambience bed (distant jets, apron hum) near terminals; taxiing AI traffic has no sound (there is none yet).
- Thunder from the actual strike position (WeatherFx has none: the flash lights the whole scene).
