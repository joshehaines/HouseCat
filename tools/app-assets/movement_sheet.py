"""A contact sheet of every way the cat moves, from the clips `renderTheMovementInventory` writes (HouseCatGame tests,
HOUSECAT_RENDER_INVENTORY=<folder>): each clip a tile with its name and whether it is a film or the puppet, all playing
together in one GIF, plus one GIF per clip when asked.

    uv run --with pillow python tools/app-assets/movement_sheet.py <folder> <out.gif> [--each <folder>] [--fps 10]
        [--columns 5] [--tile 220x165]
"""
import argparse
import json
import os

from PIL import Image, ImageDraw, ImageFont


def frames_of(folder, step):
    names = sorted(n for n in os.listdir(folder) if n.endswith('.png'))
    return [os.path.join(folder, n) for n in names[::step]]


def fitted(image, width, height):
    image = image.convert('RGB')
    image.thumbnail((width, height), Image.LANCZOS)
    canvas = Image.new('RGB', (width, height), (237, 224, 199))
    canvas.paste(image, ((width - image.width) // 2, (height - image.height) // 2))
    return canvas


def label(canvas, name, how, font):
    draw = ImageDraw.Draw(canvas)
    w, h = canvas.size
    draw.rectangle([0, h - 30, w, h], fill=(40, 32, 30))
    puppet = how.startswith('PUPPET') or 'PUPPET' in how
    colour = (255, 150, 120) if puppet else (170, 235, 160)
    draw.text((6, h - 29), name, fill=(255, 250, 240), font=font)
    draw.text((6, h - 15), how, fill=colour, font=font)
    return canvas


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('folder')
    parser.add_argument('out')
    parser.add_argument('--each')
    parser.add_argument('--fps', type=int, default=10)
    parser.add_argument('--columns', type=int, default=5)
    parser.add_argument('--tile', default='220x165')
    args = parser.parse_args()
    tw, th = (int(v) for v in args.tile.split('x'))
    tiles = json.load(open(os.path.join(args.folder, 'tiles.json')))
    step = max(1, 30 // args.fps)
    try:
        font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 12)
    except OSError:
        font = ImageFont.load_default()
    clips = []
    for tile in tiles:
        paths = frames_of(os.path.join(args.folder, tile['folder']), step)
        clips.append((tile, paths))
    longest = max(len(paths) for _, paths in clips)
    columns = args.columns
    rows = (len(clips) + columns - 1) // columns
    sheet = []
    for f in range(longest):
        canvas = Image.new('RGB', (columns * tw, rows * th), (30, 26, 24))
        for i, (tile, paths) in enumerate(clips):
            path = paths[f % len(paths)]
            cell = label(fitted(Image.open(path), tw, th), tile['name'], tile['how'], font)
            canvas.paste(cell, ((i % columns) * tw, (i // columns) * th))
        sheet.append(canvas)
    palette = sheet[0].quantize(colors=200, method=Image.Quantize.MEDIANCUT)
    quantized = [frame.quantize(colors=200, palette=palette, dither=Image.Dither.NONE) for frame in sheet]
    quantized[0].save(args.out, save_all=True, append_images=quantized[1:], duration=1000 // args.fps, loop=0, optimize=True)
    print(f'{args.out}: {len(sheet)} frames, {columns}x{rows} tiles, {os.path.getsize(args.out) / 1e6:.1f} MB')
    if args.each:
        os.makedirs(args.each, exist_ok=True)
        for tile, paths in clips:
            frames = [fitted(Image.open(p), 480, 360) for p in paths]
            palette = frames[0].quantize(colors=160)
            q = [frame.quantize(colors=160, palette=palette, dither=Image.Dither.NONE) for frame in frames]
            out = os.path.join(args.each, tile['folder'] + '.gif')
            q[0].save(out, save_all=True, append_images=q[1:], duration=1000 // args.fps, loop=0, optimize=True)


if __name__ == '__main__':
    main()
