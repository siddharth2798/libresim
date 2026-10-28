<p align="center"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="game/branding/logo_wide_dark.png">
  <img src="game/branding/logo_wide.png" alt="libresim" width="560">
</picture></p>

# libresim

A free, offline flight simulator for the Mumbai–Pune region (with a corridor down to Kochi), built with Godot 4. It has two aircraft: a realistic Cessna 172 and a simplified A320-family twin-jet.

- **Terrain:** real Copernicus 30 m elevation with Sentinel-2 satellite imagery, ESA WorldCover land cover (cropland parcels, built-up, scrub, forest floor) as procedural ground detail, and runways and taxiways from OpenStreetMap.
- **Flight model:** a JSBSim-derived 6-DOF model validated against the C172S POH by headless test cards. The A320 uses the FlightGear A320-family JSBSim data (converted to JSON) with a fly-by-wire control law written for libresim; it is not validated against real-aircraft data.
- **Cessna 172:** the FlightGear c172p 3D model and cockpit, with live, physically modelled instruments. Your call sign is painted on the fuselage as the tail number (`--callsign=VT-LBR`, or the call sign in the options).
- **A320-family twin-jet:** fly-by-wire, FADEC turbofans, airliner systems (electrical, hydraulics, fuel, warnings), autopilot and glass cockpit displays (PFD, ND, engine and system pages), flown from a gate or a runway. It is the newer and cruder of the two: no FMGC flight plan or managed profile, no bleed or pack model, a borrowed turbojet sound, a generic white livery, and the jetway does not dock at the door. See [docs/A320-STATUS.md](docs/A320-STATUS.md) for what works and what does not.
- **Per-aircraft data:** an aircraft is a folder of JSON (`game/aircraft/<id>/`: flight model, systems, controls, ground handling, model and cockpit wiring), not code; see "Adding an aircraft" in [docs/USAGE.md](docs/USAGE.md).
- **Simulation:** systems, failures, weather with ridge lift off the Western Ghats, time of day and night lighting.

## Screenshots

Real in-game captures at 1920x1080 on the Ultra graphics preset, nothing edited (regenerate them with [`tools/make_screenshots.sh`](tools/make_screenshots.sh)).

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/01-vabb-golden-hour-final.jpg" alt="Cockpit view of a Cessna 172 on final approach to Mumbai runway 27 at sunset, with the sun on the horizon, approach lights ahead and broken cloud" width="100%"><br><sub>Cockpit view on final for Mumbai (VABB) runway 27, Cessna 172, sunset, broken cloud.</sub></td>
    <td width="50%"><img src="docs/screenshots/02-western-ghats.jpg" alt="Chase view of a Cessna 172 flying over a lake and forested hills of the Western Ghats with a cloud bank and haze on the horizon" width="100%"><br><sub>Chase view over the lakes and hills of the Western Ghats near Aamby Valley (VAAV), late afternoon, haze.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/03-night-approach.jpg" alt="Night approach to Mumbai runway 27 with approach lights, runway edge lights, lit city blocks and the aircraft's landing light on the ground" width="100%"><br><sub>Night approach to Mumbai (VABB) runway 27: approach and runway lights, city lights, landing light.</sub></td>
    <td width="50%"><img src="docs/screenshots/04-mumbai-terminal.jpg" alt="Aerial view at dusk of the Mumbai airport terminal with its glowing glass facade, jetways, apron floodlights and the city behind" width="100%"><br><sub>Mumbai (VABB) terminal and jetways at dusk, seen from above the apron.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/05-kochi-gate.jpg" alt="Cessna 172 parked at a gate at Kochi airport next to the terminal with its red tiled roof, a jetway, a fuel truck and baggage carts" width="100%"><br><sub>A gate at Kochi (VOCI) with the terminal, jetway, fuel truck and baggage carts, late afternoon.</sub></td>
    <td width="50%"><img src="docs/screenshots/06-monsoon-approach.jpg" alt="Cockpit view in heavy monsoon rain on approach to Mumbai, with rain streaks, low cloud and the runway approach lights barely visible ahead" width="100%"><br><sub>Monsoon approach to Mumbai (VABB) runway 27: heavy rain under a low cloud deck.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/07-training-landing.jpg" alt="Training mode Landing lesson in the cockpit, with the step card and live gauges on the left and a yellow glide-path ring ahead of the runway" width="100%"><br><sub>Training mode, Landing lesson: step card, live gauges and the glide-path ring.</sub></td>
    <td width="50%"><img src="docs/screenshots/08-moving-map.jpg" alt="Chase view of a Cessna 172 over Mumbai harbour beside the moving map, which shows satellite imagery, airports, ILS beams and a GPS direct-to line" width="100%"><br><sub>Moving map with a GPS direct-to line, over Mumbai and Navi Mumbai.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/09-start-screen.jpg" alt="libresim start screen with Free flight and Training choices over a flight scene" width="100%"><br><sub>Start screen: Free flight or Training.</sub></td>
    <td width="50%"><img src="docs/screenshots/10-airport-picker.jpg" alt="Free-flight setup showing the airport list and the Mumbai airport diagram with runways, taxiways and gate and remote stands" width="100%"><br><sub>Free-flight setup: pick an airport and a stand on its real taxiway map.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/11-a320-gate-kochi.jpg" alt="A320-family airliner parked at a gate at Kochi airport in warm evening light, with a jetway, the terminal's red tiled roof and a line of trees beyond the apron" width="100%"><br><sub>A320-family airliner at a gate at Kochi (VOCI), golden hour, seen from the nose.</sub></td>
    <td width="50%"><img src="docs/screenshots/12-a320-cockpit.jpg" alt="Cockpit view of the A320 in flight with the primary flight display, navigation display and engine display on the panel, and hills and coast through the windscreen" width="100%"><br><sub>A320 cockpit at 3,000 ft near Mumbai: primary flight display, navigation display in arc mode, engine page.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/13-a320-cruise.jpg" alt="Chase view of an A320-family airliner with gear retracted flying above a layer of scattered cumulus cloud with farmland below" width="100%"><br><sub>Chase view of the A320 above scattered cloud near Pune (VAPO), 9,000 ft, gear up.</sub></td>
    <td width="50%"><img src="docs/screenshots/14-a320-final-dusk.jpg" alt="A320-family airliner with its landing gear down on approach over the lit buildings of Mumbai at dusk, red wing-tip light visible, orange sky and first stars" width="100%"><br><sub>A320 on approach to Mumbai (VABB) runway 27 at dusk, gear down, over the lit suburbs.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/15-a320-aircraft-page.jpg" alt="Free-flight setup, aircraft step, showing the A320-family card with its description and specifications, the fuel and payload sliders and the weight and balance envelope chart" width="100%"><br><sub>Start screen, aircraft step: A320 specifications, fuel and payload sliders, and the weight and balance envelope (approximate).</sub></td>
    <td width="50%"><img src="docs/screenshots/16-callsign-tail-number.jpg" alt="Side view of a Cessna 172 parked at a gate with a fuel truck and terminal behind it, with the custom registration VT-LBR painted on the rear fuselage" width="100%"><br><sub>Cessna 172 at Pune (VAPO) wearing the call sign you choose as its tail number (VT-LBR here).</sub></td>
  </tr>
</table>

The A320 shown in the screenshots is the FlightGear A320-family aircraft model by Josh Davidson, Jonathan Redpath, merspieler, Matthew Maring, Thorsten Herrmann, Semir Gebran and others, based on work credited to Immersive Design Group (GPL-2.0-only), recoloured and converted by libresim, with a generic livery; it is not affiliated with or endorsed by Airbus, an airline or an engine maker ("Airbus" and "A320" are Airbus trademarks, used factually). See [CREDITS.md](CREDITS.md) and [third_party/a320-family](third_party/a320-family/SOURCE.md).

Screenshots show Sentinel-2 cloudless imagery by EOX IT Services GmbH (contains modified Copernicus Sentinel data 2024), Copernicus GLO-30 DEM © DLR e.V. and Airbus Defence and Space GmbH, land cover from ESA WorldCover 2021 v200 © ESA WorldCover project (CC BY 4.0; contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium), and map data © OpenStreetMap contributors (ODbL); see [CREDITS.md](CREDITS.md). The imagery is licensed for non-commercial use only (CC BY-NC-SA 4.0), so the screenshots follow the same terms (see [docs/LICENSING.md](docs/LICENSING.md)).

**Quick start:** double-click **Start libresim** (Linux: `Start libresim.desktop`, macOS: `Start libresim.command`; see [docs/USAGE.md](docs/USAGE.md)). The first time it opens a window that sets everything up; after that it just starts the game. Or from a terminal: `./run.sh` checks and installs the prerequisites (asking before any `sudo`), downloads the data, builds it and opens the game. Re-running it just launches the game. `./run.sh --help` lists the options; details are in [docs/USAGE.md](docs/USAGE.md).

## Relation to FlightGear and JSBSim

libresim is not a fork of FlightGear and contains no FlightGear or JSBSim source code. It is a separate simulator written in GDScript on the Godot engine, with its own flight-dynamics integrator, engine, systems, instruments, radios, ATC and world streaming. It does reuse FlightGear-project work as data and assets: the c172p 3D model, cockpit, textures and sounds (GPL-2.0-or-later, by the c172p team) four fgdata airport models (GPL-2.0), and the A320-family 3D model, cockpit and JSBSim flight, engine and systems data (GPL-2.0-only, converted by libresim), plus JSBSim's c172p aerodynamic, mass and propeller data (LGPL-2.1), which libresim converts to JSON and retunes. By file size most of the repository is those assets; by lines of code essentially none of it is. See [docs/PROVENANCE.md](docs/PROVENANCE.md) for the audit and numbers.

**Docs:**
- How to install, build the data, run and fly: [docs/USAGE.md](docs/USAGE.md)
- Roadmap: [PLAN.md](PLAN.md)
- How libresim differs from FlightGear (fact-checked comparison): [docs/LIBRESIM-VS-FLIGHTGEAR.md](docs/LIBRESIM-VS-FLIGHTGEAR.md)
- Where the code and assets come from (audit): [docs/PROVENANCE.md](docs/PROVENANCE.md)
- Credits: [CREDITS.md](CREDITS.md)
- Licences: [docs/LICENSING.md](docs/LICENSING.md)

**Licence:** libresim's own code is GPL-2.0-or-later (see [LICENSE](LICENSE)). The bundled FlightGear data files are GPL-2.0 (some "or later"), and the bundled A320-family data is GPL-2.0-only (no "or later"), so a complete distribution that includes it is GPL-2.0 as a whole (libresim's own GPL-2.0-or-later code may be combined with it; see [docs/LICENSING.md](docs/LICENSING.md)). Other third-party assets keep their own licences, as listed in [CREDITS.md](CREDITS.md). The map imagery used in the screenshots is CC BY-NC-SA 4.0, so do not sell or ship the game with it in paid or ad-supported stores.
