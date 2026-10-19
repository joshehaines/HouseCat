#!/usr/bin/env python3
"""Builds only the Games menu's art (the `arcade/` sets of build_app_art.py) into App/Art/arcade and its entries in
App/Art/art.json, leaving everything else as it is, so the games' pictures can be rebuilt without the whole art
build. A full run of build_app_art.py makes the same files. Standard library plus macOS `sips` only.

Run from the repo root: python3 -I tools/app-assets/build_arcade_art.py
"""
import glob
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_app_art as app  # noqa: E402


def main():
    index_path = os.path.join(app.OUT, 'art.json')
    with open(index_path) as f:
        art = json.load(f)
    files = {rel: entry for rel, entry in art['files'].items() if not rel.startswith('arcade/')}
    shutil.rmtree(os.path.join(app.OUT, 'arcade'), ignore_errors=True)
    count = 0
    for pattern, factor in (s for s in app.SETS if s[0].startswith('arcade/')):
        found = sorted(glob.glob(os.path.join(app.ASSETS, pattern)))
        assert found, pattern
        for src in found:
            rel = os.path.relpath(src, app.ASSETS)
            w, h = app.size(src)
            entry = {"master": [w, h], "scale": factor}
            dst = os.path.join(app.OUT, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if app.heic(rel):
                file = os.path.splitext(rel)[0] + '.heic'
                quality = app.HEIC_ALPHA_QUALITY if rel.startswith(app.HEIC_ALPHA) and not rel.startswith(app.HEIC) else app.HEIC_QUALITY
                subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', quality,
                                '-z', str(max(1, round(h * factor))), str(max(1, round(w * factor))), src, '--out',
                                os.path.join(app.OUT, file)], capture_output=True, check=True)
                entry["file"] = file
            elif factor < 1.0:
                fmt = 'jpeg' if src.endswith('.jpg') else 'png'
                subprocess.run(['sips', '-s', 'format', fmt, '-z', str(max(1, round(h * factor))), str(max(1, round(w * factor))),
                                src, '--out', dst], capture_output=True, check=True)
            else:
                shutil.copyfile(src, dst)
            files[rel] = entry
            count += 1
    art['files'] = files
    with open(index_path, 'w') as f:
        json.dump(art, f, indent=1, sort_keys=True)
        f.write('\n')
    total = sum(os.path.getsize(os.path.join(dp, n)) for dp, _, ns in os.walk(os.path.join(app.OUT, 'arcade')) for n in ns)
    print(f'{count} games pictures into App/Art/arcade ({total / 1e6:.1f} MB)')


if __name__ == '__main__':
    main()
