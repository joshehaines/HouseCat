"""Cuts the HouseCat wordmark (the letters alone, no house or cat) out of the horizontal logos, for the animated
logo: the mascot bounds in and curls up asleep on top of the letters (App/Sources/Intro/AnimatedLogo.swift,
HouseCatGame LogoScene). Writes new masters beside the logos; the logos themselves are never edited.

    uv run --with pillow python tools/asset-pipeline/wordmark.py

assets/brand/logo/wordmark_on_light.png (dark ink) and wordmark_on_dark.png (cream ink), transparent, 1647 x 480: the
letters along the bottom with clear room above them for the cat asleep on top (the launch screen shows this box, and
the scene's measurements, Tuning.Logo, are in its pixels from the bottom left). Both are cut from the same box, so the
letters sit at the same place in each (the two logos were drawn alike to a few pixels).
"""
import os

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
LOGO = os.path.join(ROOT, 'assets', 'brand', 'logo')
# The letters in logo_horizontal_on_*.png (2323 x 767): the house ends at x 669, the H starts at 700; the ink runs
# from y 251 to 541; the t runs to the picture's right edge. A clear margin round them (12 px each side, added on
# the right), and 166 px of clear sky above for the sleeping cat.
BOX = (688, 73, 2323, 553)
RIGHT_PAD = 12


def main():
    for ink in ('light', 'dark'):
        logo = Image.open(os.path.join(LOGO, f'logo_horizontal_on_{ink}.png')).convert('RGBA')
        letters = logo.crop(BOX)
        cut = Image.new('RGBA', (letters.width + RIGHT_PAD, letters.height), (0, 0, 0, 0))
        cut.paste(letters, (0, 0))
        out = os.path.join(LOGO, f'wordmark_on_{ink}.png')
        cut.save(out, optimize=True)
        print(out, cut.size)


if __name__ == '__main__':
    main()
