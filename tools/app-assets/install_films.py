"""Copies the cat's film frames (assets/cat/films/frames, made by tools/asset-pipeline/walk/filmwalk.py and indexed by
filmindex.py) into App/Art/cat/custom, as the last step of build_cat_art.py does, without rebuilding every sprite:

    python3 -I tools/app-assets/install_films.py
"""
import os
import shutil

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
FRAMES = os.path.join(ROOT, 'assets', 'cat', 'films', 'frames')
OUT = os.path.join(ROOT, 'App', 'Art', 'cat', 'custom')


def main():
    shutil.copytree(FRAMES, OUT, dirs_exist_ok=True)
    films = sum(os.path.getsize(os.path.join(dp, n)) for dp, _, ns in os.walk(OUT) for n in ns if '/films' in dp or dp.endswith('films'))
    print(f'films into App/Art/cat/custom: {films / 1e6:.1f} MB')


if __name__ == '__main__':
    main()
