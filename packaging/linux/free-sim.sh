#!/bin/sh
# Launcher for the tar.gz release: run from anywhere.
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/free-sim.x86_64" "$@"
