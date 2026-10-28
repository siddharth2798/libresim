# A320 pack sound sources and licences

Only recordings whose own file page states **CC0 or CC-BY** are used; the licence was read on each file's page
on **2026-10-28**. Nothing comes from the A320-family upstream `Sounds/` folder (no per-file provenance).
Nothing is synthesised: every file below is a trimmed / filtered / resampled / normalised cut of a real
recording (recipes: `tools/25_a320_sounds.py`, table `EDITS`; `--fetch` downloads the originals with pinned
sha256, `--build` cuts them, running it without options audits files, hashes, loop seams and this list).
Credits are also in /CREDITS.md and docs/LICENSING.md.

All files are mono, 44.1 kHz, 16-bit WAV (resampled from the original rate where needed, DC removed, peak
normalised to -3 dBFS; loops are equal-power cross-faded so the end runs into the start; one-shots are faded in
and out). Volume balance between files is done by the `gain` / `volume` tables in the aircraft's audio section.

## Files made for this pack

| File | Original: title, author, page | Licence | Edit |
|---|---|---|---|
| eng_idle_loop.wav, eng_power_loop.wav, eng_whine_loop.wav, eng_start.wav, eng_shutdown.wav | "SaabJ35D Draken - start engine and taxiing" (`WWS SaabJ35DDrakenstartengineandtaxiing.ogg`), Work With Sounds / Torsten Nilsson, via Wikimedia Commons (project with Wikimedia Sverige), https://commons.wikimedia.org/wiki/File:WWS_SaabJ35DDrakenstartengineandtaxiing.ogg | CC BY 4.0 | Cuts of the 137 s stereo recording, mixed to mono: idle 70-82 s, power 104-118 s (higher-power taxi section), whine = the power cut high-passed above 1.8 kHz, start 3-20 s (ignition and spool-up), shutdown 118-134 s (spool-down). A Rolls-Royce Avon **turbojet**, not a turbofan: the character (whine, roar) is jet-like but not a CFM56 |
| eng_reverse.wav | "LAX AIRPORT! LANDING SOUND LA CITY SOUNDS" ("LAX Aiport Landing Sound Two.ogg"), freetousesounds (Marcel), OpenGameArt, https://opengameart.org/content/lax-airport-landing-sound-la-city-sounds | CC BY 4.0 | 34-47 s of the 76 s mono 96 kHz recording (landing roll heard from behind the field), resampled to 44.1 kHz, faded. A far-field airliner landing used as the reverser roar one-shot |
| packs_loop.wav | "air conditioner hum 2" by Gravity Sound (`Air conditioner hum 2 (Gravity Sound).wav`), https://commons.wikimedia.org/wiki/File:Air_conditioner_hum_2_(Gravity_Sound).wav (Gravity Sound's free library, https://www.gravitysound.studio/free-music-sound-effects; copied to Commons by a third party) | CC BY 4.0 | Whole 18 s recording, loop cross-fade. A building air conditioner used for the cabin air-conditioning hiss |
| hyd_pump_loop.wav | "Pump" (`WWS Pump.ogg`), Work With Sounds / La Fonderie, via Wikimedia Commons, https://commons.wikimedia.org/wiki/File:WWS_Pump.ogg | CC BY 4.0 | 4-13 s (steady part) of an electric liquid pump in a distillery, mono, loop. Used for the hydraulic pump whine |
| gear_motion_loop.wav | "Hoist" (`WWS Hoist.ogg`), Work With Sounds / Torsten Nilsson, via Wikimedia Commons, https://commons.wikimedia.org/wiki/File:WWS_Hoist.ogg | CC BY 4.0 | 18-30 s (steady part) of a mine hoist winder, mono, loop. Used for the landing-gear actuation noise |
| chime.wav | "Airplane Chime Sound Effect" (`Airplane Chime Sound Effect.ogg`), Sharelk, https://commons.wikimedia.org/wiki/File:Airplane_Chime_Sound_Effect.ogg | CC0 | Whole 2.9 s file, mono, short fade-out. Cabin seat-belt chime. Commons says "Own work"; whether it is a recording or was made on a computer is not stated |

CC-BY requires the attribution above (author, title, source, licence, "changes were made": trimmed, filtered, resampled).
Draken, pump and hoist: "Work With Sounds", CC BY 4.0. LAX landing: freetousesounds, CC BY 4.0. Air conditioner hum 2: Gravity Sound, CC BY 4.0.

## Reused from the C172 pack (listed by path in the A320 audio section, not copied)

| File (game/aircraft/c172/sounds/) | Used for | Licence (see ../../c172/sounds/SOURCES.md) |
|---|---|---|
| wind1 | airflow | fgdata, GPL-2.0-or-later (fgdata states GPL-2.0) |
| rain, rain-windshield | rain | fgdata, GPL-2.0 |
| rumble | spoiler rumble, tyre rumble | fgdata, GPL-2.0 |
| tires-rolling-asphalt, tires-screech-asphalt | tyre roll, touchdown squeal | c172p team, GPL-2.0-or-later |
| flaps-motor, flaps-click, door-closing | slat / flap motor, flap lever detent, gear-lock thunk | c172p team, GPL-2.0-or-later |
| click2 | gear lever click | c172p team, GPL-2.0-or-later |
| lever | parking brake lever | "Old Lever Pull" by DrMinky (freesound.org/s/167048), CC0 |

## Stand-ins and gaps (no verified recording)

- **APU start / run / shutdown**: no CC0 / CC-BY recording of an airliner APU was found. The audio section reuses the Draken
  start, idle and shutdown cuts above, pitched up and kept quiet, as a stand-in. Remove the three `apu_*` layers to leave it silent.
- **Stall / overspeed warning, autopilot disconnect ("cavalry charge"), GPWS callouts, cabin announcements**: omitted (no verified
  recording; nothing is synthesised).
- **Takeoff roar**: the high-power loop is the Draken power cut pitched up with N1; a real turbofan takeoff recording needs the
  Freesound route below.

## Candidates needing a Freesound API key (not used)

Freesound serves originals only to logged-in users / API clients; the pages below show the licence (read 2026-10-28). With an API
key (`/apiv2/sounds/<id>/` then the original download, OAuth2) these could replace the stand-ins. Check each file's own page again
before use.

| Wanted | Title, author, URL | Licence on the page |
|---|---|---|
| takeoff roar, outside | "AIRBUS A320 Take off", George_Papargyris, https://freesound.org/people/George_Papargyris/sounds/853381/ | CC BY 4.0 |
| takeoff roar, outside | "Airbus A320 Takeoff.wav", Bryce835, https://freesound.org/people/Bryce835/sounds/677369/ | CC0 |
| cockpit / cabin ambience | "Airbus A320 Ambience during flight (48/24)", neilraouf, https://freesound.org/people/neilraouf/sounds/479266/ | CC0 |
| cabin ambience | "PlanecabininteriorAirbus320.wav", devy32, https://freesound.org/people/devy32/sounds/459372/ | CC0 |
| cabin ambience | "Takeoff - Cabin Ambience", ElevatorFan2020, https://freesound.org/people/ElevatorFan2020/sounds/845957/ | CC0 |
| seat-belt chime | "A320 Double Chime.wav", JOHNNYFIVE, https://freesound.org/people/JOHNNYFIVE/sounds/457922/ | CC0 |
| seat-belt chime | "Airplane, Seatbelt Sign Beep", Kinoton, https://freesound.org/people/Kinoton/sounds/670297/ | CC0 |
| engine start | "Jet engine startup", SamsterBirdies, https://freesound.org/people/SamsterBirdies/sounds/491407/ | CC0 |
| engine start / APU-like | "Jet Engine Start Cart.wav", C-V, https://freesound.org/people/C-V/sounds/704945/ | CC0 |
| engine start | "Cessna private jet turbine starting", imagefilm.berlin, https://freesound.org/people/imagefilm.berlin/sounds/761480/ | CC BY 4.0 |
| ground air start unit (APU-like) | "airplane air start unit extremely loud machine", alex36917, https://freesound.org/people/alex36917/sounds/582104/ | CC BY 4.0 |
| gear extension | "Landing approach Airbus A350-900 extend landing gear", Marschal, https://freesound.org/people/Marschal/sounds/787789/ | CC0 |
| airliner idle / takeoff / taxi | "Boeing 737 Lot ambiance .wav", fassaria, https://freesound.org/people/fassaria/sounds/433005/ ; "Air North 737 take-off", SoundsLikeYukon, https://freesound.org/people/SoundsLikeYukon/sounds/820320/ ; "Air North 737 touchdown - interior", SoundsLikeYukon, https://freesound.org/people/SoundsLikeYukon/sounds/796060/ | CC0 |
| airliner takeoff / taxi | "Commercial Jet Takeoff Exterior 2", ForgeProductions, https://freesound.org/people/ForgeProductions/sounds/868155/ ; "Taxiing Aircraft", iainmccurdy, https://freesound.org/people/iainmccurdy/sounds/648451/ ; "Aeroplane/Airplane Taxiing (interior/cabin perspective)", iainmccurdy, https://freesound.org/people/iainmccurdy/sounds/644362/ ; "Boeing 737-800 Taxi and Take Off", ultradust, https://freesound.org/people/ultradust/sounds/165114/ | CC BY 4.0 |
| autopilot disconnect | "Autopilot Disconnected Warn", KIZILSUNGUR, https://freesound.org/people/KIZILSUNGUR/sounds/203539/ | CC0 |

## Looked at and rejected

- Beeld en Geluid Boeing 737 / Cessna Citation recordings (Wikimedia Commons, CC BY-SA 3.0), "Jet airliner overhead" (CC BY-SA 4.0): share-alike.
- "Start einer Airbus A320 (Air Berlin)" (Huhu Uet, CC BY 3.0; a take-off flyby, no steady engine state) and "428086 inspectorj airplane-boeing-flyby"
  (CC BY 4.0; a flyby with Doppler): valid licences but not loopable; not used.
- Internet Archive "Red Library: Aircraft Misc" and "GOLD TAPE: Aircraft Jets" (USC Optical Sound Effects Library, marked CC0 by the digitiser):
  1930s-50s Hollywood effects of piston aircraft and early jets; the rights chain behind the CC0 mark is not stated by the original creators. Not used.
- "Turbulence sounds" (Commons, CC BY 3.0, author "assumed"), "Sound in air plane 1/2" (public domain, PDSounds; not decodable here): not used.
- "Jet Engine Takeoff" by dklon (OpenGameArt, CC-BY 3.0; Doppler-shifted 3.6 s), "Jet airplane take off with strong ground whoosh" (GPL 3.0): not used.
