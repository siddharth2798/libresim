"""Minimal vectorised BC1 (DXT1) encoder + DDS writer with a full mip chain.
Quality: bounding-box-on-principal-axis endpoints, nearest-palette indices.
Good enough for 10 m satellite imagery; ~0.5 s per 768^2 tile.
"""
import struct

import numpy as np


def _to565(c):
    c = np.clip(np.round(c), 0, 255).astype(np.uint32)
    return ((c[..., 0] >> 3) << 11) | ((c[..., 1] >> 2) << 5) | (c[..., 2] >> 3)


def _from565(v):
    r = ((v >> 11) & 31) * 255 / 31
    g = ((v >> 5) & 63) * 255 / 63
    b = (v & 31) * 255 / 31
    return np.stack([r, g, b], -1)


def encode_level(img):
    """img: HxWx3 uint8 -> bytes of BC1 blocks (pads to a multiple of 4)."""
    h, w, _ = img.shape
    ph, pw = (-h) % 4, (-w) % 4
    if ph or pw:
        img = np.pad(img, ((0, ph), (0, pw), (0, 0)), mode="edge")
    h, w, _ = img.shape
    blk = img.reshape(h // 4, 4, w // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3).astype(np.float32)
    mean = blk.mean(1, keepdims=True)
    d = blk - mean
    cov = np.einsum("bki,bkj->bij", d, d)
    axis = np.ones((blk.shape[0], 3), np.float32)
    for _ in range(4):  # power iteration for the principal axis
        axis = np.einsum("bij,bj->bi", cov, axis)
        axis /= np.linalg.norm(axis, axis=1, keepdims=True) + 1e-6
    proj = np.einsum("bki,bi->bk", d, axis)
    lo = mean[:, 0] + axis * proj.min(1, keepdims=True)
    hi = mean[:, 0] + axis * proj.max(1, keepdims=True)
    c0, c1 = _to565(hi), _to565(lo)
    swap = c0 < c1
    c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
    p0, p1 = _from565(c0), _from565(c1)
    pal = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3], 1)  # 4-colour mode
    dist = ((blk[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(-1)
    idx = dist.argmin(2).astype(np.uint32)
    same = c0 == c1  # 4-colour mode needs c0 > c1; equal endpoints -> all index 0
    idx[same] = 0
    bits = (idx << (2 * np.arange(16, dtype=np.uint32))).sum(1).astype(np.uint32)
    out = np.empty((blk.shape[0], 2), np.uint32)
    out[:, 0] = c0 | (c1 << 16)
    out[:, 1] = bits
    return out.astype("<u4").tobytes()


def mip_chain(img):
    levels = [img]
    while img.shape[0] > 1 or img.shape[1] > 1:
        h, w = max(img.shape[0] // 2, 1), max(img.shape[1] // 2, 1)
        a = img.astype(np.float32)
        a = a[: h * 2 if img.shape[0] > 1 else 1, : w * 2 if img.shape[1] > 1 else 1]
        if img.shape[0] > 1:
            a = (a[0::2] + a[1::2]) / 2
        if img.shape[1] > 1:
            a = (a[:, 0::2] + a[:, 1::2]) / 2
        img = np.round(a).astype(np.uint8)
        levels.append(img)
    return levels


def write_dds(path, img):
    levels = mip_chain(img)
    h, w, _ = img.shape
    data = b"".join(encode_level(l) for l in levels)
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000  # caps|height|width|pixelfmt|mipcount|linearsize
    pf = struct.pack("<II4sIIIII", 32, 0x4, b"DXT1", 0, 0, 0, 0, 0)
    linear = max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * 8
    hdr = struct.pack("<4sIIIIIII44x", b"DDS ", 124, flags, h, w, linear, 0, len(levels)) + pf
    hdr += struct.pack("<IIIII", 0x1000 | 0x400000 | 0x8, 0, 0, 0, 0)  # texture|mipmap|complex
    with open(path, "wb") as f:
        f.write(hdr + data)
