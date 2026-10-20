#!/usr/bin/env python3
"""Bundles named masters into App/Art exactly as build_app_art.py does (the same scale for their set, HEIC for cut-outs
and surfaces, the iPad's sharper copy of furniture, the reference room from the manifest) and adds them to art.json,
leaving every other file and entry as it is. For new art while other work in App/Art is in flight; a full
build_app_art.py run makes the same files.

Run from the repo root: python3 -I tools/app-assets/add_app_art.py <master path under assets/ or a glob>...
"""
import fnmatch
import glob
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_app_art as b  # noqa: E402


def factor(rel):
    for pattern, scale in b.SETS:
        if fnmatch.fnmatch(rel, pattern):
            return scale
    if rel.startswith('furniture/'):
        return 0.6  # catalogue_sets()
    raise SystemExit(f'{rel}: not in any of build_app_art.py\'s sets')


def main(patterns):
    manifest = json.load(open(os.path.join(b.ASSETS, 'manifest.json')))['files']
    art_path = os.path.join(b.OUT, 'art.json')
    art = json.load(open(art_path))
    index = art['files']
    added = 0
    for pattern in patterns:
        for src in sorted(glob.glob(os.path.join(b.ASSETS, pattern))):
            rel = os.path.relpath(src, b.ASSETS)
            scale = factor(rel)
            w, h = b.size(src)
            entry = {"master": [w, h], "scale": scale}
            dst = os.path.join(b.OUT, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if b.heic(rel):
                file = os.path.splitext(rel)[0] + '.heic'
                quality = b.HEIC_ALPHA_QUALITY if rel.startswith(b.HEIC_ALPHA) else b.HEIC_QUALITY
                subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', quality,
                                '-z', str(max(1, round(h * scale))), str(max(1, round(w * scale))), src,
                                '--out', os.path.join(b.OUT, file)], capture_output=True, check=True)
                entry["file"] = file
                pad = b.pad_scale(rel, scale)
                if pad:
                    entry["pad"] = {"asset": b.write_pad(src, rel, w, h, pad, quality), "scale": pad}
            else:
                subprocess.run(['sips', '-s', 'format', 'png', '-z', str(max(1, round(h * scale))),
                                str(max(1, round(w * scale))), src, '--out', dst], capture_output=True, check=True)
            ref = manifest.get(rel, {}).get('ref_room')
            if ref:
                entry["ref"] = ref
            index[rel] = entry
            added += 1
    with open(art_path, 'w') as f:
        json.dump({"note": art['note'], "files": index}, f, indent=1, sort_keys=True)
        f.write('\n')
    print(f'{added} images added to App/Art')


if __name__ == '__main__':
    main(sys.argv[1:])
