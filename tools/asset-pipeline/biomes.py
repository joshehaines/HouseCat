"""The world map's biome mask (assets/world/map/map_biome.png), from the land mask that worldmap.py made from real
coastlines. Rules by latitude and hand-drawn regions (longitude and latitude boxes, degrees); 'city' is not in the
mask: the app makes a pin city near a listed city (cities.json). Rerun after changing a region:
  python3 tools/asset-pipeline/biomes.py            (needs Pillow, numpy, scipy)
The painted map (map_painted.png) is left alone: it shows only sea and land (Josh: "a blue and green world")."""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
MAP = os.path.join(ROOT, 'assets', 'world', 'map')
BIOMES = ['sea', 'coast', 'countryside', 'mountain', 'forest', 'desert', 'tropical', 'snow', 'city']

land = np.asarray(Image.open(os.path.join(MAP, 'map_landmask.png'))) > 127
H, W = land.shape
lat = 90 - (np.arange(H) + 0.5) * 180 / H
lon = -180 + (np.arange(W) + 0.5) * 360 / W
LO, LA = np.meshgrid(lon, lat)


def box(lat0, lat1, lon0, lon1):
    return (LA >= lat0) & (LA <= lat1) & (LO >= lon0) & (LO <= lon1)


def any_of(*boxes):
    out = np.zeros_like(land)
    for b in boxes:
        out |= box(*b)
    return out


desert = any_of(
    (15, 32, -17, 33),      # Sahara
    (15, 31, 36, 58),       # Arabia
    (25, 38, 54, 70),       # Iran, Afghanistan, Pakistan's west
    (36, 46, 54, 66),       # Karakum, Kyzylkum
    (37, 47, 75, 112),      # Taklamakan, Gobi
    (-32, -20, 115, 141),   # Australia's interior
    (-28, -20, 12, 22),     # Namib, Kalahari
    (-28, -17, -71, -68),   # Atacama
    (31, 42, -120, -108),   # Great Basin, Mojave, Sonoran
    (24, 31, -112, -104),   # Chihuahua
    (21, 30, 68, 75),       # Thar
)
mountain = any_of(
    (27, 37, 70, 98),       # Himalaya, Karakoram, Tibet
    (45.6, 47.8, 6, 15.5),  # Alps
    (42.2, 43.2, -1.8, 2.8),  # Pyrenees
    (-48, 8, -78, -67),     # Andes
    (37, 50, -116, -105),   # Rockies
    (36, 49, -122.5, -118.8),  # Sierra Nevada, Cascades
    (41, 44, 40, 48),       # Caucasus
    (-45, -40.5, 168, 173), # Southern Alps
    (60, 69, 6, 14),        # Scandinavian mountains
    (56.5, 58.5, -6, -3.5), # Scottish Highlands
    (30, 34, -8, -2),       # Atlas
    (7, 13, 36, 40),        # Ethiopian Highlands
    (35, 37.5, 136.5, 139), # Japanese Alps
    (37, 44, 68, 80),       # Tian Shan, Pamir
    (45, 48, 22, 26),       # Carpathians
)
tropical = (np.abs(LA) < 20) & ~desert
forest = (
    ((LA > 50) & (LA < 66) & ~box(49, 58.6, -11, 28))   # boreal, not Britain and western Europe
    | any_of(
        (42, 50, -125, -120),   # Pacific Northwest
        (40, 48, -84, -66),     # eastern woods, New England
        (-47, -38, -75, -71),   # Valdivian
        (55, 60, 10, 30),       # Scandinavia's south
        (44, 50, 126, 136),     # Manchuria, Russian Far East
        (-44, -36, 145, 149),   # Victoria's and Tasmania's forests
    )
)
snow = (LA > 66) | (LA < -60) | box(59, 84, -75, -10)
dist = ndimage.distance_transform_edt(land)            # pixels to the sea
coast = land & (dist < 5)                              # about 40 km at the equator
bio = np.zeros((H, W), np.uint8)
bio[land] = 2
bio[land & forest] = 4
bio[land & tropical] = 6
bio[land & desert] = 5
bio[land & mountain] = 3
bio[land & coast & ~snow] = 1
bio[land & snow] = 7
Image.fromarray(bio).save(os.path.join(MAP, 'map_biome.png'), optimize=True)
json.dump({str(i): b for i, b in enumerate(BIOMES)} | {"note": "index image; 8=city is assigned by the app near listed cities (cities.json); made by tools/asset-pipeline/biomes.py"},
          open(os.path.join(MAP, 'map_biome_legend.json'), 'w'), indent=1)
print('biome counts', dict(zip(BIOMES, np.bincount(bio.ravel(), minlength=9).tolist())))
