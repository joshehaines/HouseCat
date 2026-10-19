#!/bin/bash
# The cat's walk and run films, end to end (filmwalk.py says how):
#   1. the start frames: each body's puppet in its white painting at the first frame of its walk (frame 4) and its run
#      (frame 5), side on and at three-quarters, on chroma green at 1920 x 1080, and every pass of the same frame;
#   2. (by hand) the films: Higgsfield Kling 3.0 pro, 5 s, 16:9, sound off, each started from its white frame, saved as
#      assets/cat/films/<body>_<view>_<gait>.mp4 (the prompts are in the README beside them);
#   3. every film through filmwalk.py into assets/cat/films/frames, then build_cat_art.py copies them into the app.
#
#   tools/asset-pipeline/walk/films.sh start    # step 1, into assets/cat/films/start
#   tools/asset-pipeline/walk/films.sh frames   # step 3
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
START="$ROOT/assets/cat/films/start"
FRAMES="$ROOT/assets/cat/films/frames"
# Each body's look (its own ears and tail) and its breed's scale.
LOOKS="short_slim:midnight:1.0 short_chunky:bombay:1.0 long_slim:turkish_van:1.0 long_chunky:ragdoll:1.0 persian:white_persian:1.0 siamese:seal_point:1.0 mainecoon:maine_coon:1.15 sphynx:sphynx:1.0"
PASSES="white,features,whiskers,tabby_classic,tabby_mackerel,spotted,tortie,colourpoint,white_bicolour,white_mitts,white_tuxedo,white_van,part:_ear_,part:_tail,part:_head,part:.,ids,points"

case "$1" in
start)
  for entry in $LOOKS; do
    IFS=: read -r body look _ <<< "$entry"
    mkdir -p "$START/$body"
    for gait in walk:4 run:5; do
      (cd "$ROOT/Packages/HouseCatGame" && HOUSECAT_RENDER_PUPPET="$START/$body" HOUSECAT_PUPPET_LOOK="$look" \
        HOUSECAT_PUPPET_VIEWS=side,tqfront HOUSECAT_PUPPET_GAITS="${gait%%:*}" HOUSECAT_PUPPET_ONLY_FRAME="${gait##*:}" \
        HOUSECAT_PUPPET_STRIDES=1 HOUSECAT_PUPPET_FRAME=1920,1080,780 HOUSECAT_PUPPET_BACKDROP=0,0.69,0.25 \
        HOUSECAT_PUPPET_NO_SHADOW=1 HOUSECAT_PUPPET_PASSES="$PASSES" swift test --filter renderThePuppetsMovement)
    done
  done
  ;;
frames)
  for entry in $LOOKS; do
    IFS=: read -r body _ breed <<< "$entry"
    for view in side tqfront; do
      for gait in walk:004 run:005; do
        (cd "$ROOT" && uv run --with numpy --with pillow --with scipy --with scikit-image --with opencv-python-headless \
          --with torch --with torchvision --with imageio-ffmpeg python tools/asset-pipeline/walk/filmwalk.py \
          "assets/cat/films/${body}_${view}_${gait%%:*}.mp4" "$START/$body" "$body" "$view" "${gait%%:*}" "${gait##*:}" \
          "$FRAMES" "$breed")
      done
    done
  done
  ;;
*)
  echo "films.sh start|frames" >&2
  exit 1
  ;;
esac
