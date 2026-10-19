#!/bin/zsh
# Renders the launch's film of the animated logo (Midnight bounding onto the wordmark and curling up asleep), light and
# dark, from HouseCatGame's LogoScene into App/Resources/LaunchFilm (HEVC with transparency; App/Sources/Intro/
# LaunchFilm.swift plays it). Run after changing the cat's art, Tuning.Logo or the wordmark. Needs a Mac with Metal
# (the scene is rendered offscreen by the test renderTheLaunchLogo).
# Run from anywhere: tools/app-assets/build_logo_film.sh
set -euo pipefail
root=${0:A:h:h:h}
out=$root/App/Resources/LaunchFilm
mkdir -p $out
cd $root/Packages/HouseCatGame
HOUSECAT_RENDER_LOGO=$out swift test --filter renderTheLaunchLogo
ls -l $out
