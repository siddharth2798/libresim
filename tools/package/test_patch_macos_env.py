#!/usr/bin/env python3
"""Test of patch_macos_env.py: python3 tools/package/test_patch_macos_env.py (also checks the Godot.app on this machine)."""
import plistlib
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import patch_macos_env as p

with tempfile.TemporaryDirectory() as d:
    plist = Path(d) / "Info.plist"
    # a plist that already has other keys and an LSEnvironment entry of its own: both are kept
    plist.write_bytes(plistlib.dumps({"CFBundleName": "libresim", "LSEnvironment": {"FOO": "bar", "SDL_JOYSTICK_MFI": "1"}}))
    env = p.patch(plist)
    got = plistlib.loads(plist.read_bytes())
    assert got["CFBundleName"] == "libresim", got
    assert got["LSEnvironment"] == {"FOO": "bar", "SDL_JOYSTICK_MFI": "0", "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS": "1"}, got
    assert env == got["LSEnvironment"]
    p.patch(plist)  # idempotent
    assert plistlib.loads(plist.read_bytes()) == got
    # no plist at all -> clean error code
    sys.argv = ["x", d]
    assert p.main() == 1
# a binary plist (what some tools write) loads and is rewritten as XML
with tempfile.TemporaryDirectory() as d:
    plist = Path(d) / "Info.plist"
    plist.write_bytes(plistlib.dumps({"A": 1}, fmt=plistlib.FMT_BINARY))
    p.patch(plist)
    assert plist.read_bytes().startswith(b"<?xml"), "not XML"
print("patch_macos_env: ok")
