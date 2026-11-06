#!/usr/bin/env python3
"""Panel-line and rivet normal maps from the A320 albedo atlases.

Reads exterior_fuselage.png and exterior_engine.png (not modified). Writes
exterior_panels.png and exterior_engine_panels.png at the same pixel size.
Luminance minus a small blur keeps only thin marks: dark lines become shallow
grooves, compact rivet dots become small bumps, and large regions whose blur
is also dark (windows, the blue fin, registration boxes) stay flat.
OpenGL tangent-space normals, +Y toward the top of the image, mostly 128,128,255.

    tools/.venv/bin/python tools/a320_panel_normal.py
"""
import hashlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "game/aircraft/a320/models"
PAIRS = (
    ("exterior_fuselage.png", "exterior_panels.png"),
    ("exterior_engine.png", "exterior_engine_panels.png"),
)
# Residual darker than this, on paint the blur still calls light, is a thin mark.
DARK_EPS = 0.055
BLUR_DARK = 0.42  # blur this dark means a large region, not a line
GROOVE = 0.04     # max height drop for a line
BUMP = 0.028      # max height rise for a rivet
STRENGTH = 6.5


def main() -> None:
    _check_axes()
    for src_name, dst_name in PAIRS:
        src, dst = MODELS / src_name, MODELS / dst_name
        before = hashlib.md5(src.read_bytes()).hexdigest()
        rgb = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255.0
        normal = panels_to_normal(rgb)
        Image.fromarray(normal, "RGB").save(dst)
        after = hashlib.md5(src.read_bytes()).hexdigest()
        if before != after:
            raise SystemExit("source atlas was modified: %s" % src_name)
        _report(dst, normal)
    return None


def panels_to_normal(rgb: np.ndarray) -> np.ndarray:
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    radius = 2.2 if lum.shape[0] >= 3000 else 1.8
    blur = _blur(lum, radius)
    # Subtract the blur: broad shapes cancel, a few-pixel mark remains.
    dark = np.clip(blur - lum, 0.0, None)
    dark[blur < BLUR_DARK] = 0.0
    dark[dark < DARK_EPS] = 0.0
    thin = dark > 0.0
    rivet = _rivets(thin)
    height = np.full(lum.shape, 0.5, dtype=np.float32)
    height -= np.clip(dark * 0.22, 0.0, GROOVE)
    height[rivet] = 0.5
    height[rivet] += np.clip(dark[rivet] * 0.16, 0.0, BUMP)
    return _normals(_smooth(height), STRENGTH)


def _blur(lum: np.ndarray, radius: float) -> np.ndarray:
    u8 = np.clip(np.round(lum * 255.0), 0, 255).astype(np.uint8)
    out = Image.fromarray(u8, "L").filter(ImageFilter.GaussianBlur(radius=radius))
    return np.asarray(out, dtype=np.float32) / 255.0


def _window_sum(mask: np.ndarray, radius: int) -> np.ndarray:
    m = mask.astype(np.float32)
    ii = np.pad(m, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    h, w = m.shape
    y = np.arange(h)
    x = np.arange(w)
    y0 = np.clip(y - radius, 0, h)
    y1 = np.clip(y + radius + 1, 0, h)
    x0 = np.clip(x - radius, 0, w)
    x1 = np.clip(x + radius + 1, 0, w)
    return (ii[y1[:, None], x1[None, :]] - ii[y0[:, None], x1[None, :]]
            - ii[y1[:, None], x0[None, :]] + ii[y0[:, None], x0[None, :]])


def _rivets(thin: np.ndarray) -> np.ndarray:
    """Compact dark dots, not strokes. A line still has marks several pixels away."""
    near = _window_sum(thin, 2)
    far = _window_sum(thin, 6)
    return thin & (near >= 2) & (near <= 18) & ((far - near) <= 3)


def _smooth(height: np.ndarray) -> np.ndarray:
    k = np.array([0.25, 0.5, 0.25], dtype=np.float32)
    p = np.pad(height, ((0, 0), (1, 1)), mode="edge")
    hx = p[:, :-2] * k[0] + p[:, 1:-1] * k[1] + p[:, 2:] * k[2]
    p = np.pad(hx, ((1, 1), (0, 0)), mode="edge")
    return p[:-2] * k[0] + p[1:-1] * k[1] + p[2:] * k[2]


def _normals(height: np.ndarray, strength: float) -> np.ndarray:
    """OpenGL +Y: green points toward the top of the image. Flat is 128,128,255."""
    hp = np.pad(height, 1, mode="edge")
    dx = hp[1:-1, 2:] - hp[1:-1, :-2]
    dy = hp[2:, 1:-1] - hp[:-2, 1:-1]
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(dx, dtype=np.float32)
    length = np.maximum(np.sqrt(nx * nx + ny * ny + nz * nz), 1e-8)
    rgb = np.stack((nx / length, ny / length, nz / length), axis=-1)
    return np.clip(np.round((rgb * 0.5 + 0.5) * 255.0), 0, 255).astype(np.uint8)


def _check_axes() -> None:
    """A horizontal groove tilts toward itself: +Y is up the image (OpenGL)."""
    h = np.full((8, 8), 0.5, dtype=np.float32)
    h[4, :] = 0.4
    n = _normals(h, 4.0)
    if not (n[3, 4, 1] < 128 and n[5, 4, 1] > 128 and abs(int(n[0, 0, 0]) - 128) <= 1 and n[0, 0, 2] >= 250):
        raise SystemExit("normal axis check failed: %s / %s / %s" % (tuple(n[3, 4]), tuple(n[5, 4]), tuple(n[0, 0])))


def _report(path: Path, rgb: np.ndarray) -> None:
    step = max(rgb.shape[0] * rgb.shape[1] // 8000, 1)
    sample = rgb.reshape(-1, 3)[::step]
    unique = len({tuple(int(c) for c in px) for px in sample})
    flat = (rgb[..., 0] == 128) & (rgb[..., 1] == 128) & (rgb[..., 2] == 255)
    print("%s %dx%d unique_sample %d nonflat %.2f%% Bmean %.1f R %d..%d"
          % (path.name, rgb.shape[1], rgb.shape[0], unique, (1.0 - flat.mean()) * 100.0,
             float(rgb[..., 2].mean()), int(rgb[..., 0].min()), int(rgb[..., 0].max())))
    if unique < 2 or flat.mean() > 0.995:
        raise SystemExit("normal map looks flat: %s" % path.name)
    if float(rgb[..., 2].mean()) < 245.0:
        raise SystemExit("normal map is too strong (not mostly flat blue): %s" % path.name)


if __name__ == "__main__":
    main()
