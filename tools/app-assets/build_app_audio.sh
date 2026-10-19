#!/bin/zsh
# Builds App/Audio: the sounds the app plays, from assets/audio, as AAC (.m4a) with afconvert. ui_knock_off and
# ui_sparkle (the mini-games) were synthesised for step 6, like the other UI sounds. The music_ loops (stereo) are
# composed by tools/app-assets/make_music.py.
# The masters are never edited. Run from the repo root: tools/app-assets/build_app_audio.sh
set -e
OUT=App/Audio
rm -rf $OUT && mkdir -p $OUT
for name in door_open cat_meow_short cat_meow_long cat_chirp cat_trill cat_grumble cat_purr_loop \
            fire_crackle_loop night_crickets_loop dawn_birds_loop ui_place_item ui_tap \
            cat_meow_hungry cat_meow_soft ui_bean_chime ui_level_up ui_gift_open_common ui_gift_open_uncommon \
            ui_gift_open_rare ui_gift_open_legendary ui_streak_milestone \
            rain_loop wind_loop snow_hush_loop ui_purchase_confirm \
            ui_knock_off ui_sparkle cat_zoomies_thumps cat_sleep_breathing music_windowsill music_lullaby; do
  afconvert -f m4af -d aac -b 96000 assets/audio/$name.wav $OUT/$name.m4a
done
du -sh $OUT
