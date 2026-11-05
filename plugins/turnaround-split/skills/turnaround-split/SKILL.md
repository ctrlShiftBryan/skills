---
name: turnaround-split
description: Split a character turnaround sheet (rows of front / side / back views, e.g. a 6-view sheet of armored + base body) into separate front, left, right and back images, mirroring the side view to make the missing side. Use when asked to cut up, split or crop a turnaround / character sheet into individual views.
---

# Turnaround split

A **turnaround sheet** holds one or more rows of three views, left to right: front, side, back. The usual one is a **6-sheet**: two rows (e.g. armored character over its base-body doll). Each row becomes four images: front, left, right, back. The missing side is the side view **mirrored** (flipped left-to-right; users may call this flipping "across the horizontal axis" and mean the same thing).

[`split_turnaround.py`](split_turnaround.py) does the cutting: it finds each figure as a large blob against the flat background, paints out sheet text (titles, captions, FRONT/LEFT/BACK labels), centres every figure on a uniform canvas per row, and edge-extends the background where the canvas outruns the figure's cell.

## Steps

1. **Read the sheet** with the Read tool. Settle three things:
   - **Row names**, top to bottom, from the sheet's own labels (`armored,doll`) or the user's words; omit for `row1,row2`.
   - **Which side the side view shows.** Figure faces image-left → its **left** side is showing → `--side left`. Faces image-right → `--side right`. Sheets disagree here, and their LEFT label is not proof; judge by the facing. Same facing in every row is assumed; if rows differ, run once per row's facing and keep the right files.
   - It really is rows of three. A sheet of anything else (texture atlas, weapon sheet) is out of scope; say so.

2. **Run** (Python with `-I`, since the sheet is a download):

   ```
   python3 -I ~/.claude/skills/turnaround-split/split_turnaround.py SHEET \
     --rows armored,doll --side left --preview <scratchpad>/preview.png
   ```

   Output defaults to `<sheet name> Views/` beside the sheet, files named `<row>_<view>.png`. `--out DIR` overrides; `--pad PX` sets the margin (default 20).
   An `expected 3 figures per row` exit prints the blob boxes it found: the sheet's background is busy or figures touch. Crop by hand from those boxes (PIL crop + `ImageOps.mirror`) rather than tuning the script blind.

3. **Read the preview.** Done when every image holds one whole figure (nothing clipped), no sheet text or neighbour fragments remain, no black or flat-coloured patches show, and the mirrored view matches its source.

4. **Report** the output folder and files, with sizes per row, and the mirror caveat: one-sided details (emblems, buckles, a blaze, hair parting) swap sides in the mirrored view.
