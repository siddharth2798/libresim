# Live weather plan

An opt-in switch that reads real weather for the chosen airport and feeds it to the sim. Off by default. The game stays fully playable offline. PLAN.md says "live data stay out" (line 107) and "offline" (lines 6, 25): the owner has lifted that for this one opt-in feature (decision 1). When W5 is done, change that line in PLAN.md.

## 1. What the sim takes today

All weather lives in Props `weather/*`, set from `Session.setup` by `Session.apply_to_props()` (`core/session.gd`). Edited on the Weather step (`ui/menu/conditions_page.gd`, ranges in `weather_choices.gd`) and in F10 (`ui/settings_menu.gd`).

| Key | Unit, range | Read by |
|---|---|---|
| `wind_dir_deg`, `wind_kt` | from-true deg; kt at 10 m, 0-40 | `world/weather.gd` `wind_at()`, ATC, pause summary |
| `aloft_dir_deg`, `aloft_kt` | wind above ~1500 m AGL; set to surface +10 deg and x1.6 by `apply_to_props`, not saved | `weather.gd`, cloud drift (`sky_time.gd`) |
| `gust_kt` | peak kt | `weather.gd` (random ramps), ATC |
| `turbulence` | 0..1 | `weather.gd` (filtered noise, sigma in m/s) |
| `visibility_m` | 800-40000 m | `sky_time.gd` (fog, haze, sky aerosol), fog, lights, ATC |
| `cloud_cover`, `cloud_base_ft` | 0..1; 800-12000 ft **AMSL**; one layer, 900 m thick | cloud shader, sun occlusion, `cloud_physics.gd`, rain, ATC |
| `precip` | rain 0..1 (below 0.3 = showers) | `weather_fx.gd`, icing, `environment_effects.gd` (only above 0.6) |
| `convection`, `storms` | thermals 0..1; microburst cells 0..1 | `cloud_convection.gd`, `cloud_storm.gd` |
| `icing` | supercooled water 0..1 | `systems/icing.gd` |
| `qnh_hpa`, `temp_c` | 990-1035 hPa; **sea-level** temp, ISA offset = temp_c - 15 | `fdm/atmosphere_isa.gd`, altimeter, ATC |
| `time_h`, `day_of_year`, `time_rate` | IST hours; day 1-365 | `sky_time.gd` (sun, moon; fixed at 18.75 N 73.4 E) |

ATC (`atc/atc_world.gd`) already reads wind, gust, QNH, visibility, temperature, cloud, rain from these keys, so live values reach ATIS and calls with no ATC change. The ATIS letter moves when wind, QNH, visibility or rain change (`atc_controller.gd`).

**What it cannot represent today**
- More than one cloud layer. High cloud is a fixed cirrus (0.6 in `sky_time.gd`). Cloud thickness is fixed (`WeatherFx.CLOUD_THICK`).
- Dew point or humidity. Cloud base is set by hand, not from the temperature spread.
- A temperature profile. Only ISA lapse (6.5 K/km) plus one offset.
- A wind profile from real data: only surface (log law, z0 0.15 m) and one "aloft" value.
- Fog and mist (`vfog_rules.gd` `MIST_ENABLED` is false). Snow, hail.
- Placing real storm cells (no radar source). Cells are generated from a seed.
- Wet-runway braking: `fdm/gear_ground.gd` uses a fixed `BRAKE_MU` 0.45. Wetness only changes looks.
- Humidity in air density. Sun position for the whole map is one point (small error in Kerala).

## 2. Data sources (tested 2026-11-05 with curl; none needs a key)

| | NOAA Aviation Weather | Open-Meteo | met.no Locationforecast | Ogimet / VATSIM METAR |
|---|---|---|---|---|
| What | Observed METAR, TAF, station list | Model forecast and "current" at any point | Model forecast at any point | Observed METAR text |
| Gives | wind, gust, vis, weather, cloud layers + bases, T, dew point, QNH | all surface fields, winds/T/RH at 13 pressure levels (1000-250 hPa) plus 80/120/180 m, cloud low/mid/high, visibility, CAPE, freezing level, boundary layer, gusts, weather code | surface fields, cloud fractions; no winds aloft seen (the "complete" call did not parse in my test: unverified) | raw METAR only |
| Update | METAR 30-60 min; cache file every minute | model hourly, "current" every 15 min | hourly | as NOAA |
| Terms | 100 req/min, 400 rows, custom User-Agent advised, no stated attribution rule | free tier non-commercial, 600/min, 5,000/h, 10,000/day, CC BY 4.0, link "Weather data by Open-Meteo.com" next to the data | User-Agent with contact required, cache, honour Expires, coords max 4 decimals, CC BY 4.0 | VATSIM answered `https://metar.vatsim.net/VABB`; terms not found: skip |
| In Godot | HTTPRequest + JSON | HTTPRequest + JSON | HTTPRequest + JSON | text |
| Reliability | very good | no uptime promise | good | unknown |

NOAA GFS/NOMADS and ECMWF open data are GRIB2: heavy and need a decoder. Not used. CheckWX needs a key: excluded.

**Recommendation.** Primary: NOAA METAR for what is observed (wind, visibility, cloud bases, weather, QNH), plus Open-Meteo for what no METAR gives (winds aloft, freezing level, CAPE, boundary layer). Fallback: Open-Meteo alone, for every airport with no METAR. One call each, about every 15 minutes.

**The owner's region.** METAR test, one `bbox` call (8-20 N, 72-78 E) returned 21 stations, all observed 05 Nov 06:00-07:00Z: VABB, VAJJ, VOCI, VOCL, VOML, VOGO, VOGA, VOTV, VOKN, VASD, VAKP, VOSR and others. VABB `09006KT 3000 FU NSC 36/19 Q1013`; VOCI `27004KT 4500 HZ FEW015 SCT020 FEW025CB 33/23 Q1011`. VOBL and VOMM also answer. **VAPO (Pune) has no METAR in the NOAA feed** (empty for 168 h) but has a TAF. Pune is the home field of the lessons, so it runs on Open-Meteo. Open-Meteo at Pune returned winds at 10 m, 80-180 m and all pressure levels, freezing level 5,210 m, boundary layer 1,615 m, CAPE 50 J/kg.

**Licence.** A GPL hobby game with no ads or subscriptions fits the Open-Meteo non-commercial list, but its terms do not name open-source projects. The owner decided not to ask them (decision 6): we use the free tier under its published terms, with the credit link. The risk is that they could object later, so Open-Meteo sits behind one small source interface (W1) and can be swapped or switched off without touching the rest. Their page asks for a link next to the data; CC BY also asks to say data was changed. NOAA data: I found no attribution rule; we credit it anyway.

## 3. Design

**Parameters and mapping.** One pure module `world/live/live_map.gd`: input = parsed METAR and/or model JSON plus station elevation; output = `Session.setup`-style dictionary plus extra keys. No nodes, no network.

| Need | Source field | Rule | Feeds |
|---|---|---|---|
| Surface wind, gust | METAR dd/ff/G kt; model m/s x 1.944 | VRB or calm: keep last direction, speed under 3 kt | `wind_dir_deg`, `wind_kt`, `gust_kt` |
| Winds aloft | model 80/120/180 m + pressure levels with geopotential height | height AGL = level height - field elevation; sort | new `weather/wind_table` (below) |
| Temperature | METAR T; model 2 m | sea level = T + 0.0065 x elevation (so offset = T - ISA at the field) | `temp_c` |
| Dew point | METAR Td; model | kept for ATIS text and the checks | new `weather/dewpoint_c` |
| QNH | METAR Q or A; model `surface_pressure` | model: reduce with the ICAO formula, **not** `pressure_msl` (differs by 4 hPa at Pune now: 1019 vs 1015) | `qnh_hpa` |
| Visibility | METAR metres (9999 = 10 km or more, use 12 km); model `visibility` | clamp 200-40000 | `visibility_m` |
| Cloud | METAR FEW/SCT/BKN/OVC and bases (ft **AGL**) | cover 0.2 / 0.45 / 0.75 / 1.0; base = layer base + field elevation in ft; use the ceiling layer (lowest BKN/OVC), else the lowest layer; model: base 125 m x (T - Td) or the lowest level with RH 90 % or more | `cloud_cover`, `cloud_base_ft` |
| High cloud | METAR layers above 20,000 ft; model `cloud_cover_high` | amount | new `weather/cirrus` (replaces the fixed 0.6) |
| Rain | METAR `-RA` `RA` `+RA` `DZ` `SH` `TS`; model rain mm/h | 0.15 drizzle, 0.25 / 0.5 / 0.85 by intensity; mm/h / 10 for the model; showers stay under 0.3 | `precip` |
| Thunderstorm | `TS`, `CB`, `TCU`, weather code 95-99, CAPE | storms 0.7 if TS or CB with CAPE over 1000; else 0 | `storms`, `convection` |
| Thermals | model boundary layer height, day only | 500 m = 0, 2500 m = 1; less under overcast | `convection` |
| Turbulence | METAR gust spread, wind, model gusts | target sigma_w = max(0.1 x wind in m/s, gust spread / 5); solve the slider so `weather.gd` gives that sigma | `turbulence` |
| Icing | model T and RH by level, CB | 0.3 if RH 90 % or more at a level between -20 and 0 C, 0.7 with CB; else 0 | `icing` |
| Time | UTC clock | IST = UTC + 5.5; day of year | `time_h`, `day_of_year` |
| Raw text | METAR | shown in the UI and ATC history | `weather/live_metar` |

**Smallest extensions.** (a) `weather/wind_table`: list of [height AGL m, from deg, kt]; `wind_at()` blends the log profile near the ground into the table, and falls back to today's two-point rule when empty. (b) `weather/cirrus` replaces the constant. (c) A flag `visibility_includes_precip`: METAR visibility already includes rain, and `WeatherVisuals.rain_visibility` would cut it again. (d) Simplification kept: one volumetric layer, multi-layer METARs collapse to the ceiling plus cirrus.

**Data flow.** `world/live/live_sources.gd` (HTTPRequest, 10 s timeout, User-Agent `libresim/<version> (repo URL)`), `live_cache.gd` (`user://live_weather.json` with fetch time and source), `live_blend.gd`. Nearest METAR station by distance from the start point (all stations come in one `bbox` call); used only within 50 km, else model-only. Order: live METAR + model, then live model, then last cache (shown with its age), then the chosen preset. Refresh at start, then every 15 min only if "Update during flight" is on. Only the aircraft's position is used (never cached as a track). In flight the blender moves each value to the new target over about 5 min (wind and direction by shortest angle, cloud base at most 300 ft/min, QNH 1 hPa/min); the pilot's altimeter setting is never touched.

**UI (Weather step, `conditions_page.gd`).** A "Live weather" switch above the presets. Shows: source and station ("VABB, observed 07:00Z, 28 min ago, 8 km away" or "Pune: model"), Refresh, the METAR line. While on, the preset row and sliders are read-only with a "Use as base" button that copies the live values into the sliders and turns live off. Offline: "No connection. Using the last data (3 h old)" or "Using the Fair preset." First use shows a notice: the game asks aviationweather.gov and open-meteo.com for weather, sends only rounded coordinates or a station id (your IP is visible to them), no account, you can switch it off. The attribution line at the bottom (`credits_screen.gd` ATTRIBUTION) gains "Weather: aviationweather.gov, Open-Meteo.com" while live is on; CREDITS.md and `docs/LICENSING.md` list both. Command line: `--live-weather` (`session.gd` `_parse_args`; works with `--airport`; ignored with `--lesson`). New setup keys: `live_weather`, `live_update` (false). Training lessons and the e2e/test runs never go live; saved flights keep the weather they had.

**Safety and privacy.** No key stored or needed. No personal data. Rate far below every limit. Never read a web page by scraping.

**Tests (no network in the suite).**
- Fixtures in `game/tests/fixtures/live_weather/`: VABB, VOCI and a CB/TS METAR JSON, an Open-Meteo reply for Pune and Kochi, with a `SOURCES.md` giving licence and fetch date.
- `tests/test_live_map.gd`: METAR parse and every rule above (AGL to AMSL base, sea-level temperature, QNH from surface pressure, VRB, 9999, CB).
- `tests/test_live_fetch.gd`: a fake HTTP layer: timeout, 429, bad JSON, cache age, fallback order, blend steps.
- `tools/check_live_weather.sh`: real calls for the owner's airports, prints raw data and the mapped keys.

## 4. Physics: does it look right?

Targets and the test that catches an error. All tests are headless and go in `tests/test_live_physics.gd` unless noted.

| Item | Rule (source) | Game now | Numeric check |
|---|---|---|---|
| ISA lapse, temperature offset | 6.5 K/km; density altitude about +120 ft per degree (ICAO ISA) | Does it: `atmosphere_isa.gd`, `temp_c - 15` | ISA+20 at 5,000 ft: density altitude +2,400 ft; sea-level T from a 31.1 C field at 590 m gives freezing level about 5.37 km vs the model's 5.21 km (within 400 m) |
| QNH altimetry | about 27 ft per hPa near sea level (calculation from the ISA formula) | Does it: `indicated_altitude()`; `test_instruments.gd` checks only +1 inHg | 1013.25 vs 1003.25 changes the reading by 270-300 ft |
| Humidity in density | virtual temperature, vapour pressure | Not modelled | 36/19 C at 1013 hPa = +2.5 K = about +300 ft density altitude; optional, apply to density only (not to icing) |
| Dew point and cloud base | about 125 m (400 ft) per degree of spread ([Cloud base](https://en.wikipedia.org/wiki/Cloud_base)) | No humidity; base set directly | mapping: 30/20 C gives 1,250 m AGL; Pune adds 592 m (a METAR BKN015 there is about 3,450 ft AMSL) |
| Wind profile | log law with roughness; power law about 0.14; veering with height (MathWorks/UWO notes: [exponents](https://www.eng.uwo.ca/people/esavory/blnotes.doc)) | Partly: log law at z0 0.15 (x1.55 at 100 m, clamp 1.6), veer fixed +10 deg; no real shear | `wind_at(10 m)` equals the METAR wind within 0.5 kt; `wind_at` at 80/180 m and each pressure level equals the table |
| Wind and ground speed | ground speed = TAS minus headwind | Does it (`wind_ned` into the FDM) | 10 kt headwind: ground speed on final drops 10 kt (add to `test_systems.gd`) |
| Shear on the glide path | decreasing headwind lowers airspeed at once | Partly: log profile only | with a table giving 12 kt less at 100 ft than at 300 ft, airspeed at fixed controls drops about 12 kt within a few seconds |
| Turbulence | Dryden model: low altitude sigma_w about 0.1 x wind at 20 ft; light / moderate / severe near 15 / 30 / 45 kt (MIL-F-8785C, MIL-HDBK-1797: [MathWorks Dryden](https://www.mathworks.com/help/aeroblks/drydenwindturbulencemodelcontinuous.html); thresholds not checked against the handbook) | Partly: first-order filtered noise, fixed 250 m scale (true Dryden scale grows with height), sigma = slider x cloud factor x (1 + 0.15 x wind) x 1.4 below 300 m | 600 s run: measured vertical sigma within 25 % of the mapped target at 10 and 20 kt |
| Thunderstorm, microburst | peak wind change about 45 kt, downdraft 4,000-6,000 fpm (training sources, not authoritative: [ATSB](https://atsb.gov.au/node/8864)) | Partly: outflow up to 13 m/s (26 m/s across), downdraft up to 10 m/s (about 2,000 fpm), `cloud_storm.gd` | extend `test_cloud_storms.gd`: live TS gives storms 0.7 and a core |
| Icing | visible moisture, -20 to 0 C; ice forms from +2 (game's band) | Does it: `systems/icing.gd`, band uses the sim's lapse | no icing outside the band; freezing level check above; extend `test_icing.gd` |
| Visibility | contrast threshold 5 % gives extinction 3 / V (WMO) | Does it: `WeatherVisuals.fog_density`, tested | 3000 m reads 3 km; **METAR visibility must not be reduced again by rain** (gap c) |
| Rain effects | heavy rain: small lift loss, longer braking; wet friction well below dry; hydroplaning near 9 x sqrt(tyre psi) kt (Horne: [PPRuNe](https://www.pprune.org/tech-log/199039-9-x-square-root-tyre-pressure.html), unverified) | Lift/drag small and only above 0.6; **braking unchanged** | wet 50 kt stop at least 1.4 x dry (target to confirm against an AC 150/5200-30 table) |
| Light vs weather | cover and base decide sun occlusion; visibility decides haze | Does it: `sun_occlusion`, `aerosol_for_visibility`; `test_weather_visuals.gd` | OVC008 plus 1,500 m: no sun disc, aircraft above the base sees sun, inside cloud fog ramps in |

**Known gaps to fix before live weather can look right**
1. Wind table (aloft winds are one number; `apply_to_props` forces x1.6 and +10 deg).
2. METAR visibility double-reduced by rain (`sky_time.gd` line with `rain_visibility`).
3. Cloud base is AMSL in the sim, AGL in METARs (a trap at Pune and Bengaluru).
4. Wet-runway braking missing (`gear_ground.gd`).
5. One cloud layer and a constant cirrus.
6. Slider limits too narrow for real days (temperature 5-45 C, QNH 990-1035, visibility minimum 800 m): the live path must clamp, and fog under 800 m is not drawn.
7. Optional: humidity in density, a Dryden length scale that grows with height, mist (`MIST_ENABLED`).

## 5. Phases

| Phase | Work | Done when | Size |
|---|---|---|---|
| W0 | `live_map.gd`, METAR and model parsers, fixtures, mapping tests, gaps 1-3 and 5 | all mapping tests pass on the fixtures; no network code | 2-3 days |
| W1 | HTTP layer with one small interface per source (NOAA, Open-Meteo: each can be swapped or switched off), cache, fallback order, fake-HTTP tests, `check_live_weather.sh` | script prints sane keys for VABB, VOCI, VOGO, VAPO; offline run falls back to the preset | 2 days |
| W2 | Weather step switch, status line, first-use notice, `--live-weather`, setup keys, attribution | start screen shows source and age; lessons unaffected; works offline | 2-3 days |
| W3 | blender, "Update during flight", METAR line in ATC history, dew point in ATIS | no jump over 5 min of changes; altimeter setting untouched | 2 days |
| W4 | physics tests above, gaps 4, 6, 7 | the Section 4 checks all pass; before/after screenshots for VABB, VOCI, a TS case | 3 days |
| W5 | USAGE.md, CREDITS.md, LICENSING.md, PLAN.md and FlightGear comparison text, e2e run | docs match the code; `tools/e2e.sh` passes | 1 day |

## 6. Decisions (owner, 2026-11-05)

1. Lift "live data stay out" for this one feature: **yes**. Off by default, no key.
2. First source: **NOAA METAR plus Open-Meteo**, as in section 2.
3. Update during flight: **a switch, off by default**; the weather is read once at start.
4. Training lessons: **always ignore live weather**, so lessons repeat.
5. One extra attribution line (bottom bar plus credits): **yes**.
6. Email Open-Meteo about GPL use: **no**. Use the free tier under its published terms; keep the source swappable (see the Licence paragraph). If Open-Meteo ever objects: NOAA METAR plus a simple wind rule, Open-Meteo off.

Status: planned, nothing built. Start with W0.
