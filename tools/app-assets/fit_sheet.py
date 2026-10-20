"""Contact sheets of the cat's fit (the ears, every outfit in every pose): the rows HouseCatGame's renderTheFitSheets
wrote (one PNG a look, a cell a state, names in columns.txt), cut into cells and laid out with labels.

    uv run --with pillow python tools/app-assets/fit_sheet.py <folder> <out.png> [--rows a,b] [--cols 0,1] [--cell 260]
        [--scale 1.0] [--crop 0.0,0.8] [--title T]

--rows picks and orders rows by name (default all, sorted), --cols cells by index, --crop keeps a band of each cell
(top,bottom fractions), --cell is the render's cell width (HOUSECAT_FIT_CELL)."""
import sys, os, argparse
from PIL import Image, ImageDraw, ImageFont
ap = argparse.ArgumentParser()
ap.add_argument("folder"); ap.add_argument("out")
ap.add_argument("--rows"); ap.add_argument("--cols"); ap.add_argument("--cell", type=int, default=260)
ap.add_argument("--scale", type=float, default=1.0); ap.add_argument("--title", default="")
ap.add_argument("--crop", default=None, help="top,bottom fraction of the cell to keep")
a = ap.parse_args()
cols = open(os.path.join(a.folder, "columns.txt")).read().split("\n")
rows = a.rows.split(",") if a.rows else sorted(f[:-4] for f in os.listdir(a.folder) if f.endswith(".png"))
pick = [int(c) for c in a.cols.split(",")] if a.cols else list(range(len(cols)))
try:
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 18)
    big = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 28)
except Exception:
    font = big = ImageFont.load_default()
first = Image.open(os.path.join(a.folder, rows[0] + ".png"))
cw, ch = a.cell, first.height
top, bottom = 0, ch
if a.crop:
    t, b = (float(x) for x in a.crop.split(","))
    top, bottom = int(ch * t), int(ch * b)
cw2, ch2 = int(cw * a.scale), int((bottom - top) * a.scale)
label = 200
head = 40 + (40 if a.title else 0)
W = label + cw2 * len(pick)
H = head + ch2 * len(rows)
S = Image.new("RGB", (W, H), (250, 248, 240))
d = ImageDraw.Draw(S)
if a.title:
    d.text((10, 8), a.title, fill=(40, 20, 40), font=big)
for j, c in enumerate(pick):
    d.text((label + j * cw2 + 6, head - 28), cols[c], fill=(60, 0, 0), font=font)
for i, r in enumerate(rows):
    p = os.path.join(a.folder, r + ".png")
    if not os.path.exists(p):
        continue
    im = Image.open(p).convert("RGB")
    y = head + i * ch2
    d.text((6, y + ch2 // 2 - 10), r.replace("__", " "), fill=(0, 0, 0), font=font)
    for j, c in enumerate(pick):
        tile = im.crop((c * cw, top, (c + 1) * cw, bottom))
        if a.scale != 1:
            tile = tile.resize((cw2, ch2), Image.LANCZOS)
        S.paste(tile, (label + j * cw2, y))
    d.line((0, y, W, y), fill=(255, 255, 255))
S.save(a.out)
print(a.out, S.size)
