"""Turn a white 'light only' room painting into three light maps (left wall, right wall, floor), each a
512x512 float RGB array around 1.0 that the app multiplies over the tiled wallpaper and floor.
Geometry is the 10x10 reference room (ref_room_grey.png, 1640x1200): back floor corner B=(820,420),
one cell = (72,36) along the right wall and (-72,36) along the left wall, walls 5 cells (360 px) high.
Map layout matches build_room.py: x=0 at the back corner running outward along the wall (or along the
right wall for the floor), y=0 at the top of the wall (or along the left wall for the floor).
python3 lightmap.py <painting.png> <outprefix>"""
import sys
import numpy as np, cv2
from PIL import Image
sys.path.insert(0, '.')
from extract import align_ref, REF_GREY

B = np.array([820.0, 420.0]); R = np.array([72.0, 36.0]); L = np.array([-72.0, 36.0]); N = 10; WH = 360.0
NORM = 215.0   # painted white of about 215 maps to 1.0
S = 512

def sample(img, pts):
    mx = pts[..., 0].astype(np.float32); my = pts[..., 1].astype(np.float32)
    return cv2.remap(img, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)

def planes(gen):
    _, t = align_ref(gen, REF_GREY, with_transform=True)
    sx, sy, dx, dy = t
    def to_gen(p): return np.stack([p[..., 0] * sx + dx, p[..., 1] * sy + dy], axis=-1)
    u = (np.arange(S) + 0.5) / S
    U, V = np.meshgrid(u, u)                      # U along x, V along y
    top = B + np.array([0.0, -WH])
    left = top + U[..., None] * (L * N) + V[..., None] * np.array([0.0, WH])
    right = top + U[..., None] * (R * N) + V[..., None] * np.array([0.0, WH])
    floor = B + U[..., None] * (R * N) + V[..., None] * (L * N)
    a = np.asarray(gen.convert('RGB')).astype(np.float32)
    # inset a touch so the seams and the outer silhouette edge do not bleed in
    return {k: sample(a, to_gen(v)) for k, v in (('left', left), ('right', right), ('floor', floor))}

if __name__ == '__main__':
    gen = Image.open(sys.argv[1]); pre = sys.argv[2]
    for k, arr in planes(gen).items():
        arr = cv2.GaussianBlur(arr, (0, 0), 3)
        lm = arr / NORM
        np.save(f'{pre}_{k}.npy', lm.astype(np.float32))
        Image.fromarray(np.clip(lm / 1.5 * 255, 0, 255).astype(np.uint8)).save(f'{pre}_{k}.png')
        print(k, lm.shape, lm.mean().round(3), lm.min().round(3), lm.max().round(3))
