"""Per-tile pavement raster (used by 27_pavement.py): same 4 m lattice and orientation as road_raster.py.

RGBA8, row 0 = north, RN x RN texels of RES metres over a level-0 tile:
  R  pavement edge distance e (m, negative inside), byte = (e - E_MIN) / E_SPAN * 255, filtered
  G  signed lateral offset d from the nearest stand lead-in line (m, + = right of the aircraft's
     heading), byte = (d + D_MAX) / (2 D_MAX) * 255; 255 = no lead-in nearby; filtered
  B  concrete slab-joint direction, byte = angle mod 90 deg / 90 * 256 (per polygon), unfiltered
  A  bits 0-1 surface (0 none, 1 concrete, 2 asphalt), bits 2-7 stand wear 0..63 (63 where aircraft
     stand: oil stains; lower along the lead-in: tyre marks), unfiltered
Keep the constants in step with game/world/terrain_pavement.gdshaderinc.
"""
import math

import numpy as np
import shapely

import road_raster as rr

RES, RN = rr.RES, rr.RN
E_MIN, E_SPAN = -8.0, 16.0
D_MAX = 10.0
LEAD_BACK, LEAD_FWD = 60.0, 8.0  # m of lead-in behind / ahead of the stop that carry tyre marks


def centres(tx, ty, tile):
    """Texel centre coordinates (xs (RN,), ys (RN,)), rows from the SOUTH."""
    x0, y0 = tx * tile, ty * tile
    return x0 + (np.arange(RN) + 0.5) * RES, y0 + (np.arange(RN) + 0.5) * RES


def dominant_angle(pts):
    """Length-weighted dominant edge direction of a polygon, modulo 90 deg (rad, 0..pi/2)."""
    p = np.asarray(pts, np.float64)
    d = np.diff(np.vstack([p, p[:1]]), axis=0)
    ln = np.hypot(d[:, 0], d[:, 1])
    th = np.arctan2(d[:, 1], d[:, 0])
    z = np.sum(ln * np.exp(4j * th))  # 4 theta: directions 90 deg apart vote together
    return (np.angle(z) / 4.0) % (math.pi / 2)


def edge_field(geom, xs, ys):
    """Signed distance (m) to the boundary of geom (negative inside): exact near the edge, coarse elsewhere."""
    X, Y = np.meshgrid(xs, ys)
    inside = shapely.contains_xy(geom, X, Y)
    sd = rr.signed_dist(inside)
    near = np.abs(sd) < -E_MIN + 6.0
    if near.any():
        pts = shapely.points(X[near], Y[near])
        ex = shapely.distance(geom.boundary, pts)
        sd[near] = np.where(inside[near], -ex, ex)
    return sd, inside


def stand_fields(stands, xs, ys):
    """-> (d (RN, RN) lateral offset or nan, wear uint8 0..63), rows from the south."""
    d_out = np.full((RN, RN), np.nan, np.float32)
    best = np.full((RN, RN), np.inf, np.float32)
    wear = np.zeros((RN, RN), np.uint8)
    x0, y0 = xs[0] - RES / 2, ys[0] - RES / 2
    for sx, sy, hd, *_ in stands:
        fx, fy = math.sin(hd), math.cos(hd)
        r = LEAD_BACK + 12.0
        i0, i1 = max(0, int((sx - r - x0) / RES)), min(RN, int((sx + r - x0) / RES) + 1)
        j0, j1 = max(0, int((sy - r - y0) / RES)), min(RN, int((sy + r - y0) / RES) + 1)
        if i1 <= i0 or j1 <= j0:
            continue
        px = xs[i0:i1][None, :] - sx
        py = ys[j0:j1][:, None] - sy
        along = -(px * fx + py * fy)        # metres behind the stop (the way the aircraft comes from)
        lat = px * fy - py * fx             # + = right of the heading
        ok = (along > -LEAD_FWD) & (along < LEAD_BACK) & (np.abs(lat) < D_MAX - 1.0)
        score = np.abs(lat) + np.maximum(along - 20.0, 0.0) * 0.05
        sub_b = best[j0:j1, i0:i1]
        m = ok & (score < sub_b)
        if not m.any():
            continue
        sub_b[m] = score[m]
        d_out[j0:j1, i0:i1][m] = lat[m]
        # 63 where aircraft stand (stains), tyre marks fading along the lead-in and just past the stop
        w = np.where(along < -3.0, 1.0 - (-3.0 - along) / (LEAD_FWD - 3.0),
                     np.where(along < 16.0, 1.0, 0.82 - 0.7 * (along - 16.0) / (LEAD_BACK - 16.0)))
        wear[j0:j1, i0:i1][m] = np.clip(np.round(w[m] * 63.0), 0, 63).astype(np.uint8)
    return d_out, wear


def encode(sd, d_lat, angle_b, surf, wear):
    """-> uint8 (RN, RN, 4), row 0 = north."""
    r = np.clip(np.round((sd - E_MIN) / E_SPAN * 255.0), 0, 255).astype(np.uint8)
    g = np.where(np.isnan(d_lat), 255, np.clip(np.round((np.nan_to_num(d_lat) + D_MAX) / (2 * D_MAX) * 255.0), 0, 254))
    a = (surf.astype(np.uint8) & 3) | (np.where(surf > 0, wear, 0).astype(np.uint8) << 2)
    return np.flipud(np.dstack([r, g.astype(np.uint8), angle_b.astype(np.uint8), a]))
