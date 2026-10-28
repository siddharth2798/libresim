#!/usr/bin/env bash
# Fetch the FlightGear A320-family data (GPL-2.0-only) that libresim's A320 converter needs.
# Sparse checkout, depth 1, pinned commit: FDE/ Engines/ Systems/ + the top-level files
# (A320-200-CFM-set.xml, LICENSE, README.copyright.md) + Docs/THANKS.md  ->  data/raw/fg/a320
# NOT fetched on purpose (licence audit, docs/LICENSING.md): Sounds/, Fonts/, Nasal/, WebPanel/, Models/
# (models come in phase P8), liveries, navdata. Idempotent: does nothing when the pinned commit is already checked out.
# The checkout is untrusted data: nothing in it is ever executed.
# Usage: tools/22_a320_fetch.sh [--force]
set -Eeuo pipefail
cd "$(dirname "$0")/.."
URL=https://github.com/legoboyvdlp/A320-family.git
BRANCH=dev
PIN=fec1ecba767c8fffd145337b27012e89c01e3ade   # tip of `dev` on 2026-10-28; also recorded in third_party/a320-family/SOURCE.md
DST=data/raw/fg/a320
FORCE=0; [[ ${1:-} == --force ]] && FORCE=1

if ((!FORCE)) && [[ -d $DST/.git ]] && [[ $(git -C "$DST" rev-parse HEAD 2>/dev/null) == "$PIN" ]] \
   && [[ -f $DST/A320-200-CFM-set.xml && -d $DST/FDE ]]; then
  echo "a320: already at $PIN ($DST)"; exit 0
fi
rm -rf "$DST"; mkdir -p "$DST"
git -C "$DST" init -q
git -C "$DST" remote add origin "$URL"
git -C "$DST" config core.sparseCheckout true
git -C "$DST" sparse-checkout init --cone
git -C "$DST" sparse-checkout set FDE Engines Systems Docs   # cone mode also keeps every top-level file
# fetch exactly the pinned commit (GitHub allows fetching an exact sha), blobs on demand
git -C "$DST" fetch -q --depth 1 --filter=blob:none origin "$PIN"
git -C "$DST" checkout -q FETCH_HEAD
got=$(git -C "$DST" rev-parse HEAD)
[[ $got == "$PIN" ]] || { echo "a320: expected $PIN, got $got" >&2; exit 1; }
# Docs/ is only needed for THANKS.md (authors); drop the rest of it from the working tree
find "$DST/Docs" -type f ! -name THANKS.md -delete 2>/dev/null || true
echo "a320: fetched $PIN into $DST ($(du -sh "$DST" | cut -f1))"
