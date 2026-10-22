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

# A scratch's raking loop, in stored pictures (about 8 a second of film).
LOOP_LEAST, LOOP_MOST = 5, 12


def main():
    root = sys.argv[1]
    path = os.path.join(root, 'films', 'films.json')
    index = json.load(open(path))
    for key, film in index['films'].items():
        if film.get('kind') == 'clip':
            if film.get('loop'):
                # A scratch's raking loop, found again over the stored pictures at a steadier length: the likest pair
                # of pictures in the second half of the clip at least LOOP_LEAST apart (a three-picture loop raked
                # in a flicker), at most LOOP_MOST.
                thumbs = []
                for rel in film['frames']:
                    rgb = np.asarray(Image.open(os.path.join(root, 'base', rel + '.jpg')).convert('L').resize((120, 90))).astype(np.float32)
                    alpha = np.asarray(Image.open(os.path.join(root, 'alpha', rel)).convert('L').resize((120, 90))).astype(np.float32) / 255
                    thumbs.append(rgb * alpha)
                n = len(thumbs)
                best = None
                for a in range(n // 2, n - LOOP_LEAST):
                    for b in range(a + LOOP_LEAST, min(n, a + LOOP_MOST + 1)):
                        score = float(np.abs(thumbs[a] - thumbs[b]).mean()) + 0.15 * (b - a)
                        if best is None or score < best[0]:
                            best = (score, a, b)
                if best:
                    film['loop'] = [best[1], best[2]]
                    print(f"{key}: loop {best[1]}->{best[2]} of {n}, likeness {best[0]:.2f}")
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
