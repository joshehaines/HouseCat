"""Build a 2:1 isometric corner room from flat tile assets, the way the app will.

Inputs (same folder): wall_cream.png, wall_mint.png, floor_honey.png (seamless-ish tiles),
skirting.png (RGBA strip), window.png, door.png (RGBA, openings in pure cyan to key out),
furn_sofa_iso.png, cat_iso.png (RGBA with soft halo to threshold).
Output: room_built.png
"""
from PIL import Image, ImageOps, ImageFilter
import numpy as np

CELL = 72          # half-width of a floor cell on screen (2:1 iso): cell diamond is 2*CELL wide, CELL tall
N = 10             # cells per wall
WALL_H = 5         # wall height in cells
UNIT = int(CELL * 1.0)  # vertical pixels per cell of height
R = (CELL, CELL // 2)   # one cell along the right wall
L = (-CELL, CELL // 2)  # one cell along the left wall
W, H = 2400, 1800
B = (W // 2, 520)       # back corner on the floor


def clean_alpha(im, thr=200):
    a = np.array(im.convert('RGBA'))
    a[:, :, 3] = np.where(a[:, :, 3] < thr, 0, 255).astype(np.uint8)
    im = Image.fromarray(a)
    return im.crop(im.getbbox())


def key_cyan(im, tol=70):
    """Make pure-cyan pixels transparent (window glass, door opening)."""
    a = np.array(im.convert('RGBA')).astype(int)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mask = (r < tol) & (g > 255 - tol - 40) & (b > 255 - tol - 40)
    a[:, :, 3] = np.where(mask, 0, a[:, :, 3])
    return Image.fromarray(a.astype(np.uint8))


def tile(im, nx, ny, size):
    """Tile a square texture nx by ny, each tile `size` px."""
    t = im.convert('RGBA').resize((size, size), Image.LANCZOS)
    out = Image.new('RGBA', (size * nx, size * ny))
    for i in range(nx):
        for j in range(ny):
            out.paste(t, (i * size, j * size))
    return out


def affine_place(canvas, src, origin, u_vec, v_vec):
    """Draw src so that its (0,0) lands on origin, its x axis follows u_vec per pixel-fraction
    and its y axis follows v_vec. u_vec/v_vec are the screen vectors for the FULL width/height of src."""
    sw, sh = src.size
    # forward: screen = origin + (x/sw)*u + (y/sh)*v
    a11, a12 = u_vec[0] / sw, v_vec[0] / sh
    a21, a22 = u_vec[1] / sw, v_vec[1] / sh
    det = a11 * a22 - a12 * a21
    i11, i12, i21, i22 = a22 / det, -a12 / det, -a21 / det, a11 / det
    ox, oy = origin
    # PIL inverse map: src_x = i11*(X-ox) + i12*(Y-oy) ...
    c = -(i11 * ox + i12 * oy)
    f = -(i21 * ox + i22 * oy)
    warped = src.transform(canvas.size, Image.AFFINE, (i11, i12, c, i21, i22, f), resample=Image.BICUBIC)
    canvas.alpha_composite(warped)



def lit(plane_img, lm_path):
    """Multiply a flat tiled plane by a light map (H,W,3 floats around 1.0)."""
    lm = np.load(lm_path)
    lm_img = Image.fromarray((np.clip(lm/2.0,0,1)*255).astype(np.uint8)).resize(plane_img.size, Image.BICUBIC)
    lm_arr = np.asarray(lm_img).astype(float)/255.0*2.0
    a = np.asarray(plane_img.convert('RGBA')).astype(float)
    a[:,:,:3] = np.clip(a[:,:,:3] * lm_arr, 0, 255)
    return Image.fromarray(a.astype(np.uint8))

def build():
    wall_c = Image.open('wall_cream.png').convert('RGB')
    # WARM_WALL: nudge the cream wallpaper warmer so it reads cream, not grey, under the light map
    arr = np.asarray(wall_c).astype(float); arr[:,:,0] *= 1.04; arr[:,:,2] *= 0.94
    wall_c = Image.fromarray(np.clip(arr,0,255).astype(np.uint8))
    wall_m = Image.open('wall_mint.png')
    floor = Image.open('floor_honey.png')
    skirt = clean_alpha(Image.open('skirting.png'), 128)
    window = key_cyan(clean_alpha(Image.open('window.png'), 128))
    door = key_cyan(clean_alpha(Image.open('door.png'), 128))
    sofa = Image.open('furn_living_sofa_R.png').convert('RGBA')
    cat = clean_alpha(Image.open('cat_iso.png'))

    canvas = Image.new('RGBA', (W, H), (255, 255, 255, 255))
    tex = 256
    wall_top = (B[0], B[1] - WALL_H * UNIT)

    # right wall: from the back corner along +R, height up
    rw = lit(tile(wall_c, N//2, (WALL_H+1)//2, tex*2).crop((0,0,N*tex,WALL_H*tex)), 'lm_right.npy')
    affine_place(canvas, rw, wall_top, (R[0] * N, R[1] * N), (0, WALL_H * UNIT))
    # left wall: from the back corner along +L
    lw = lit(tile(wall_c, N//2, (WALL_H+1)//2, tex*2).crop((0,0,N*tex,WALL_H*tex)), 'lm_left.npy')
    affine_place(canvas, lw, wall_top, (L[0] * N, L[1] * N), (0, WALL_H * UNIT))
    # floor: diamond, u along R, v along L
    fl = lit(tile(floor, N//2, N//2, tex*2), 'lm_floor.npy')
    affine_place(canvas, fl, B, (R[0] * N, R[1] * N), (L[0] * N, L[1] * N))

    # skirting on both walls (strip height ~0.35 cell)
    sk_h = int(UNIT * 0.35)
    skr = skirt.resize((int(skirt.size[0]), int(skirt.size[1])))
    affine_place(canvas, skr, (B[0], B[1] - sk_h), (R[0] * N, R[1] * N), (0, sk_h))
    affine_place(canvas, ImageOps.mirror(skr), (B[0], B[1] - sk_h), (L[0] * N, L[1] * N), (0, sk_h))

    # window on the right wall: 2 cells wide, 3 cells tall, starting 5 cells along, sill 1.5 cells up
    win_w, win_h = 2.6, 3.4
    o = (B[0] + R[0] * 5, B[1] + R[1] * 5 - int(UNIT * 1.5) - win_h * UNIT)
    sky = Image.new('RGBA', window.size, (0,0,0,0))
    skyfill = Image.new('RGBA', window.size, (122, 196, 240, 255))
    sky = Image.composite(skyfill, sky, Image.eval(window.split()[3], lambda a: 255 - a))
    affine_place(canvas, sky, o, (R[0] * win_w, R[1] * win_w), (0, win_h * UNIT))
    affine_place(canvas, window, o, (R[0] * win_w, R[1] * win_w), (0, win_h * UNIT))

    # door on the left wall: 1.6 cells wide, 3.6 cells tall, 2 cells along; show the next room through it
    d_w, d_h = 1.6, 3.6
    o = (B[0] + L[0] * 2, B[1] + L[1] * 2 - int(d_h * UNIT))
    # next-room glimpse: mint wall + a floor strip, clipped to the door's rect
    glimpse = Image.new('RGBA', door.size, (0, 0, 0, 0))
    gw, gh = door.size
    mint = tile(wall_m, 2, 3, tex).resize((gw, int(gh * 0.82)), Image.LANCZOS)
    glimpse.paste(mint, (0, 0))
    fstrip = tile(floor, 2, 1, tex).resize((gw, gh - int(gh * 0.82)), Image.LANCZOS)
    glimpse.paste(fstrip, (0, int(gh * 0.82)))
    glimpse = Image.composite(glimpse, Image.new('RGBA', door.size, (0, 0, 0, 0)), Image.eval(door.split()[3], lambda a: 255 - a))
    # darken the glimpse a touch so it reads as further away
    glimpse = Image.blend(glimpse, Image.new('RGBA', door.size, (60, 50, 90, 255)), 0.25)
    glimpse.putalpha(Image.eval(door.split()[3], lambda a: 255 - a))
    affine_place(canvas, glimpse, o, (L[0] * d_w, L[1] * d_w), (0, d_h * UNIT))
    affine_place(canvas, ImageOps.mirror(door), o, (L[0] * d_w, L[1] * d_w), (0, d_h * UNIT))

    # sofa against the right wall: footprint 3 cells along R (cells 1..4), 1 cell deep.
    # Leftmost pixel = front-left leg at B + R*1 + L*1; lowest pixel = front-right leg at B + R*4 + L*1.
    along, deep, start = 3, 1, 1
    x_left = B[0] + R[0] * start + L[0] * deep
    x_right = B[0] + R[0] * (start + along)          # back-right top corner is the rightmost point
    y_bottom = B[1] + R[1] * (start + along) + L[1] * deep
    sw = int((x_right - x_left) * 1.04)
    s = sofa.resize((sw, int(sofa.size[1] * sw / sofa.size[0])), Image.LANCZOS)
    from PIL import ImageDraw
    shadow = Image.new('RGBA', (N*tex, N*tex), (0,0,0,0))
    ds = ImageDraw.Draw(shadow)
    # footprint cells start..start+along along u, 0..deep along v, padded a bit
    ds.rectangle([int(tex*2*start/2*1.0), 0, int(tex*(start+along)), int(tex*deep*1.3)], fill=(40, 30, 70, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    affine_place(canvas, shadow, B, (R[0] * N, R[1] * N), (L[0] * N, L[1] * N))
    canvas.alpha_composite(s, (int(x_left), int(y_bottom - s.size[1])))

    # cat on the floor, about half the sofa height
    ch = int(s.size[1] * 0.55)
    c = cat.resize((int(cat.size[0] * ch / cat.size[1]), ch), Image.LANCZOS)
    p = (B[0] + R[0] * 4 + L[0] * 5, B[1] + R[1] * 4 + L[1] * 5)
    canvas.alpha_composite(c, (int(p[0] - c.size[0] / 2), int(p[1] - c.size[1])))

    canvas.convert('RGB').save('room_built.png')
    print('built', canvas.size)


if __name__ == '__main__':
    build()
