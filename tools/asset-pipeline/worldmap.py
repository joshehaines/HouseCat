"""Build the stylised world map and the coarse biome mask from real coastlines (global-land-mask).
Equirectangular, 4096x2048, longitude -180..180 left to right, latitude 90..-90 top to bottom, so the
app converts a coordinate to a pixel with x = (lon+180)/360*W, y = (90-lat)/180*H.
Outputs: map_landmask.png (white land), map_biome.png (palette index image) + map_biome_legend.json,
map_painted.png (painted sea and land textures with a soft cream coastline)."""
import json
import numpy as np, cv2
from PIL import Image
from global_land_mask import globe

W, H = 4096, 2048
lat = 90 - (np.arange(H) + 0.5) * 180 / H
lon = -180 + (np.arange(W) + 0.5) * 360 / W
LO, LA = np.meshgrid(lon, lat)
land = globe.is_land(LA, LO)
Image.fromarray((land * 255).astype(np.uint8)).save('map_landmask.png')

# ---- biomes (coarse rules; the app adds 'city' when the pin is near a listed city) ----
BIOMES = ['sea', 'coast', 'countryside', 'mountain', 'forest', 'desert', 'tropical', 'snow', 'city']
def box(lat0, lat1, lon0, lon1): return (LA >= lat0) & (LA <= lat1) & (LO >= lon0) & (LO <= lon1)
desert = (box(15, 33, -17, 35) | box(15, 32, 35, 60) | box(23, 40, 50, 75) | box(37, 47, 85, 112) |
          box(-32, -19, 113, 142) | box(-28, -18, 12, 25) | box(-30, -15, -72, -68) | box(25, 37, -118, -103) |
          box(23, 31, -115, -105))
mountain = (box(27, 37, 70, 97) | box(43, 48, 5, 16) | box(-45, 5, -79, -66) | box(35, 55, -125, -105) |
            box(36, 44, 40, 50) | box(-45, -38, 166, 175) | box(42, 44, -2, 3) | box(60, 70, 5, 15))
tropical = (np.abs(LA) < 20) & ~desert
forest = ((LA > 50) & (LA < 66)) | box(-50, -38, -75, -70) | box(40, 50, -95, -60) | box(-5, 5, 10, 30)
snow = (LA > 66) | (LA < -60) | box(59, 84, -75, -10)          # high latitudes, Antarctica, Greenland
dist = cv2.distanceTransform((land * 255).astype(np.uint8), cv2.DIST_L2, 5)  # px to the sea
coast = land & (dist < 6)                                          # ~50 km at the equator
bio = np.zeros((H, W), np.uint8)                                   # 0 = sea
bio[land] = 2                                                      # countryside by default
bio[land & forest] = 4
bio[land & tropical] = 6
bio[land & desert] = 5
bio[land & mountain] = 3
bio[land & coast & ~snow] = 1
bio[land & snow] = 7
Image.fromarray(bio).save('map_biome.png')
json.dump({str(i): b for i, b in enumerate(BIOMES)} | {"note": "index image; 8=city is assigned by the app near listed cities"},
          open('map_biome_legend.json', 'w'), indent=1)

# ---- painted map ----
def tiled(path, size=512):
    t = Image.open(path).convert('RGB').resize((size, size), Image.LANCZOS)
    out = Image.new('RGB', (W, H))
    for x in range(0, W, size):
        for y in range(0, H, size): out.paste(t, (x, y))
    return np.asarray(out).astype(np.float32)
sea = tiled('gen/misc/map_sea.png'); grn = tiled('gen/misc/map_land.png')
# calm the textures: half painted texture, half a flat colour, so the map reads as simple blue and green
sea = sea * 0.45 + np.array([120, 185, 225]) * 0.55
grn = grn * 0.45 + np.array([150, 200, 120]) * 0.55
# soft snow caps only (Josh: "a blue and green world"); biomes stay invisible in the mask
snowy = cv2.GaussianBlur(((bio == 7) & land).astype(np.float32), (0, 0), 25)[..., None]
landrgb = grn * (1 - 0.8 * snowy) + np.array([245, 248, 252]) * 0.8 * snowy
soft = cv2.GaussianBlur(land.astype(np.float32), (0, 0), 1.5)[..., None]
out = sea * (1 - soft) + landrgb * soft
edge = np.clip(1 - np.abs(soft[..., 0] - 0.5) * 2, 0, 1)[..., None]           # thin coastline band
out = out * (1 - 0.6 * edge) + np.array([250, 240, 220]) * 0.6 * edge          # cream outline
Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save('map_painted.png')
print('land fraction', land.mean().round(3), 'biome counts', np.bincount(bio.ravel(), minlength=9))
