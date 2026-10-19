#!/usr/bin/env python3
"""Adds the long-haired slim body's single side legs (tools/asset-pipeline/legs/single_legs.py) to
App/Art/cat/custom the way build_cat_art.py builds every sprite, merging them into index.json, without rebuilding the
rest. build_cat_art.py also picks them up when they are listed in its sprites().

    uv run --with numpy --with pillow --with scipy python tools/app-assets/build_single_legs.py
"""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_cat_art as cat  # noqa: E402
from build_profile_ears import build  # noqa: E402


def main():
    path = os.path.join(cat.OUT, 'index.json')
    index = json.load(open(path))
    base = os.path.join(cat.CUSTOM, 'base')
    for found in sorted(glob.glob(os.path.join(base, 'parts', '*_leg_*_single.png'))):
        rel = os.path.relpath(found, base)
        index['files'][rel] = build(rel)
        print(rel, index['files'][rel]['masks'])
    with open(path, 'w') as f:
        json.dump(index, f, indent=1, sort_keys=True)
        f.write('\n')


if __name__ == '__main__':
    main()
