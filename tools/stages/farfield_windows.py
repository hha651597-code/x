import numpy as np
from PIL import Image

TINTS = np.array([
    [1.00, 0.70, 0.34],
    [1.00, 0.86, 0.58],
    [0.78, 0.92, 1.00],
    [0.45, 0.85, 0.95],
    [1.00, 0.58, 0.46],
])
TINT_WEIGHTS = np.array([0.34, 0.28, 0.2, 0.13, 0.05])
LUMA = np.array([0.299, 0.587, 0.114])


def cells_of(grids):
    return [(xa, ya, xb, yb) for g in grids for (ya, yb) in g["ys"] for (xa, xb) in g["xs"]]


def build(atlas, cfg, seed):
    rgb = np.asarray(atlas.convert("RGB"), dtype=np.float64)
    r = np.random.default_rng(seed)
    cells = cells_of(cfg["grids"])
    bx0, by0 = min(c[0] for c in cells), min(c[1] for c in cells)
    bx1, by1 = max(c[2] for c in cells), max(c[3] for c in cells)
    out = np.zeros((by1 - by0, bx1 - bx0, 4), dtype=np.float64)
    for (xa, ya, xb, yb) in cells:
        cell = rgb[ya:yb, xa:xb] @ LUMA
        norm = (cell - cell.min()) / max(cell.max() - cell.min(), 1.0)
        tint = TINTS[r.choice(len(TINTS), p=TINT_WEIGHTS)] * (0.75 + 0.5 * r.random())
        lit = tint[None, None, :] * (0.55 + 0.75 * norm)[:, :, None]
        out[ya - by0:yb - by0, xa - bx0:xb - bx0, :3] = lit
        out[ya - by0:yb - by0, xa - bx0:xb - bx0, 3] = 0.04 + 0.96 * r.random()
    img = Image.fromarray((np.clip(out, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGBA")
    w, h = atlas.size
    return img, [bx0 / w, by0 / h, (bx1 - bx0) / w, (by1 - by0) / h], len(cells)


def card_sheet(atlas, cfg, seed, cols, rows, cw=64, ch=48):
    rgb = np.asarray(atlas.convert("RGB"), dtype=np.float64)
    r = np.random.default_rng(seed)
    cells = cells_of(cfg["grids"])
    pick_ids = r.permutation(len(cells))[:cols * rows]
    sheet = np.zeros((rows * ch, cols * cw, 4), dtype=np.float64)
    for k, ci in enumerate(pick_ids):
        xa, ya, xb, yb = cells[int(ci)]
        cell = Image.fromarray(rgb[ya:yb, xa:xb].astype(np.uint8)).resize((cw - 4, ch - 4), Image.LANCZOS)
        lum = (np.asarray(cell, dtype=np.float64) @ LUMA) / 255.0
        norm = (lum - lum.min()) / max(lum.max() - lum.min(), 1e-3)
        tint = TINTS[r.choice(len(TINTS), p=TINT_WEIGHTS)] * (0.8 + 0.4 * r.random())
        lit = tint[None, None, :] * (0.5 + 0.8 * norm)[:, :, None]
        x0, y0 = (k % cols) * cw + 2, (k // cols) * ch + 2
        sheet[y0:y0 + ch - 4, x0:x0 + cw - 4, :3] = lit
        sheet[y0:y0 + ch - 4, x0:x0 + cw - 4, 3] = 1.0
    return Image.fromarray((np.clip(sheet, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGBA")
