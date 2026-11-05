#!/usr/bin/env python3
"""Split a character turnaround sheet into front/left/right/back images.

Each row of the sheet must hold three views left-to-right: front, side, back.
The side view is saved as `left` and mirrored to make `right` (or the reverse
with --side right). Sheet text is detected as small blobs and painted out.

usage: split_turnaround.py SHEET [--out DIR] [--rows NAMES] [--side left|right]
                                 [--pad PX] [--preview PNG]
"""
import argparse
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageOps

SCALE = 4          # mask downscale factor for blob labelling
THRESH = 60        # summed RGB distance from background that counts as content
MIN_FIG_H = 0.15   # a blob taller than this fraction of the sheet is a figure


def label(mask):
    """4-connected component labelling; returns (labels, count)."""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    for y0, x0 in zip(*np.nonzero(mask)):
        if lab[y0, x0]:
            continue
        n += 1
        lab[y0, x0] = n
        q = deque([(y0, x0)])
        while q:
            y, x = q.popleft()
            for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n
                    q.append((yy, xx))
    return lab, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("--out", help="output dir (default: '<sheet name> Views' beside the sheet)")
    ap.add_argument("--rows", help="comma-separated row names, top to bottom (default row1,row2,...)")
    ap.add_argument("--side", choices=["left", "right"], default="left",
                    help="which side the sheet's side view shows (default left)")
    ap.add_argument("--pad", type=int, default=20, help="margin around each figure in px")
    ap.add_argument("--preview", help="also write a contact sheet of all outputs here")
    a = ap.parse_args()

    img = np.asarray(Image.open(a.sheet).convert("RGB")).astype(np.int16)
    H, W, _ = img.shape
    border = np.concatenate([img[:8].reshape(-1, 3), img[-8:].reshape(-1, 3),
                             img[:, :8].reshape(-1, 3), img[:, -8:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    fg = np.abs(img - bg).sum(axis=2) > THRESH

    # Downscale (any-pixel), dilate once, label blobs.
    h, w = H // SCALE, W // SCALE
    small = fg[:h * SCALE, :w * SCALE].reshape(h, SCALE, w, SCALE).any(axis=(1, 3))
    d = small.copy()
    d[1:] |= small[:-1]; d[:-1] |= small[1:]; d[:, 1:] |= small[:, :-1]; d[:, :-1] |= small[:, 1:]
    lab, n = label(d)

    blobs = []
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        blobs.append((i, xs.min() * SCALE, ys.min() * SCALE, (xs.max() + 1) * SCALE, (ys.max() + 1) * SCALE))
    figs = [b for b in blobs if b[4] - b[2] > MIN_FIG_H * H]
    other = [b for b in blobs if b not in figs]

    # Group figures into rows by vertical overlap, then sort each row by x.
    figs.sort(key=lambda b: (b[2] + b[4]) / 2)
    rows = []
    for f in figs:
        if rows and f[2] < rows[-1][-1][4] and f[4] > rows[-1][-1][2]:
            rows[-1].append(f)
        else:
            rows.append([f])
    for r in rows:
        r.sort(key=lambda b: b[1])
    shape = [len(r) for r in rows]
    if any(c != 3 for c in shape):
        sys.exit(f"expected 3 figures per row, found rows of {shape}; "
                 f"figure bboxes: {[(b[1], b[2], b[3], b[4]) for b in figs]}")

    names = a.rows.split(",") if a.rows else [f"row{i + 1}" for i in range(len(rows))]
    if len(names) != len(rows):
        sys.exit(f"--rows gave {len(names)} names but the sheet has {len(rows)} rows")

    # Paint out every non-figure blob (titles, labels, captions) with the
    # row-wise background just outside it, so it vanishes from any crop.
    out_img = img.copy()
    big = np.kron(lab, np.ones((SCALE, SCALE), np.int32))
    big = np.pad(big, ((0, H - big.shape[0]), (0, W - big.shape[1])))
    for i, x0, y0, x1, y1 in other:
        m = big[y0:y1, x0:x1] == i
        ref = np.concatenate([img[y0:y1, max(x0 - 6, 0):x0], img[y0:y1, x1:x1 + 6]], axis=1)
        fill = np.median(ref, axis=1) if ref.shape[1] else np.tile(bg, (y1 - y0, 1))
        region = out_img[y0:y1, x0:x1]
        region[m] = np.repeat(fill[:, None, :], x1 - x0, axis=1)[m]
    sheet = out_img.astype(np.uint8)

    out = a.out or os.path.join(os.path.dirname(os.path.abspath(a.sheet)),
                                os.path.splitext(os.path.basename(a.sheet))[0] + " Views")
    os.makedirs(out, exist_ok=True)
    mirrored = "right" if a.side == "left" else "left"
    written = []
    # Each figure owns a cell bounded by midpoints to its neighbours, so no
    # neighbour ever enters its crop; canvas beyond the cell is edge-extended.
    row_mids = [(rows[k][0][4] + rows[k + 1][0][2]) // 2 for k in range(len(rows) - 1)]
    for r, (name, row) in enumerate(zip(names, rows)):
        cy0 = row_mids[r - 1] if r > 0 else 0
        cy1 = row_mids[r] if r < len(rows) - 1 else H
        cw = max(b[3] - b[1] for b in row) + 2 * a.pad
        ch = max(b[4] - b[2] for b in row) + 2 * a.pad
        views = {}
        for k, (view, (i, x0, y0, x1, y1)) in enumerate(zip(["front", a.side, "back"], row)):
            cx0 = (row[k - 1][3] + x0) // 2 if k > 0 else 0
            cx1 = (x1 + row[k + 1][1]) // 2 if k < 2 else W
            bx0 = (x0 + x1) // 2 - cw // 2
            by0 = (y0 + y1) // 2 - ch // 2
            sx0, sy0 = max(bx0, cx0), max(by0, cy0)
            sx1, sy1 = min(bx0 + cw, cx1), min(by0 + ch, cy1)
            part = sheet[sy0:sy1, sx0:sx1]
            part = np.pad(part, ((sy0 - by0, by0 + ch - sy1), (sx0 - bx0, bx0 + cw - sx1), (0, 0)), mode="edge")
            views[view] = Image.fromarray(part)
        views[mirrored] = ImageOps.mirror(views[a.side])
        for view in ["front", "left", "right", "back"]:
            p = os.path.join(out, f"{name}_{view}.png")
            views[view].save(p)
            written.append(p)
        print(f"{name}: {cw}x{ch}")

    print(f"wrote {len(written)} files to {out}")
    if a.preview:
        ims = [Image.open(p) for p in written]
        cols = 4
        tw = max(i.width for i in ims) + 8
        th = max(i.height for i in ims) + 8
        sheet_p = Image.new("RGB", (tw * cols, th * len(rows)), "white")
        for k, im in enumerate(ims):
            sheet_p.paste(im, ((k % cols) * tw + 4, (k // cols) * th + 4))
        sheet_p.save(a.preview)
        print(f"preview: {a.preview}")


if __name__ == "__main__":
    main()
