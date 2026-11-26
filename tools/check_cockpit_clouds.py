#!/usr/bin/env python3
"""Frame-capture check: no cloud may draw on the A320 cockpit.

Renders the cockpit view twice (tests/showcase_cloud_scenes.gd: cloud_a320_cockpit_clear and cloud_a320_cockpit_broken,
the same place and time, one without cloud and one inside it), then compares the pixels that belong to the cockpit
(a third picture from the same run, tests/showcase_mask.gd: the aircraft alone on flat magenta, then opened to drop
particles and eroded by a pixel ring where the window edge anti-aliases). Cloud light is far brighter than the
cockpit, so a cockpit pixel that is much brighter in the cloud shot has cloud on it.

  tools/check_cockpit_clouds.py [--quality=high] [--rendering-method=forward_plus] [--rendering-driver=metal]
Needs a window (the showcase renders on screen), muted (--audio-driver Dummy). Exit 1 on failure.
Pillow is used for the pixels: /usr/local/bin/python3 has it, or `pip install pillow`.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
GODOT = Path.home() / ".local/bin/godot"
SIZE = (1280, 720)
EXCESS = 0.40  # luminance (0..1) a cockpit pixel may gain from the cloud shot: in-cloud light and exposure lift it by up to ~0.3
MAX_BAD = 0.002  # share of cockpit pixels allowed above EXCESS
OPEN = 11  # px: bits of "cockpit" smaller than this in the mask are particles / horizon specks, not the cockpit
RING = 5  # px: erosion of the cockpit mask off the window edge


def shoot(scene: str, out: Path, args: list) -> Path:
    env = dict(os.environ, FREESIM_SHOTS=str(out), FREESIM_SIZE="%dx%d" % SIZE)
    cmd = [str(GODOT), "--audio-driver", "Dummy"] + [a for a in args if a.startswith("--rendering")]
    cmd += ["--path", str(ROOT / "game"), "res://tests/debug_showcase.tscn", "--", "--scene=" + scene, "--mask"]
    cmd += [a for a in args if a.startswith("--quality")]
    subprocess.run(cmd, env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
    return out / (scene + ".png")


def cockpit_mask(path: Path) -> Image.Image:
    r, g, b = Image.open(path).convert("RGB").split()
    # background: red and blue well above green (the flat magenta, tone mapped)
    bg = ImageChops.darker(ImageChops.subtract(r, g).point(lambda v: 255 if v > 60 else 0),
                           ImageChops.subtract(b, g).point(lambda v: 255 if v > 60 else 0))
    cockpit = bg.point(lambda v: 255 - v)
    cockpit = cockpit.filter(ImageFilter.MinFilter(OPEN)).filter(ImageFilter.MaxFilter(OPEN))
    return cockpit.filter(ImageFilter.MinFilter(RING))


def compare(clear: Path, cloudy: Path) -> tuple:
    a, b = Image.open(clear).convert("L"), Image.open(cloudy).convert("L")
    w, h = a.size
    box = (0, 0, w, h - 40)  # the credits line at the bottom is UI
    cockpit = cockpit_mask(cloudy.with_name(cloudy.stem + "_mask.png")).crop(box)
    gain = ImageChops.subtract(b, a).crop(box).point(lambda v: 255 if v / 255.0 > EXCESS else 0)
    total = cockpit.histogram()[255]
    bad = ImageChops.darker(gain, cockpit).histogram()[255]
    return bad, total


def main() -> int:
    args = sys.argv[1:] or ["--quality=high"]
    with tempfile.TemporaryDirectory() as tmp:
        clear = shoot("cloud_a320_cockpit_clear", Path(tmp), args)
        cloudy = shoot("cloud_a320_cockpit_broken", Path(tmp), args)
        bad, total = compare(clear, cloudy)
    share = bad / max(total, 1)
    print("cockpit pixels %d, brighter in cloud by > %.2f: %d (%.3f %%, limit %.3f %%)" % (total, EXCESS, bad, 100 * share, 100 * MAX_BAD))
    if total < 50000:
        print("FAIL: the cockpit mask is too small, the shots are not what was expected")
        return 1
    if share > MAX_BAD:
        print("FAIL: cloud draws on the cockpit")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
