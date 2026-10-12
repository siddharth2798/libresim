"""Reusable aircraft shapes for the logo options (flat fills, simple geometry, nose to the right / up)."""
import math


def svg_doc(w, h, body, bg=None):
    rect = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{rect}{body}</svg>\n'


def g(body, x=0, y=0, scale=1.0, rot=0.0):
    return f'<g transform="translate({x:.2f} {y:.2f}) rotate({rot:.2f}) scale({scale:.4f})">{body}</g>'


def c172_side(fill, hole=False, accent=None, gear=True):
    """High-wing four-seat single in side view, nose to +x, about 218 wide, centred near the origin.
    `hole` punches the cabin windows out of the fuselage; `accent` is the cheat line."""
    f = fill
    soft = f'stroke="{f}" stroke-width="3" stroke-linejoin="round"'
    body = ("M107 3 C107 -3 102 -8 94 -9 L70 -11 C62 -11 58 -13 54 -18 L45 -27 L-6 -27 C-20 -27 -34 -16 -52 -11 "
            "L-103 -8 L-104 -2.5 C-70 2 -40 8 -10 13 L70 13 C80 13 86 11 94 9 C101 8 106 6 107 3 Z")
    win = " M57 -9 L45 -23 L18 -23 L18 -9 Z M11 -9 L11 -23 L-1 -23 L-27 -9 Z" if hole else ""
    parts = [
        f'<path d="{body}{win}" fill="{f}" fill-rule="evenodd" {soft}/>',
        f'<rect x="4" y="-38" width="50" height="10" rx="5" fill="{f}"/>',            # wing
        f'<path d="M-66 -10 L-93 -50 L-106 -50 L-104 -10 Z" fill="{f}" {soft}/>',     # fin
        f'<rect x="-108" y="-12" width="38" height="6" rx="3" fill="{f}"/>',          # tailplane
        f'<path d="M35 12 L25 -28" stroke="{f}" stroke-width="3.6" stroke-linecap="round"/>',  # wing strut
        f'<rect x="105" y="-27" width="3.6" height="54" rx="1.8" fill="{f}"/>',       # propeller
    ]
    if gear:
        parts += [
            f'<path d="M12 12 L14 29 M70 12 L72 27" stroke="{f}" stroke-width="3.6" stroke-linecap="round"/>',
            f'<circle cx="14" cy="32" r="7.5" fill="{f}"/><circle cx="72" cy="30" r="6.5" fill="{f}"/>',
        ]
    if accent:
        parts.append(f'<path d="M86 0 L-99 -4.8" stroke="{accent}" stroke-width="3.4" stroke-linecap="butt"/>')
    return "".join(parts)


def _parts(fill, length, ds):
    return f'<g transform="scale({length / 100.0:.4f})" fill="{fill}">' + "".join(f'<path d="{d}"/>' for d in ds) + "</g>"


def plane_top(fill, length=100.0):
    """Straight-wing light aircraft seen from above, nose up, centred on the origin; `length` = nose to tail."""
    return _parts(fill, length, [
        "M0 -50 C5 -50 6.5 -40 6.5 -28 L6.5 18 C6.5 30 3 42 1.6 50 L-1.6 50 C-3 42 -6.5 30 -6.5 18 L-6.5 -28 C-6.5 -40 -5 -50 0 -50 Z",
        "M5 -14 L52 -14 L52 4 L5 4 Z", "M-5 -14 L-52 -14 L-52 4 L-5 4 Z",
        "M4 34 L22 34 L22 44 L3 44 Z", "M-4 34 L-22 34 L-22 44 L-3 44 Z"])


def plane_swept(fill, length=100.0):
    """Swept-wing aircraft icon seen from above, nose up, centred on the origin (reads well at dot size)."""
    return _parts(fill, length, [
        "M0 -50 C4.5 -50 6 -40 6 -30 L6 36 L3 50 L-3 50 L-6 36 L-6 -30 C-6 -40 -4.5 -50 0 -50 Z",
        "M4 -16 L50 16 L50 27 L4 8 Z", "M-4 -16 L-50 16 L-50 27 L-4 8 Z",
        "M3 34 L22 46 L22 53 L3 46 Z", "M-3 34 L-22 46 L-22 53 L-3 46 Z"])


def polar(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy - r * math.sin(a)


def swept_bbox(length, rot):
    """Bounding box (x0, y0, x1, y1) of plane_swept(length) rotated by `rot` degrees (SVG, clockwise)."""
    k, a = length / 100.0, math.radians(rot)
    pts = [(0, -50), (50, 16), (50, 27), (22, 46), (22, 53), (0, 50), (-50, 16), (-50, 27), (-22, 46), (-22, 53)]
    xy = [((x * math.cos(a) - y * math.sin(a)) * k, (x * math.sin(a) + y * math.cos(a)) * k) for x, y in pts]
    xs, ys = [p[0] for p in xy], [p[1] for p in xy]
    return min(xs), min(ys), max(xs), max(ys)
