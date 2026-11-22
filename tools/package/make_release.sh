#!/usr/bin/env bash
# Build release packages from the current checkout + generated data.
#   tools/package/make_release.sh [version]        (default version: 0.1.0-dev)
# Produces in build/:
#   libresim-<v>-linux-x86_64.tar.gz      binary + .pck + data/ + licences (any distro)
#   libresim-<v>-x86_64.AppImage          single-file Linux app (needs appimagetool, auto-downloaded)
#   libresim-<v>-macos-universal.zip      .app with data in Contents/Resources (ad-hoc signed)
#   libresim-<v>-source.tar.gz            exact source of this build (GPL corresponding source)
# Flatpak: see packaging/flatpak/ (builds from the tar.gz).
# Shader baker (export_presets.cfg shader_baker/enabled): the exports pre-compile the shaders into the .pck so the first
# start does not compile them. Godot can only bake with a GPU, so the exports run windowed (a short editor window opens)
# on the Forward+ renderer, the default the packages start on; on a machine with no display or GPU set HEADLESS=1
# (exports work, nothing is baked). macOS bakes Metal (macOS) and Vulkan (Linux); docs/USAGE.md "Packaging".
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
V="${1:-0.1.0-dev}"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
B="$ROOT/build"
DATA="$ROOT/data/processed"
rm -rf "$B" && mkdir -p "$B/linux/libresim" "$B/macos"

# game/override.cfg is this checkout's own renderer choice (Graphics.set_renderer). Godot loads it into the project
# settings (without --rendering-method the editor would run and bake that renderer): keep it aside while exporting.
# The windowed editor also re-saves game/project.godot in its own format (defaults dropped, same meaning): put it back.
OVR="$ROOT/game/override.cfg"
PG="$ROOT/game/project.godot"
[ -f "$OVR" ] && mv "$OVR" "$OVR.release-keep"
cp "$PG" "$PG.release-keep"
trap '[ -f "$OVR.release-keep" ] && mv "$OVR.release-keep" "$OVR"; mv "$PG.release-keep" "$PG"' EXIT
EXPORT=(--audio-driver Dummy --path game --rendering-method forward_plus)
if [ -n "${HEADLESS:-}" ]; then
	EXPORT=(--headless "${EXPORT[@]}")
	echo "make_release: HEADLESS=1, shaders are not baked (Godot needs a GPU to bake)" >&2
fi

# 1. runtime data subset (no intermediate OSM files the game doesn't read)
stage_data() {  # $1 = destination data dir
	mkdir -p "$1"
	cp -r "$DATA/terrain" "$DATA/buildings" "$1/"
	cp "$DATA/airports.json" "$DATA/navaids.json" "$DATA/runways.json" "$DATA/airport_ops.json" "$DATA/ils.json" "$1/"
	[ -f "$DATA/airways.json" ] && cp "$DATA/airways.json" "$1/"
	mkdir -p "$1/terminals"  # landmark terminal models (not the OSM extracts)
	cp "$DATA"/terminals/*.glb "$DATA"/terminals/*_model.json "$1/terminals/" 2>/dev/null || true
	cp "$ROOT/packaging/DATA-LICENSES.txt" "$1/"
}
stage_docs() {  # $1 = destination folder
	cp "$ROOT/LICENSE" "$ROOT/CREDITS.md" "$ROOT/README.md" "$1/"
	mkdir -p "$1/docs" "$1/licenses"
	cp "$ROOT/docs/USAGE.md" "$ROOT/docs/LICENSING.md" "$1/docs/"
	cp -r "$ROOT/docs/site" "$1/docs/"
	cp -r "$ROOT/third_party" "$1/"
	cp "$ROOT/packaging/licenses/"* "$1/licenses/"  # godot-*.txt, fira-sans-OFL.txt and dejavu-symbols-LICENSE.txt (the UI font and its symbol fallback are shipped; their licence texts must travel with them)
}

# 2. Linux
"$GODOT" "${EXPORT[@]}" --export-release "Linux" "$B/linux/libresim/libresim.x86_64"
stage_data "$B/linux/libresim/data"
stage_docs "$B/linux/libresim"
cp packaging/linux/libresim.sh packaging/linux/libresim.desktop packaging/linux/libresim.png "$B/linux/libresim/"
tar -C "$B/linux" -czf "$B/libresim-$V-linux-x86_64.tar.gz" libresim

# 3. AppImage
AIT="$ROOT/data/raw/tools/appimagetool-x86_64.AppImage"
if [ ! -x "$AIT" ]; then
	mkdir -p "$(dirname "$AIT")"
	curl -sSfL -o "$AIT" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
	chmod +x "$AIT"
fi
APPDIR="$B/linux/libresim.AppDir"
cp -r "$B/linux/libresim" "$APPDIR"
cp packaging/linux/AppRun "$APPDIR/AppRun" && chmod +x "$APPDIR/AppRun"
ARCH=x86_64 "$AIT" --appimage-extract-and-run "$APPDIR" "$B/libresim-$V-x86_64.AppImage" >/dev/null

# 4. macOS (universal .app; data + docs inside Contents/Resources)
"$GODOT" "${EXPORT[@]}" --export-release "macOS" "$B/macos/libresim.zip"
(cd "$B/macos" && unzip -q libresim.zip && rm libresim.zip)
APP=$(ls -d "$B/macos/"*.app | head -1)
stage_data "$APP/Contents/Resources/data"
stage_docs "$APP/Contents/Resources"
# joysticks on macOS 27 need SDL_JOYSTICK_MFI=0 (+ background events) in the process environment: a double-clicked
# app gets no shell exports, Launch Services applies Info.plist's LSEnvironment
python3 "$ROOT/tools/package/patch_macos_env.py" "$APP"
# adding files invalidates Godot's signature: re-sign ad-hoc with rcodesign (runs on Linux).
# For distribution outside your own Macs, sign with a Developer ID and notarise instead.
RCS="$ROOT/data/raw/tools/rcodesign"
if [ ! -x "$RCS" ]; then
	mkdir -p "$(dirname "$RCS")"
	curl -sSfL https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F0.29.0/apple-codesign-0.29.0-x86_64-unknown-linux-musl.tar.gz \
		| tar -xz -C "$(dirname "$RCS")" --strip-components=1 --wildcards '*/rcodesign'
fi
"$RCS" sign "$APP" >/dev/null
(cd "$B/macos" && zip -qry "$B/libresim-$V-macos-universal.zip" "$(basename "$APP")")

# 5. corresponding source
git archive --format=tar.gz --prefix="libresim-$V/" -o "$B/libresim-$V-source.tar.gz" HEAD

ls -lh "$B"/*.tar.gz "$B"/*.AppImage "$B"/*.zip
