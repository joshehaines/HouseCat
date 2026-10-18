"""The cat puppet rig for every body (assets/cat/rig.json): the short_slim rig, set by eye with puppet.py,
carried to the other bodies with the overrides below, and each body's assembled and reference sizes measured
from the cat-builder art (cat/custom). Bodies share the cut-out layout, so the fractions carry.

python3 rigfit.py write                           rewrites the rig's sets
python3 rigfit.py check out.jpg body,body,...     each body's standing reference beside its assembled puppet
(needs Pillow, numpy, scipy)"""
import copy, json, math, os, sys
from PIL import Image, ImageDraw
import caps

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RIG_PATH = os.path.join(ROOT, "assets", "cat", "rig.json")
CUSTOM = os.path.join(ROOT, "assets", "cat", "custom", "base")
BODIES = ["short_slim", "short_chunky", "long_slim", "long_chunky", "persian", "siamese", "mainecoon", "sphynx"]
EARS = ["ear_far", "ear_near"]
OVERRIDES = {
    # The breed heads are painted with their own ears on (the swap ears are for the standard bodies only);
    # the separate ear parts would double them. Siamese and sphynx side heads are painted without.
    "persian": {"side": {"omit": EARS}, "tqfront": {"omit": EARS}, "front": {"omit": EARS}},
    "mainecoon": {"side": {"omit": EARS}, "tqfront": {"omit": EARS}, "front": {"omit": EARS}},
    "siamese": {"tqfront": {"omit": EARS}, "front": {"omit": EARS},
                "side": {"tail_up": {"at": [0.975, 0.79], "pivot": [0.06, 0.92]}}},
    "sphynx": {"side": {"tail_up": {"at": [0.975, 0.75], "pivot": [0.05, 0.91]}}},
}


def part(body, view, name, view_rig=None):
    img = Image.open(f"{CUSTOM}/parts/cat_{body}_{view}_{name}.png").convert("RGBA")
    return caps.clean(img, view_rig, name) if view_rig else img


def whole(body, view):
    p = f"{CUSTOM}/whole/cat_{body}_{view}_whole.png"
    if not os.path.exists(p):
        p = os.path.join(ROOT, "assets", "cat", "base", body, f"cat_{body}_{view}_whole.png")
    return Image.open(p).convert("RGBA")


def assemble(body, view, view_rig, clean=True):
    """The rest pose, cropped to the cat."""
    parts = view_rig["parts"]
    imgs = {n: part(body, view, n, view_rig if clean else None) for n in parts}
    world = {}

    def place(n):
        if n in world:
            return world[n]
        p = parts[n]
        ang = p.get("angle", 0)
        x = y = 0.0
        if p.get("parent"):
            px, py, pang = place(p["parent"])
            par, pim = parts[p["parent"]], imgs[p["parent"]]
            jx = (p["at"][0] - par["pivot"][0]) * pim.width
            jy = (p["at"][1] - par["pivot"][1]) * pim.height
            r = math.radians(pang)
            x, y = px + jx * math.cos(r) - jy * math.sin(r), py + jx * math.sin(r) + jy * math.cos(r)
            ang += pang
        world[n] = (x, y, ang)
        return world[n]

    for n in parts:
        place(n)
    canvas = Image.new("RGBA", (3600, 3600), (0, 0, 0, 0))
    for n in sorted(parts, key=lambda n: parts[n]["z"]):
        img, (px, py, ang), pv = imgs[n], world[n], parts[n]["pivot"]
        side = int(2 * math.hypot(img.width, img.height)) + 4
        holder = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        holder.alpha_composite(img, (int(round(side // 2 - pv[0] * img.width)), int(round(side // 2 - pv[1] * img.height))))
        rot = holder.rotate(-ang, resample=Image.BICUBIC, center=(side // 2, side // 2))
        canvas.alpha_composite(rot, (int(round(1800 + px - side // 2)), int(round(1800 + py - side // 2))))
    return canvas.crop(canvas.getbbox())


def rig_for(body, base):
    out = {}
    for view, spec in base.items():
        s = copy.deepcopy(spec)
        o = OVERRIDES.get(body, {}).get(view, {})
        for n in o.get("omit", []):
            s["parts"].pop(n, None)
        for n, change in o.items():
            if n != "omit":
                s["parts"][n].update(change)
        a, w = assemble(body, view, s, clean=False), whole(body, view)
        s["assembled"], s["whole"] = [a.width, a.height], [w.width, w.height]
        out[view] = s
    return out


def on_mid(im):
    bg = Image.new("RGBA", im.size, (150, 140, 160, 255))   # white paintings on a mid background
    bg.alpha_composite(im)
    return bg


if __name__ == "__main__":
    rig = json.load(open(RIG_PATH))
    base = rig["sets"]["short_slim"]
    if sys.argv[1] == "write":
        rig["sets"] = {b: rig_for(b, base) for b in BODIES}
        json.dump(rig, open(RIG_PATH, "w"), indent=1)
        print("wrote", RIG_PATH)
    else:
        bodies, h, rows = sys.argv[3].split(","), 300, []
        for b in bodies:
            row = []
            for v in ["side", "tqfront", "front"]:
                for t in (whole(b, v), assemble(b, v, rig["sets"][b][v])):
                    t = on_mid(t)
                    row.append(t.resize((max(1, round(t.width * h / t.height)), h)))
            rows.append(row)
        sheet = Image.new("RGB", (max(sum(t.width + 12 for t in r) for r in rows), len(rows) * (h + 18)), (238, 234, 226))
        d = ImageDraw.Draw(sheet)
        for i, row in enumerate(rows):
            x = 0
            for t in row:
                sheet.paste(t.convert("RGB"), (x, i * (h + 18) + 16))
                x += t.width + 12
            d.text((4, i * (h + 18) + 2), bodies[i], fill=(0, 0, 0))
        sheet.save(sys.argv[2], quality=82)
