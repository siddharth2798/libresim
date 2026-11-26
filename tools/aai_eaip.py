"""Shared access to the AAI eAIP archive (https://aim-india.aai.aero.in/eAIP_Archive/<AIRAC date>/eAIP/).

Used by 28_airways.py (ENR 3.1 / 3.2 routes) and 29_ils_aip.py (AD 2.19 ILS). Pages are cached under
data/raw/aai/<cycle>/ and never shipped. For simulation only, not navigation.
"""
import time
import urllib.parse
import urllib.request
from datetime import date, timedelta

import common as c

HOST = "https://aim-india.aai.aero.in/eAIP_Archive/{cycle}/eAIP/{name}"
UA = "libresim-airways/1.0 (flight simulator; not for navigation)"


def airac_dates():
    d, end = date(2025, 1, 23), date.today() + timedelta(days=40)
    out = []
    while d <= end:
        out.append(d.strftime("%d-%m-%Y"))
        d += timedelta(days=28)
    return out


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    last = None
    for n in range(3):
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 - retry any transport or HTTP error
            last = e
            time.sleep(0.4 * (n + 1))
    raise last


def cached(cycle, name):
    path = c.RAW / "aai" / cycle / name.replace(" ", "_")
    if path.exists() and path.stat().st_size > 800:
        data = path.read_bytes()
        if not data.lstrip().lower().startswith(b"<!doctype html>"):
            return data
    data = fetch(HOST.format(cycle=cycle, name=urllib.parse.quote(name)))
    if data.lstrip().lower().startswith(b"<!doctype html>"):
        raise RuntimeError("not an eAIP page")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


def latest_cycle(*needles):
    """(cycle, menu html) of the newest archive whose menu page contains every needle (bytes)."""
    for cycle in reversed(airac_dates()):
        try:
            body = cached(cycle, "Menu-en-GB.html")
        except Exception:  # noqa: BLE001 - that cycle is not published (yet)
            continue
        if all(n in body for n in needles):
            return cycle, body.decode("utf-8", "replace")
    raise SystemExit("no AAI eAIP archive with " + ", ".join(n.decode() for n in needles))
