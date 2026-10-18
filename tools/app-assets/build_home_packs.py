#!/usr/bin/env python3
"""Builds the download packs for the homes' exteriors (Background Assets, Apple-hosted): one pack a home, every
biome and season, door closed and open, with their masks, laid out like App/Art and carrying its own art.json,
so the game adds it to its art library when it arrives (Shared/Sources/HomePacks.swift). The London terrace ships
inside the app (tools/app-assets/build_app_art.py) and has no pack.

  python3 -I tools/app-assets/build_home_packs.py [home ...]

Writes to ~/Library/Caches/HouseCat/packs (hundreds of MB; never into the repo):
  home_<style>/homes/<style>/...   the pack's files (the pack's paths start homes/<style>/ so packs never collide)
  home_<style>.json                its manifest (asset-pack id home.<style>, on demand, iOS)
  home_<style>.aar                 the archive from `xcrun ba-package`, to upload to App Store Connect
Standard library plus macOS `sips` and `xcrun ba-package`.
"""
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.dirname(__file__))
import build_app_art as art  # noqa: E402

SCENES = os.path.join(ROOT, 'assets', 'world', 'scenes')
OUT = os.path.expanduser('~/Library/Caches/HouseCat/packs')
HOMES = ['mansion_flat', 'cottage', 'georgian_townhouse', 'newbuild_balcony', 'houseboat', 'mediterranean_rooftop', 'woodland_cabin']
SCALE = 0.75   # as the bundled London terrace


def build(home):
    pack = f'home_{home}'
    root = os.path.join(OUT, pack)
    content = os.path.join(root, 'homes', home)
    if os.path.isdir(root):
        shutil.rmtree(root)
    os.makedirs(os.path.join(content, 'world', 'scenes'))
    index = {}
    for name in sorted(os.listdir(SCENES)):
        if not name.startswith(home + '_') or not name.endswith(('.jpg', '.png')):
            continue
        rel = 'world/scenes/' + name
        src = os.path.join(SCENES, name)
        w, h = art.size(src)
        entry = {"master": [w, h], "scale": SCALE}
        dims = [str(max(1, round(h * SCALE))), str(max(1, round(w * SCALE)))]
        if art.heic(rel):
            file = os.path.splitext(rel)[0] + '.heic'
            subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', art.HEIC_QUALITY, '-z', *dims, src,
                            '--out', os.path.join(content, file)], capture_output=True, check=True)
            entry["file"] = file
        else:
            subprocess.run(['sips', '-s', 'format', 'png', '-z', *dims, src, '--out', os.path.join(content, rel)],
                           capture_output=True, check=True)
        index[rel] = entry
    with open(os.path.join(content, 'art.json'), 'w') as f:
        json.dump({"note": f"The {home} exteriors (tools/app-assets/build_home_packs.py).", "files": index}, f, indent=1, sort_keys=True)
    manifest = {
        "assetPackID": f"home.{home}",
        "downloadPolicy": {"onDemand": {}},
        "fileSelectors": [{"directory": "homes"}],
        "platforms": ["iOS"],
        "sourceRoot": pack,
    }
    path = os.path.join(OUT, pack + '.json')
    with open(path, 'w') as f:
        json.dump(manifest, f, indent=1)
    archive = os.path.join(OUT, pack + '.aar')
    subprocess.run(['xcrun', 'ba-package', 'package', path, '-o', archive, '--quiet'], cwd=OUT, check=True)
    total = sum(os.path.getsize(os.path.join(dp, n)) for dp, _, ns in os.walk(root) for n in ns)
    print(f'{pack}: {len(index)} files, {total / 1e6:.0f} MB, {os.path.getsize(archive) / 1e6:.0f} MB archive')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for home in sys.argv[1:] or HOMES:
        build(home)
