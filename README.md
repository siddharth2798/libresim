# free-sim

A free, offline, realistic Cessna 172 flight simulator for the Mumbai–Pune region, built with Godot 4.

- **Terrain:** real Copernicus 30 m elevation with Sentinel-2 satellite imagery, and runways and taxiways from OpenStreetMap.
- **Flight model:** a JSBSim-derived 6-DOF model validated against the C172S POH by headless test cards.
- **Aircraft:** the FlightGear c172p 3D model and cockpit, with live, physically modelled instruments.
- **Simulation:** systems, failures, weather with ridge lift off the Western Ghats, time of day and night lighting.

**Quick start:** `./run.sh` checks and installs the prerequisites (asking before any `sudo`), downloads the data, builds it and opens the game. Re-running it just launches the game. `./run.sh --help` lists the options; details are in [docs/USAGE.md](docs/USAGE.md).

**Docs:**
- How to install, build the data, run and fly: [docs/USAGE.md](docs/USAGE.md)
- Roadmap: [PLAN.md](PLAN.md)
- How free-sim differs from FlightGear (fact-checked comparison): [docs/FREE-SIM-VS-FLIGHTGEAR.md](docs/FREE-SIM-VS-FLIGHTGEAR.md)
- Credits: [CREDITS.md](CREDITS.md)
- Licences: [docs/LICENSING.md](docs/LICENSING.md)

**Licence:** GPL-2.0-or-later (see [LICENSE](LICENSE)). Third-party assets keep their own licences, as listed in CREDITS.md.
