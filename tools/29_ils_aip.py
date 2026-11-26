"""AAI eAIP AD 2.19 -> data/processed/ils_aip.json (gitignored): the REAL ILS of the sim's airports.

The Airports Authority of India publishes each aerodrome as one HTML page in the public eAIP archive
(the same archive step 28 reads). AD 2.19 lists, per ILS runway end, the localizer ident, frequency and
category, the glide-path remarks and the antenna coordinates. This step keeps those facts for the
airports of airports.json that have a page; step 14 matches them to the runways. The HTML stays in
data/raw/aai and is not shipped. Offline: pages already cached are reused, a failed fetch keeps the
old ils_aip.json (step 14 then falls back to its simulated ILS). For simulation only, not navigation.
"""
import json
import re
import sys

import aai_eaip as aai
import common as c
import ils_aip

PAGE = "IN-AD 2.1{icao}-en-GB.html"
MENU_PAGE = re.compile(r"IN-AD 2\.1([A-Z0-9]{4})-en-GB\.html")


def wanted():
    """ICAO codes of the sim's airports that have runways."""
    ap = json.loads((c.OUT / "airports.json").read_text())
    return sorted({a["icao"] for a in ap if a.get("icao") and len(a["icao"]) == 4 and a.get("runways")
                   and a.get("type") != "heliport"})


def main():
    out = c.OUT / "ils_aip.json"
    try:
        cycle, menu = aai.latest_cycle(b"IN-AD 2.1")
    except BaseException as e:  # noqa: BLE001 - SystemExit when nothing is reachable and nothing cached
        print(f"ils_aip: no eAIP archive reachable ({e}); keeping {'the old file' if out.exists() else 'nothing'}")
        return 0
    have = set(MENU_PAGE.findall(menu))
    pages, records, failed = [], [], []
    for icao in wanted():
        if icao not in have:
            continue
        try:
            body = aai.cached(cycle, PAGE.format(icao=icao)).decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001 - one page failing must not stop the rest
            failed.append(icao)
            print(f"ils_aip: {icao}: {e}")
            continue
        found = ils_aip.parse(body)
        pages.append(icao)
        for r in found:
            records.append({"airport": icao, **r})
        print(f"{icao}: " + (", ".join(f'{r["runway"]} {r["ident"]} {r["freq_mhz"]:.2f}' + (f' CAT {r["category"]}' if r["category"] else "")
                                       for r in found) or "no ILS"))
    if failed and not pages:
        print("ils_aip: every fetch failed; keeping the old file")
        return 0
    out.write_text(json.dumps({"source": "AIP India (AAI eAIP) AD 2.19", "cycle": cycle, "pages": pages,
                               "records": records}, indent=1))
    print(f"ils_aip: cycle {cycle}, {len(pages)} aerodrome pages, {len(records)} ILS runway ends")
    return 0


if __name__ == "__main__":
    sys.exit(main())
