#!/usr/bin/env python3
"""Packs the cat's masks inside a built app: each masks/<kind>/ folder (some 2,800 small PNGs) becomes one
masks/<kind>.pack holding the same PNG bytes, untouched, with an index (Josh, 26 Oct: the app was 600 MB, and some
100 MB of it was the space 40,000 small files take on a phone, not the pictures). CatArt reads a pack when there is
one and the loose files when there is not, so App/Art itself, the tools and the tests keep the loose files.

A pack: b"HCMP", the index's length (uint32, little-endian), the index as UTF-8 JSON
({"<path below the kind>": [offset, length]}, offsets from the end of the index), then the PNGs back to back.

Run by the HouseCat target's last build phase (project.yml) with the bundle's masks folder:
python3 -I tools/app-assets/pack_cat_masks.py "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Art/cat/custom/masks"
"""
import json
import os
import shutil
import struct
import sys


def pack(folder, out):
    index, blobs, offset = {}, [], 0
    for dirpath, _, names in os.walk(folder):
        for name in sorted(names):
            if not name.endswith('.png'):
                continue
            path = os.path.join(dirpath, name)
            with open(path, 'rb') as f:
                data = f.read()
            index[os.path.relpath(path, folder)] = [offset, len(data)]
            blobs.append(data)
            offset += len(data)
    head = json.dumps(index, separators=(',', ':'), sort_keys=True).encode('utf-8')
    with open(out, 'wb') as f:
        f.write(b'HCMP')
        f.write(struct.pack('<I', len(head)))
        f.write(head)
        for data in blobs:
            f.write(data)
    return len(index), offset


def main(masks):
    if not os.path.isdir(masks):
        print(f'pack_cat_masks: no {masks}, nothing to pack')
        return
    total_files = total_bytes = 0
    for kind in sorted(os.listdir(masks)):
        folder = os.path.join(masks, kind)
        if not os.path.isdir(folder):
            continue
        files, size = pack(folder, os.path.join(masks, kind + '.pack'))
        shutil.rmtree(folder)
        total_files += files
        total_bytes += size
    print(f'pack_cat_masks: {total_files} masks into packs ({total_bytes / 1e6:.1f} MB)')


if __name__ == '__main__':
    main(sys.argv[1])
