# Live-weather fixtures

Shaped like the feeds in `docs/LIVE-WEATHER-PLAN.md`. Not a verbatim download.

- `vabb.json`, `voci.json`, `ts.json`: NOAA Aviation Weather METAR JSON. The `rawOb` lines are the examples in that plan (5 Nov 2026). NOAA states no attribution rule; credited anyway. Simulation only.
- `pune.json`, `kochi.json`: Open-Meteo forecast shape, winds in m/s. Open-Meteo is CC BY 4.0. These numbers illustrate the mapping (Pune: field 31.1 C at 592 m, boundary layer 1,615 m, CAPE 50). They are not a stored copy of a forecast.
