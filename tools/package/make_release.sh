#!/usr/bin/env bash
# Build release packages from the current checkout + generated data.
#   tools/package/make_release.sh [version]        (default version: 0.1.0-dev)
# Produces in build/:
#   free-sim-<v>-linux-x86_64.tar.gz      binary + .pck + data/ + licences (any distro)
#   free-sim-<v>-x86_64.AppImage          single-file Linux app (needs appimagetool, auto-downloaded)
#   free-sim-<v>-macos-universal.zip      .app with data in Contents/Resources (ad-hoc signed)
#   free-sim-<v>-source.tar.gz            exact source of this build (GPL corresponding source)
# Flatpak: see packaging/flatpak/ (builds from the tar.gz).
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
V="${1:-0.1.0-dev}"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
B="$ROOT/build"
DATA="$ROOT/data/processed"
rm -rf "$B" && mkdir -p "$B/linux/free-sim" "$B/macos"

# 1. runtime data subset (no intermediate OSM files the game doesn't read)
stage_data() {  # $1 = destination data dir
	mkdir -p "$1"
	cp -r "$DATA/terrain" "$DATA/buildings" "$1/"
	cp "$DATA/airports.json" "$DATA/navaids.json" "$DATA/runways.json" "$DATA/airport_ops.json" "$DATA/ils.json" "$1/"
	mkdir -p "$1/terminals"  # landmark terminal models (not the OSM extracts)
	cp "$DATA"/terminals/*.glb "$DATA"/terminals/*_model.json "$1/terminals/" 2>/dev/null || true
	cp "$ROOT/packaging/DATA-LICENSES.txt" "$1/"
}
stage_docs() {  # $1 = destination folder
	cp "$ROOT/LICENSE" "$ROOT/CREDITS.md" "$ROOT/README.md" "$1/"
	mkdir -p "$1/docs" "$1/licenses"
	cp "$ROOT/docs/USAGE.md" "$ROOT/docs/LICENSING.md" "$1/docs/"
	cp -r "$ROOT/third_party" "$1/"
	cp "$ROOT/packaging/licenses/"* "$1/licenses/"
}

# 2. Linux
"$GODOT" --headless --path game --export-release "Linux" "$B/linux/free-sim/free-sim.x86_64"
stage_data "$B/linux/free-sim/data"
stage_docs "$B/linux/free-sim"
cp packaging/linux/free-sim.sh packaging/linux/free-sim.desktop packaging/linux/free-sim.png "$B/linux/free-sim/"
tar -C "$B/linux" -czf "$B/free-sim-$V-linux-x86_64.tar.gz" free-sim

# 3. AppImage
AIT="$ROOT/data/raw/tools/appimagetool-x86_64.AppImage"
if [ ! -x "$AIT" ]; then
	mkdir -p "$(dirname "$AIT")"
	curl -sSfL -o "$AIT" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
	chmod +x "$AIT"
fi
APPDIR="$B/linux/free-sim.AppDir"
cp -r "$B/linux/free-sim" "$APPDIR"
cp packaging/linux/AppRun "$APPDIR/AppRun" && chmod +x "$APPDIR/AppRun"
ARCH=x86_64 "$AIT" --appimage-extract-and-run "$APPDIR" "$B/free-sim-$V-x86_64.AppImage" >/dev/null

# 4. macOS (universal .app; data + docs inside Contents/Resources)
"$GODOT" --headless --path game --export-release "macOS" "$B/macos/free-sim.zip"
(cd "$B/macos" && unzip -q free-sim.zip && rm free-sim.zip)
APP=$(ls -d "$B/macos/"*.app | head -1)
stage_data "$APP/Contents/Resources/data"
stage_docs "$APP/Contents/Resources"
# adding files invalidates Godot's signature: re-sign ad-hoc with rcodesign (runs on Linux).
# For distribution outside your own Macs, sign with a Developer ID and notarise instead.
RCS="$ROOT/data/raw/tools/rcodesign"
if [ ! -x "$RCS" ]; then
	mkdir -p "$(dirname "$RCS")"
	curl -sSfL https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F0.29.0/apple-codesign-0.29.0-x86_64-unknown-linux-musl.tar.gz \
		| tar -xz -C "$(dirname "$RCS")" --strip-components=1 --wildcards '*/rcodesign'
fi
"$RCS" sign "$APP" >/dev/null
(cd "$B/macos" && zip -qry "$B/free-sim-$V-macos-universal.zip" "$(basename "$APP")")

# 5. corresponding source
git archive --format=tar.gz --prefix="free-sim-$V/" -o "$B/free-sim-$V-source.tar.gz" HEAD

ls -lh "$B"/*.tar.gz "$B"/*.AppImage "$B"/*.zip
