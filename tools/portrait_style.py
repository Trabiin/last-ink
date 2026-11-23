#!/usr/bin/env python3
"""Portrait style trial (code only, no paid generation).

Turns the game portraits (assets/portraits/<id>.png, 512x768 RGBA) into candidate treatments that sit
closer to the pixel-art world, so they can be compared in the real dialogue scene before more portraits
are generated.

    python3 tools/portrait_style.py OUT_DIR quill velvette bran

writes OUT_DIR/<style>/<id>.png for every style in STYLES. tools/shot.gd can show them in place:
    xvfb-run -a godot --path . -s tools/shot.gd -- scene=town talk=quill_first portraits=OUT_DIR/ink ...

Styles
  grade    : full-res painting, colours pulled softly onto the game palette, darker and less saturated.
  ink      : flat cel shading in game-palette colours, heavy ink outline, paper grain ("Last Ink" look).
  pix336   : hi-res pixel art, 224x336, shown at 1 canvas px per pixel (2 screen px).
  pix168   : chunky pixel art, 112x168, same pixel size as the world (2 canvas px per pixel).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage
from skimage import color as skc

ROOT = Path(__file__).resolve().parent.parent
PAL_FILE = ROOT / "tools" / "style_palette.hex"
INK = np.array([0x12, 0x14, 0x1F], np.float32) / 255.0
STYLES = ["grade", "ink", "pix336", "pix168"]
SPECK = 20  # smallest loose island kept in pixel portraits (tests/test_portraits.gd checks the same)


def palette() -> np.ndarray:
    cols = []
    for line in PAL_FILE.read_text().splitlines():
        line = line.strip()
        if line.startswith("#"):
            cols.append([int(line[i:i + 2], 16) for i in (1, 3, 5)])
    return np.array(cols, np.float32) / 255.0


def load(pid: str):
    im = Image.open(ROOT / "assets" / "portraits" / f"{pid}.png").convert("RGBA")
    a = np.asarray(im, np.float32) / 255.0
    return a[..., :3], a[..., 3]


def save(rgb, alpha, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    out = np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)])
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA").save(path)


def to_lab(rgb):
    return skc.rgb2lab(np.clip(rgb, 0, 1))


def nearest(lab_px, pal_lab, chroma_w=1.0):
    """Index of the nearest palette colour for each Lab pixel (N,3). Chroma weighted a little lower so
    shading keeps its value and hue reads stay close."""
    w = np.array([1.0, chroma_w, chroma_w], np.float32)
    d = (((lab_px[:, None, :] - pal_lab[None, :, :]) * w) ** 2).sum(-1)
    return d.argmin(1), d


def grade(rgb, alpha, pal):
    """Soft palette pull: each pixel moves toward a distance-weighted blend of its nearest palette colours,
    then a darker, lower-saturation grade like the world's night/day ambience."""
    h, w, _ = rgb.shape
    lab = to_lab(rgb).reshape(-1, 3).astype(np.float32)
    pal_lab = to_lab(pal[None])[0].astype(np.float32)
    _, d = nearest(lab, pal_lab)
    k = np.exp(-(d - d.min(1, keepdims=True)) / 60.0)
    k /= k.sum(1, keepdims=True)
    pulled = (k @ pal_lab)
    mix = 0.65
    lab2 = lab * (1 - mix) + pulled * mix
    lab2[:, 0] = lab[:, 0] * 0.6 + lab2[:, 0] * 0.4  # keep the original values (detail), take the hues
    lab2[:, 1:] *= 0.8
    out = skc.lab2rgb(lab2.reshape(h, w, 3))
    # Slight crush: darker mids, lifted blacks toward ink blue-black, like the ambience grade.
    out = np.clip(out, 0, 1) ** 1.12
    out = out * 0.92 + INK * 0.08
    return out, alpha


def fg_kmeans(lab, mask, k, seed=1):
    """k-means colours of the foreground (Lab). Returns (centroids (k,3), labels for mask pixels)."""
    import cv2
    data = lab[mask].astype(np.float32)
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 40, 0.5)
    cv2.setRNGSeed(seed)
    _, labels, cent = cv2.kmeans(data, k, None, crit, 3, cv2.KMEANS_PP_CENTERS)
    return cent, labels.ravel()


def pull(cent, pal_lab, amt):
    """Move each colour part of the way onto its nearest game-palette colour (hue unity with the world),
    keeping more of its own value so faces keep their modelling."""
    idx, _ = nearest(cent, pal_lab, chroma_w=1.3)
    tgt = pal_lab[idx]
    out = cent * (1 - amt) + tgt * amt
    out[:, 0] = cent[:, 0] * (1 - amt * 0.5) + tgt[:, 0] * amt * 0.5
    out[:, 1:] *= 0.88
    return out


def smooth(rgb, sp=6, sr=16):
    import cv2
    bgr = (np.clip(rgb[..., ::-1], 0, 1) * 255).astype(np.uint8)
    ms = cv2.pyrMeanShiftFiltering(bgr, sp, sr)
    return ms[..., ::-1].astype(np.float32) / 255.0


def majority(idx, size):
    """Mode filter on palette indices (removes isolated pixels / speckle)."""
    best = np.zeros(idx.shape, np.float32) - 1
    out = idx.copy()
    for c in np.unique(idx):
        cnt = ndimage.uniform_filter((idx == c).astype(np.float32), size)
        m = cnt > best
        best[m] = cnt[m]
        out[m] = c
    return out


def quantize(rgb, solid, pal, k, amt):
    lab = to_lab(rgb).astype(np.float32)
    pal_lab = to_lab(pal[None])[0].astype(np.float32)
    cent, labels = fg_kmeans(lab, solid, k)
    cent = pull(cent, pal_lab, amt)
    cols = np.clip(skc.lab2rgb(cent[None])[0], 0, 1)
    idx = np.zeros(solid.shape, np.int32)
    idx[solid] = labels
    return idx, cols, lab


def dark_lines(lab, solid, rel=10, absl=20):
    L = lab[..., 0]
    loc = ndimage.uniform_filter(L, 9)
    return solid & (L < absl) & (L < loc - rel)


def paper(h, w, seed=7):
    rng = np.random.default_rng(seed)
    fine = ndimage.gaussian_filter(rng.normal(0, 1, (h, w)).astype(np.float32), 0.7)
    blot = ndimage.gaussian_filter(rng.normal(0, 1, (h, w)).astype(np.float32), 18)
    return fine / (fine.std() + 1e-6) * 0.022 + blot / (blot.std() + 1e-6) * 0.03


def ink(rgb, alpha, pal):
    """Flat cel regions in palette-pulled colours, the source's own ink lines made solid ink-black, a heavy
    silhouette line, paper grain and a worn, stamped edge."""
    solid = alpha > 0.5
    sm = smooth(rgb, 7, 20)
    idx, cols, lab = quantize(sm, solid, pal, 20, 0.4)
    idx = majority(idx, 3)
    out = cols[idx]
    lines = dark_lines(to_lab(rgb), solid, 7, 34)
    lines = ndimage.binary_opening(lines, np.ones((2, 2)))
    sil = solid & ~ndimage.binary_erosion(solid, iterations=3)
    out[lines | sil] = INK
    out = np.clip(out + paper(*alpha.shape)[..., None], 0, 1)
    rng = np.random.default_rng(3)
    noise = ndimage.gaussian_filter(rng.random(alpha.shape).astype(np.float32), 1.5)
    a = solid.astype(np.float32)
    edge = solid & ~ndimage.binary_erosion(solid, iterations=2)
    a[edge & (noise < 0.47)] = 0
    return out, a


def pixelate(rgb, alpha, pal, height, k=24, amt=0.4):
    """Hi-res pixel art: edge-preserving smooth, premultiplied box downscale, per-portrait palette of k
    colours pulled onto the game palette, singles tidied, 1px ink outline, darkest lines in ink."""
    h, w = alpha.shape
    tw = int(round(w * height / h))
    sm = smooth(rgb, 3, 10)
    pm = np.dstack([sm * alpha[..., None], alpha])
    im = Image.fromarray((np.clip(pm, 0, 1) * 255).astype(np.uint8), "RGBA").resize((tw, height), Image.BOX)
    d = np.asarray(im, np.float32) / 255.0
    a = d[..., 3]
    c = d[..., :3] / np.maximum(a[..., None], 1e-4)
    blur = ndimage.gaussian_filter(c, (1.0, 1.0, 0))
    c = np.clip(c + (c - blur) * 0.5, 0, 1)
    solid = a > 0.5
    # thin strands break into loose bits when shrunk: islands under SPECK px (8-connected) go
    lab8, n8 = ndimage.label(solid, np.ones((3, 3)))
    if n8 > 1:
        sizes = ndimage.sum(solid, lab8, range(1, n8 + 1))
        solid &= ~np.isin(lab8, np.nonzero(sizes < SPECK)[0] + 1)
    idx, cols, lab = quantize(c, solid, pal, k, amt)
    maj = majority(idx, 3)
    same = np.zeros_like(solid)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        same |= np.roll(idx, (dy, dx), (0, 1)) == idx
    idx = np.where(same, idx, maj)
    out = cols[idx]
    out[dark_lines(lab, solid, 8, 18)] = INK
    # 1px ink outline; the bottom edge is where the frame cuts the figure, so no line there
    padded = np.vstack([solid, solid[-1:]])
    sil = solid & ~ndimage.binary_erosion(padded)[:-1]
    out[sil] = INK
    return out, solid.astype(np.float32)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    out_dir = Path(sys.argv[1])
    pal = palette()
    for pid in sys.argv[2:]:
        rgb, a = load(pid)
        save(*grade(rgb, a, pal), out_dir / "grade" / f"{pid}.png")
        save(*ink(rgb, a, pal), out_dir / "ink" / f"{pid}.png")
        save(*pixelate(rgb, a, pal, 336, 32), out_dir / "pix336" / f"{pid}.png")
        save(*pixelate(rgb, a, pal, 168, 24), out_dir / "pix168" / f"{pid}.png")
        print("done", pid)


if __name__ == "__main__":
    main()
