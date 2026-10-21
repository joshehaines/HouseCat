#!/bin/bash
# One film through filmwalk.py into assets/cat/films/frames (films.sh does every walk and run):
#   tools/asset-pipeline/walk/film.sh <body> <view> <gait> [breed scale]
# The film is assets/cat/films/<body>_<view>_<gait>.mp4; a walk starts from frame 4 of the puppet's walk, a run from
# frame 5 of its run, a clip (scratch, sit) from the standing cat (frame 000 of `<view>_stand`).
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
body="$1"
view="$2"
gait="$3"
breed="${4:-1.0}"
case "$gait" in
walk) start=004 ;;
run) start=005 ;;
*) start=000 ;;
esac
cd "$ROOT"
uv run --with numpy --with pillow --with scipy --with scikit-image --with opencv-python-headless \
  --with torch --with torchvision --with imageio-ffmpeg python tools/asset-pipeline/walk/filmwalk.py \
  "assets/cat/films/${body}_${view}_${gait}.mp4" "assets/cat/films/start/$body" "$body" "$view" "$gait" "$start" \
  "assets/cat/films/frames" "$breed"
