#!/bin/zsh
# Renders the animated logo's films (Midnight bounding onto the wordmark and curling up asleep): the launch's, light and
# dark, and the intro's, from HouseCatGame's LogoScene into App/Resources/LaunchFilm (HEVC with transparency;
# App/Sources/Intro/LaunchFilm.swift plays them). The landing and curling up are the generated curl film
# (assets/brand/logo/logo_curl_film.mp4, Higgsfield Kling, keyed off green by tools/asset-pipeline/logo/curlkey.py).
# Run after changing the cat's art, Tuning.Logo, the wordmark or the curl film. Needs a Mac with Metal (the scene is
# rendered offscreen by the test renderTheLogoFilms) and uv.
# Run from anywhere: tools/app-assets/build_logo_film.sh
set -euo pipefail
root=${0:A:h:h:h}
out=$root/App/Resources/LaunchFilm
mkdir -p $out
frames=$(mktemp -d)
trap 'rm -rf $frames' EXIT
uv run --with numpy --with pillow --with scipy --with opencv-python-headless python -I \
  $root/tools/asset-pipeline/logo/curlkey.py $root/assets/brand/logo/logo_curl_film.mp4 $frames
cd $root/Packages/HouseCatGame
HOUSECAT_RENDER_LOGO=$out HOUSECAT_CURL_FRAMES=$frames swift test --filter renderTheLogoFilms
ls -l $out
