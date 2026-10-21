"""Each stride film's standing and stretched pictures (21 Oct): the frame whose outline is most gathered (the cat
standing still holds it in place of the puppet, `CatNode.standFilm`) and most stretched (held through a jump,
`CatNode.leap`), by the alpha's bounding box, written into films/films.json as `stand` and `stretch`. Clips keep theirs.
Run after filmwalk.py, on the frames folder (then build_cat_art.py or install_films.py copies it into the app):

    uv run --with pillow --with numpy python -I tools/asset-pipeline/walk/filmindex.py assets/cat/films/frames
"""
import json
import os
import sys

import numpy as np
from PIL import Image


def main():
    root = sys.argv[1]
    path = os.path.join(root, 'films', 'films.json')
    index = json.load(open(path))
    for key, film in index['films'].items():
        if film.get('kind') == 'clip':
            continue
        areas = []
        for rel in film['frames']:
            alpha = np.asarray(Image.open(os.path.join(root, 'alpha', rel)).convert('L')) > 128
            ys, xs = np.nonzero(alpha)
            areas.append((xs.max() - xs.min() + 1) * (ys.max() - ys.min() + 1) if len(xs) else 0)
        film['stand'] = int(np.argmin(areas))
        film['stretch'] = int(np.argmax(areas))
        print(f"{key}: stand {film['stand']}, stretch {film['stretch']} of {len(areas)}")
    json.dump(index, open(path, 'w'), indent=1, sort_keys=True)


if __name__ == '__main__':
    main()
