#!/usr/bin/env bash
# Build the separate, withdrawable A320 pack. The pack is GPL-2.0-only as a
# whole because it includes the FlightGear A320-family data. The libresim base
# game stays GPL-2.0-or-later and is not in this archive.
# Does not fetch upstream data (that is ./run.sh --a320) and does not run Godot.
# No network. Safe to run twice: the tarball is overwritten.
#
#   tools/package/make_pack.sh [--list] [version]
#
# Default version: 0.1.0-dev
# --list    print one relative path per line of what the archive contains
#           (files only, sorted, relative to the single top directory
#           libresim-a320-<version>/) and exit 0. Does not write the tarball.
# otherwise write build/libresim-a320-<version>.tar.gz
#
# Contents, and only these:
#   LICENSE                          copy of third_party/a320-family/LICENSE
#   README.copyright.md NOTICE SOURCE-OFFER.txt
#                                    libresim texts from tools/package/a320_pack/
#   game/aircraft/a320/              the whole aircraft folder
#   third_party/a320-family/         licence and provenance files that exist:
#                                    LICENSE, README.copyright.md, SOURCE.md,
#                                    THANKS.md, and NOTICE if it is there
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD

LIST=0
V=""
for arg in "$@"; do
	case "$arg" in
		--list) LIST=1 ;;
		-h|--help)
			echo "Usage: tools/package/make_pack.sh [--list] [version]"
			exit 0
			;;
		--*)
			echo "make_pack.sh: unknown option: $arg" >&2
			echo "Usage: tools/package/make_pack.sh [--list] [version]" >&2
			exit 2
			;;
		*)
			if [ -n "$V" ]; then
				echo "make_pack.sh: unexpected extra argument: $arg" >&2
				echo "Usage: tools/package/make_pack.sh [--list] [version]" >&2
				exit 2
			fi
			V=$arg
			;;
	esac
done
V=${V:-0.1.0-dev}
case "$V" in
	.|..|*[!A-Za-z0-9._-]*)
		echo "make_pack.sh: version must be a plain token such as 0.1.0-dev (got: $V)" >&2
		exit 2
		;;
esac

AIR="$ROOT/game/aircraft/a320"
UP="$ROOT/third_party/a320-family"
TEXTS="$ROOT/tools/package/a320_pack"
if [ ! -d "$AIR" ]; then
	echo "make_pack.sh: missing aircraft folder game/aircraft/a320" >&2
	exit 1
fi
if [ ! -f "$UP/LICENSE" ]; then
	echo "make_pack.sh: third_party/a320-family/LICENSE is missing." >&2
	echo "make_pack.sh: the A320 pack is GPL-2.0-only and cannot be built without that upstream licence text. Stop." >&2
	exit 1
fi
for f in README.copyright.md NOTICE SOURCE-OFFER.txt; do
	if [ ! -f "$TEXTS/$f" ]; then
		echo "make_pack.sh: missing pack text tools/package/a320_pack/$f" >&2
		exit 1
	fi
done

# $1 = pack root (the libresim-a320-<version>/ directory)
stage_pack() {
	local dest=$1 name
	mkdir -p "$dest/game/aircraft" "$dest/third_party/a320-family"
	cp -R "$AIR" "$dest/game/aircraft/a320"
	for name in LICENSE README.copyright.md SOURCE.md THANKS.md NOTICE; do
		if [ -f "$UP/$name" ]; then
			cp "$UP/$name" "$dest/third_party/a320-family/$name"
		fi
	done
	cp "$UP/LICENSE" "$dest/LICENSE"
	cp "$TEXTS/README.copyright.md" "$dest/README.copyright.md"
	cp "$TEXTS/NOTICE" "$dest/NOTICE"
	cp "$TEXTS/SOURCE-OFFER.txt" "$dest/SOURCE-OFFER.txt"
	find "$dest" \( -name .DS_Store -o -name '._*' \) -type f -delete
}

# Files only, paths relative to the pack root, C-sorted.
list_files() {
	local dest=$1
	(
		cd "$dest"
		find . -type f -print
	) | sed 's|^\./||' | LC_ALL=C sort
}

prefix="libresim-a320-$V"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/libresim-a320-pack.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
export COPYFILE_DISABLE=1
stage_pack "$tmp/$prefix"

if [ "$LIST" -eq 1 ]; then
	list_files "$tmp/$prefix"
	exit 0
fi

out="$ROOT/build/libresim-a320-$V.tar.gz"
COPYFILE_DISABLE=1 tar -C "$tmp" -czf "$tmp/pack.tar.gz" "$prefix"
mkdir -p "$ROOT/build"
mv -f "$tmp/pack.tar.gz" "$out"
echo "$out"
ls -lh "$out"
