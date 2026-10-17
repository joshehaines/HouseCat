#!/bin/zsh
# Builds the app's icon and launch-screen assets from the masters in assets/brand.
# The masters are never edited; this writes derived copies into the targets.
# Run from the repo root: tools/app-assets/build_app_assets.sh
set -euo pipefail

root=${0:A:h:h:h}
brand=$root/assets/brand
icon=$root/Shared/AppIcon.icon
catalog=$root/App/Resources/Assets.xcassets

# iOS 26 layered icon (Icon Composer format): the cat layer over the background.
rm -rf $icon
mkdir -p $icon/Assets
cp $brand/icon/AppIcon_layer1_background.png $icon/Assets/background.png
cp $brand/icon/AppIcon_layer2_cat.png $icon/Assets/cat.png
cat > $icon/icon.json <<'JSON'
{
  "groups" : [
    {
      "layers" : [
        {
          "glass" : false,
          "image-name" : "cat.png",
          "name" : "cat"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : false,
        "value" : 0.5
      }
    },
    {
      "layers" : [
        {
          "glass" : false,
          "image-name" : "background.png",
          "name" : "background"
        }
      ],
      "shadow" : {
        "kind" : "none",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : false,
        "value" : 0.5
      }
    }
  ],
  "supported-platforms" : {
    "circles" : [
      "watchOS"
    ],
    "squares" : "shared"
  }
}
JSON

# Launch screen: the stacked logo, dark ink on cream (light) and cream ink on navy (dark).
logo=$catalog/LaunchLogo.imageset
rm -rf $logo
mkdir -p $logo
for scale in 2 3; do
  sips -s format png --resampleWidth $((200 * scale)) $brand/logo/logo_stacked_on_light.png --out $logo/logo_light@${scale}x.png >/dev/null
  sips -s format png --resampleWidth $((200 * scale)) $brand/logo/logo_stacked_on_dark.png --out $logo/logo_dark@${scale}x.png >/dev/null
done
cat > $logo/Contents.json <<'JSON'
{
  "images" : [
    { "filename" : "logo_light@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "logo_dark@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "logo_light@3x.png", "idiom" : "universal", "scale" : "3x" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "logo_dark@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "App icon and launch assets rebuilt from assets/brand."
