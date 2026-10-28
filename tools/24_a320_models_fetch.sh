#!/usr/bin/env bash
# Add the A320-family 3D models (GPL-2.0-only, pinned commit) to the sparse checkout of data/raw/fg/a320.
# Run tools/22_a320_fetch.sh first (it creates the clone); this script only ADDS paths, never touches the others.
# Sizes at the pinned commit (GitHub tree API): Models/ is 144 MB in total; we take about 92 MB:
#   Models/Fuselage/           exterior: res/A320-216.ac (airframe, gear, surfaces), res/CFM56.ac (engine), PNG textures, animation XML (hinge centres/axes: read as data, never executed)
#   Models/FlightDeck/res/     flight deck: fd_complete.ac (32 MB) and its PNG textures (71 MB in the folder; the converter uses only what the .ac references)
#   Models/Lights/             light glow definitions (reference for lamp positions only)
#   single files via `git show`: Models/A320-common.xml, A320-200-CFM.xml (model composition), Models/Liveries/CFM/2k/CFM56-white.png (clean engine texture),
#   and the 481-byte display-screen quads Models/Instruments/{PFD,ND,Upper-ECAM,Lower-ECAM,IESI}/res/*.ac (screen positions only; no canvas/Nasal code)
# NOT fetched (licence audit, docs/LICENSING.md): Models/Liveries/* airline textures (AAL AUA DAL SWR BAW SAS IAE/PW/NEO liveries, 4k fuselages), fuselage-dirt.png,
#   the rest of Models/Instruments/ (Nasal/canvas displays: libresim draws its own), Models/Effects/ (FlightGear .eff shader files), Models/Services/ (ground vehicles),
#   Models/Autopush/, FlightDeck/QRH/ and the 1.1 MB cockpit animation XML, Sounds/, Fonts/, Nasal/.
# Idempotent: does nothing when the files are already there. The checkout is untrusted data: nothing in it is ever executed.
# NB: `tools/22_a320_fetch.sh --force` deletes the clone; rerun this script afterwards.
# Usage: tools/24_a320_models_fetch.sh [--force]
set -Eeuo pipefail
cd "$(dirname "$0")/.."
PIN=fec1ecba767c8fffd145337b27012e89c01e3ade   # same pin as tools/22_a320_fetch.sh and third_party/a320-family/SOURCE.md
DST=data/raw/fg/a320
FORCE=0; [[ ${1:-} == --force ]] && FORCE=1
[[ -d $DST/.git ]] || { echo "a320: no clone at $DST: run tools/22_a320_fetch.sh first" >&2; exit 1; }
[[ $(git -C "$DST" rev-parse HEAD) == "$PIN" ]] || { echo "a320: clone is not at the pinned commit $PIN" >&2; exit 1; }
SINGLES=(Models/A320-common.xml Models/A320-200-CFM.xml Models/Liveries/CFM/2k/CFM56-white.png
  Models/Instruments/PFD/res/PFD1.ac Models/Instruments/PFD/res/PFD2.ac Models/Instruments/ND/res/ND.ac Models/Instruments/ND/res/ND_R.ac
  Models/Instruments/Upper-ECAM/res/Upper-ECAM.ac Models/Instruments/Lower-ECAM/res/Lower-ECAM.ac Models/Instruments/IESI/res/IESI.ac)
if ((!FORCE)) && [[ -f $DST/Models/Fuselage/res/A320-216.ac && -f $DST/Models/FlightDeck/res/fd_complete.ac ]]; then
  ok=1; for f in "${SINGLES[@]}"; do [[ -f $DST/$f ]] || ok=0; done
  ((ok)) && { echo "a320 models: already present ($(du -sh "$DST/Models" | cut -f1))"; exit 0; }
fi
git -C "$DST" sparse-checkout add Models/Fuselage Models/Fuselage/res Models/FlightDeck/res Models/Lights
git -C "$DST" checkout -q FETCH_HEAD 2>/dev/null || git -C "$DST" checkout -q "$PIN"
for f in "${SINGLES[@]}"; do
  mkdir -p "$DST/$(dirname "$f")"
  git -C "$DST" show "$PIN:$f" > "$DST/$f"     # lazy-fetches just this blob
done
# the dirt overlay is not needed and not wanted
rm -f "$DST/Models/Fuselage/res/fuselage-dirt.png"
echo "a320 models: fetched at $PIN ($(du -sh "$DST/Models" | cut -f1))"
