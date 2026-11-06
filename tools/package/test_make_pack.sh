#!/usr/bin/env bash
# Manifest test for the A320 pack. No Godot and no tarball.
#   tools/package/test_make_pack.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

out="build/libresim-a320-list-only-check.tar.gz"
rm -f "$out"
list=$(tools/package/make_pack.sh --list list-only-check) || exit 1
if [ -e "$out" ]; then
	echo "make_pack --list wrote $out" >&2
	exit 1
fi

need() {
	if ! printf '%s\n' "$list" | grep -Fxq "$1"; then
		echo "missing from pack list: $1" >&2
		exit 1
	fi
}
need "game/aircraft/a320/aircraft.json"
need "third_party/a320-family/LICENSE"
need "LICENSE"
need "README.copyright.md"
need "NOTICE"
need "SOURCE-OFFER.txt"
need "third_party/a320-family/README.copyright.md"
need "third_party/a320-family/SOURCE.md"
need "third_party/a320-family/THANKS.md"

if printf '%s\n' "$list" | grep -F 'game/aircraft/c172' >/dev/null; then
	echo "pack list includes game/aircraft/c172" >&2
	exit 1
fi
if printf '%s\n' "$list" | grep -F 'data/processed' >/dev/null; then
	echo "pack list includes data/processed" >&2
	exit 1
fi
if printf '%s\n' "$list" | grep -F 'third_party/c172p' >/dev/null; then
	echo "pack list includes third_party/c172p" >&2
	exit 1
fi

while IFS= read -r line; do
	[ -n "$line" ] || { echo "blank path in pack list" >&2; exit 1; }
	case "$line" in
		/*)
			echo "absolute path in pack list: $line" >&2
			exit 1
			;;
		LICENSE|NOTICE|README.copyright.md|SOURCE-OFFER.txt) ;;
		game/aircraft/a320/*) ;;
		third_party/a320-family/LICENSE|\
		third_party/a320-family/README.copyright.md|\
		third_party/a320-family/SOURCE.md|\
		third_party/a320-family/THANKS.md|\
		third_party/a320-family/NOTICE) ;;
		*)
			echo "unexpected path in pack list: $line" >&2
			exit 1
			;;
	esac
done <<EOF
$list
EOF

default_list=$(tools/package/make_pack.sh --list) || exit 1
if [ "$list" != "$default_list" ]; then
	echo "pack list changed with the version argument" >&2
	exit 1
fi

count=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
echo "make_pack: ok ($count paths)"
