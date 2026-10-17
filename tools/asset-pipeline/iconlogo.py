"""App icon layers + logo cut-outs. python3 iconlogo.py -> brand/..."""
import os, json
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage
from rembg import remove, new_session

os.makedirs('brand/icon', exist_ok=True); os.makedirs('brand/logo', exist_ok=True)
S = 1024

# --- icon: chosen concept + clean plate -> background layer, cat layer, flattened icon, alternates
concept = Image.open('gen/icon/concept_sill_peek.png').convert('RGB').resize((S, S), Image.LANCZOS)
plate = Image.open('gen/icon/plate_sill_peek.png').convert('RGB').resize((S, S), Image.LANCZOS)
concept.save('brand/icon/AppIcon_1024.png')
plate.save('brand/icon/AppIcon_layer1_background.png')
sess = new_session('isnet-general-use')
cut = np.asarray(remove(concept, session=sess)).astype(np.float32)
a = cut[..., 3] / 255
# keep the biggest component (the cat + paws), soften the edge a touch
m = a > 0.5
lab, n = ndimage.label(m)
if n:
    sizes = ndimage.sum(m, lab, range(1, n + 1)); keep = lab == (int(np.argmax(sizes)) + 1)
    keep = ndimage.binary_fill_holes(keep)
    a = np.where(ndimage.binary_dilation(keep, iterations=2), a, 0)
rgb = np.asarray(concept).astype(np.float32)
Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8)).save('brand/icon/AppIcon_layer2_cat.png')
# check: layers recomposed vs the original
bg = plate.convert('RGBA'); bg.alpha_composite(Image.open('brand/icon/AppIcon_layer2_cat.png'))
diff = np.abs(np.asarray(bg.convert('RGB')).astype(int) - np.asarray(concept).astype(int)).mean()
print('icon recomposite mean diff', round(float(diff), 2), 'cat coverage', round(float((a > 0.5).mean()), 3))
for k in ['house_window', 'round_window', 'roof_curl']:
    Image.open(f'gen/icon/concept_{k}.png').convert('RGB').resize((S, S), Image.LANCZOS).save(f'brand/icon/alt_AppIcon_{k}_1024.png')

# --- logos: white background (light) and green background (dark versions)
def key_white(im):
    a = np.asarray(im.convert('RGB')).astype(np.float32)
    mn = a.min(axis=2)
    bgc = mn > 232
    lab, n = ndimage.label(bgc)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bgm = np.isin(lab, list(border))
    edge = ndimage.binary_dilation(bgm, iterations=2) & ~bgm
    alpha = np.where(bgm, 0.0, 1.0)
    alpha = np.where(edge, np.clip((255 - mn) / (255 - 120), 0, 1), alpha)
    col = np.where(alpha[..., None] > 0.02, np.clip((a - (1 - alpha[..., None]) * 255) / np.maximum(alpha[..., None], 1e-3), 0, 255), 0)
    return Image.fromarray(np.dstack([col, alpha * 255]).astype(np.uint8))

def key_green(im):
    a = np.asarray(im.convert('RGB')).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    gness = np.clip((g - np.maximum(r, b) - 40) / 120, 0, 1)
    bgm = gness > 0.5                      # full key: green also shows inside the house outline
    near = ndimage.binary_dilation(bgm, iterations=3)
    alpha = np.where(bgm, 0.0, np.where(near, 1 - gness, 1.0))
    out = a.copy(); out[..., 1] = np.minimum(g, np.maximum(r, b) + 10)      # despill
    return Image.fromarray(np.dstack([out, alpha * 255]).astype(np.uint8))

for k in ['horizontal', 'stacked']:
    im = key_white(Image.open(f'gen/logo/{k}.png')); im = im.crop(im.getbbox()); im.save(f'brand/logo/logo_{k}_on_light.png')
    im = key_green(Image.open(f'gen/logo/{k}_dark.png')); im = im.crop(im.getbbox()); im.save(f'brand/logo/logo_{k}_on_dark.png')
print(sorted(os.listdir('brand/logo')))
