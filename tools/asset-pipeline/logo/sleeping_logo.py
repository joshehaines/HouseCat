"""Builds the secondary logo: the HouseCat wordmark with Midnight curled up asleep on the letters, where the animated
logo ends (Josh, 19 Oct: it replaces the logo with the cat in the house). New masters beside the others; nothing is
edited.

    uv run --with pillow --with numpy python tools/asset-pipeline/logo/sleeping_logo.py

assets/brand/logo/logo_sleeping_on_light.png (dark ink) and logo_sleeping_on_dark.png (cream ink), transparent,
1647 x 540: the wordmark master (wordmark_on_*.png, 1647 x 480) along the bottom, the curl painting
(cat/poses/plain/cat_short_slim_sleep_curl.png) on the lowercase letters exactly as LogoScene draws it at the end
(Tuning.Logo: the bed, the letters' top, the cat's height and the curl's scale), with its soft shadow.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
ASSETS = os.path.join(ROOT, 'assets')
# From Tuning.Logo and the puppet rig: the cat's standing height and the side view's whole height (the scale its
# paintings are drawn at), the curl's extra scale, where it lies (box pixels from the bottom left), its shadow.
CAT_HEIGHT, WHOLE_HEIGHT, CURL_SCALE = 560.0, 990.0, 1.3
BED, VALLEY_TOP = 690.0, 221.0
REST_WIDTH, SHADOW_WIDTH, SHADOW_DEPTH, SHADOW_ALPHA = 0.45, 0.75, 0.18, 0.35
# The logo's canvas: the wordmark's box with room above it for the curl.
WIDTH, HEIGHT = 1647, 540


def soft_disc(width, height, alpha):
    y, x = np.mgrid[0:height, 0:width]
    d = np.sqrt(((x + 0.5) / width - 0.5) ** 2 + ((y + 0.5) / height - 0.5) ** 2) * 2
    a = np.clip(1 - d, 0, 1) * alpha
    rgba = np.zeros((height, width, 4), np.uint8)
    rgba[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(rgba, 'RGBA')


def main():
    curl = Image.open(os.path.join(ASSETS, 'cat/poses/plain/cat_short_slim_sleep_curl.png')).convert('RGBA')
    scale = CAT_HEIGHT / WHOLE_HEIGHT * CURL_SCALE
    curl = curl.resize((round(curl.width * scale), round(curl.height * scale)), Image.LANCZOS)
    rest = CAT_HEIGHT * REST_WIDTH * CURL_SCALE
    shadow = soft_disc(round(rest * SHADOW_WIDTH), round(rest * SHADOW_WIDTH * SHADOW_DEPTH), SHADOW_ALPHA)
    for ink in ('light', 'dark'):
        word = Image.open(os.path.join(ASSETS, f'brand/logo/wordmark_on_{ink}.png')).convert('RGBA')
        logo = Image.new('RGBA', (WIDTH, HEIGHT), (0, 0, 0, 0))
        logo.alpha_composite(word, (0, HEIGHT - word.height))
        floor = HEIGHT - VALLEY_TOP
        logo.alpha_composite(shadow, (round(BED - shadow.width / 2), round(floor - shadow.height / 2)))
        logo.alpha_composite(curl, (round(BED - curl.width / 2), round(floor - curl.height)))
        out = os.path.join(ASSETS, f'brand/logo/logo_sleeping_on_{ink}.png')
        logo.save(out, optimize=True)
        print(out, logo.size)


if __name__ == '__main__':
    main()
