#!/bin/bash
# Start frames for the cat's films beyond the walk and run (21 Oct): the puppet's white frame and every pass of it,
# on chroma green at 1920 x 1080, as films.sh makes them for the side and three-quarter walks and runs:
#   front <body> <look>   the walk's frame 4 and the run's frame 5, coming straight at you
#   stand <body> <look> [views]   the cat standing still (for a scratch, a sit-down: `<view>_stand_<pass>_000.png`)
#   uv <body> <look>      the torso map pass alone for the side and three-quarter walk and run frames (for the
#                          garments on the films already made)
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
START="$ROOT/assets/cat/films/start"
PASSES="white,features,whiskers,tabby_classic,tabby_mackerel,spotted,tortie,colourpoint,white_bicolour,white_mitts,white_tuxedo,white_van,part:_ear_,part:_tail,part:_head,part:.,ids,points,uv"
what="$1"
body="$2"
look="$3"
export HOUSECAT_RENDER_PUPPET="$START/$body"
export HOUSECAT_PUPPET_LOOK="$look"
export HOUSECAT_PUPPET_STRIDES=1
export HOUSECAT_PUPPET_FRAME=1920,1080,780
export HOUSECAT_PUPPET_BACKDROP=0,0.69,0.25
export HOUSECAT_PUPPET_NO_SHADOW=1
mkdir -p "$START/$body"
cd "$ROOT/Packages/HouseCatGame"
render() {
  swift test --filter renderThePuppetsMovement 2>&1 | grep -E "passed|failed|error:" | tail -2
}
case "$what" in
front)
  HOUSECAT_PUPPET_VIEWS=front HOUSECAT_PUPPET_GAITS=walk HOUSECAT_PUPPET_ONLY_FRAME=4 HOUSECAT_PUPPET_PASSES="$PASSES" render
  HOUSECAT_PUPPET_VIEWS=front HOUSECAT_PUPPET_GAITS=run HOUSECAT_PUPPET_ONLY_FRAME=5 HOUSECAT_PUPPET_PASSES="$PASSES" render
  ;;
stand)
  HOUSECAT_PUPPET_VIEWS="${4:-side,tqfront}" HOUSECAT_PUPPET_STAND=1 HOUSECAT_PUPPET_PASSES="$PASSES" render
  ;;
uv)
  HOUSECAT_PUPPET_VIEWS=side,tqfront HOUSECAT_PUPPET_GAITS=walk HOUSECAT_PUPPET_ONLY_FRAME=4 HOUSECAT_PUPPET_PASSES=uv render
  HOUSECAT_PUPPET_VIEWS=side,tqfront HOUSECAT_PUPPET_GAITS=run HOUSECAT_PUPPET_ONLY_FRAME=5 HOUSECAT_PUPPET_PASSES=uv render
  ;;
*)
  echo "starts.sh front|stand|uv <body> <look> [views]" >&2
  exit 1
  ;;
esac
ls "$START/$body" | wc -l
