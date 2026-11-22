"""A320 flight-deck legend masks: which texels of a button atlas glow at night.

The night panel lighting (game/aircraft/common/cockpit_lighting.gd) gives the legend materials a dim emission.
Using the albedo itself as the emission made every grey knob and button body glow white at night. This writes
<atlas>_emit.png beside each atlas: warm white where the albedo is a bright, near-neutral legend (lettering, the
white ON caption rims), black everywhere else (knob bodies, panel paint, coloured annunciator art, the green
FCU bars, which have their own lamp: aircraft/common/cockpit_bar_lamps.gd).

Run:  tools/.venv/bin/python -I tools/a320_legend_mask.py
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

MODELS = Path(__file__).resolve().parent.parent / "game" / "aircraft" / "a320" / "models"
ATLASES = ["interior_fd_buttons.png"]
LUM_MIN = 0.78   # legends are near white; knob and button bodies sit at 0.4-0.6
SAT_MAX = 0.22   # coloured art (red, amber, green, cyan captions) is left dark
WARM = (1.0, 0.96, 0.88)  # backlight tint (the emission colour stays black: Godot adds it to the texture)


def mask(rgb: np.ndarray) -> np.ndarray:
    f = rgb.astype(np.float32) / 255.0
    mx = f.max(axis=2)
    mn = f.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    lum = f @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    return ((lum > LUM_MIN) & (sat < SAT_MAX)).astype(np.uint8) * 255


def main() -> int:
    for name in ATLASES:
        src = MODELS / name
        rgb = np.asarray(Image.open(src).convert("RGB"))
        m = mask(rgb)
        out = src.with_name(src.stem + "_emit.png")
        warm = np.stack([m, (m * WARM[1]).astype(np.uint8), (m * WARM[2]).astype(np.uint8)], axis=2)
        Image.fromarray(warm, "RGB").save(out, optimize=True)
        print(f"{out.name}: {m.mean() / 255.0 * 100.0:.2f} % of texels glow")
    return 0


if __name__ == "__main__":
    sys.exit(main())
