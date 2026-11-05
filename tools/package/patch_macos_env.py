#!/usr/bin/env python3
"""Put the joystick environment variables into a macOS .app's Info.plist (LSEnvironment).

On macOS 27 the SDL3 in Godot 4.7 lists no joystick unless SDL_JOYSTICK_MFI=0 is set before start
(its GameController driver hides HID joysticks such as the Thrustmaster TCA). Joystick events reach
a window only while it is the active app unless SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1. A
double-clicked app gets no shell exports, but Launch Services applies LSEnvironment. run.sh /
launch.sh export the same two variables for a source checkout.

  python3 tools/package/patch_macos_env.py path/to/libresim.app

Run it BEFORE signing (make_release.sh does): editing Info.plist breaks an existing signature.
Existing LSEnvironment entries are kept; the two variables are set (an old value of ours is overwritten).
"""
import plistlib
import sys
from pathlib import Path

ENV = {"SDL_JOYSTICK_MFI": "0", "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS": "1"}


def patch(plist_path: Path) -> dict:
    with open(plist_path, "rb") as f:
        info = plistlib.load(f)
    env = dict(info.get("LSEnvironment", {}))
    env.update(ENV)
    info["LSEnvironment"] = env
    with open(plist_path, "wb") as f:
        plistlib.dump(info, f, fmt=plistlib.FMT_XML)
    return env


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    plist = Path(sys.argv[1]) / "Contents" / "Info.plist"
    if not plist.is_file():
        print(f"no {plist}")
        return 1
    print("LSEnvironment:", patch(plist))
    return 0


if __name__ == "__main__":
    sys.exit(main())
