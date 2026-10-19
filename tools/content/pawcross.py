"""Pawcross, Pat's daily puzzle (the Games menu; CLAUDE.md "The Games menu"): makes Content/pawcross.json.

Every picture is drawn by hand, square by square, after the painting it turns into when it is solved (a gift, an
icon, a piece of furniture, or the player's own cat in a pose), so the reveal always matches what was drawn. Puzzle
No. 1 is Monday 19 October 2026 and the list is laid out week by week: 10 squares across at most on Monday and
Tuesday, 12 on Wednesday and Thursday, 12 to 15 from Friday to Sunday. After the last week it goes round again.

Each picture is checked before it is written: it can be solved a line at a time with no guessing (the same line
solver as HouseCatCore's `Pawcross.solve`), it has no empty row or column, it is between 28% and 75% filled, its
painting is in the app, and it is the right size for its weekday. `{cat}` in a title is the player's cat's name.

    uv run --with pillow python tools/content/pawcross.py [sheet.png]

With a sheet path it also draws every picture beside its painting, for checking by eye.
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'Content', 'pawcross.json')
ART = os.path.join(ROOT, 'App', 'Art', 'art.json')
POSES = {'sit_side', 'sit_tqfront', 'sit_front', 'sit_back', 'loaf_side', 'loaf_tqfront', 'sleep_curl', 'stretch_side'}

# Four weeks, Monday first: (id, what it is, the painting it turns into, the squares top row first).
WEEKS = [
    # Week 1 (from 19 October)
    ('fish', 'A fish', 'arcade/match/match_fish.png', [
        '...###...#',
        '.######.##',
        '##.######.',
        '#########.',
        '.########.',
        '.######.##',
        '...###...#',
    ]),
    ('cat_face', 'A cat face', 'ui/icon_cat_face.png', [
        '.#......#.',
        '.##....##.',
        '.###..###.',
        '.########.',
        '##.####.##',
        '##.####.##',
        '##########',
        '####..####',
        '.########.',
        '...####...',
    ]),
    ('pumpkin', 'A little pumpkin', 'gifts/gift_seasonal_mini_pumpkin.png', [
        '.....##.....',
        '......#.....',
        '..###..###..',
        '.####.#####.',
        '####.##.####',
        '####.##.####',
        '####.##.####',
        '####.##.####',
        '.####..####.',
        '..########..',
    ]),
    ('timer', 'A sand timer', 'arcade/ui/icon_game_timer.png', [
        '##########',
        '.#......#.',
        '.#......#.',
        '..######..',
        '...####...',
        '....##....',
        '....##....',
        '...#..#...',
        '..#.##.#..',
        '.#.####.#.',
        '.########.',
        '##########',
    ]),
    ('sit_front', '{cat}, sitting up', 'cat:sit_front', [
        '..#.......#..',
        '..##.....##..',
        '..#########..',
        '.###########.',
        '.##..###..##.',
        '.##..###..##.',
        '.#####.#####.',
        '..#########..',
        '...#######...',
        '...#######...',
        '..#########..',
        '..#########..',
        '..####.####.#',
        '..####.####.#',
        '############.',
    ]),
    ('leaf', 'An autumn leaf', 'gifts/gift_oddities_autumn_leaf.png', [
        '.......#.......',
        '......###......',
        '...#..###..#...',
        '...##.###.##...',
        '#..##########.#',
        '##.####.####.##',
        '.######.######.',
        '..#####.#####..',
        '.######.######.',
        '...####.####...',
        '.....##.##.....',
        '.......#.......',
        '......#........',
    ]),
    ('owl', 'An owl on the moon', 'ui/icon_way_owl.png', [
        '....###........',
        '..####.........',
        '.####..#...#...',
        '.###...#####...',
        '####...#.#.#...',
        '####...#####...',
        '####...#####...',
        '####..#######..',
        '#####.#.###.#..',
        '.####.#.###.#..',
        '.#####.#####..#',
        '..######.#.###.',
        '...##########..',
        '.....######....',
    ]),
    # Week 2
    ('acorn', 'An acorn', 'gifts/gift_keepsakes_acorn.png', [
        '....#....',
        '..#####..',
        '.#######.',
        '#########',
        '#.#.#.#.#',
        '.#######.',
        '.#######.',
        '..#####..',
        '...###...',
        '....#....',
    ]),
    ('present', 'A present', 'ui/icon_gift_box_with_a_ribbon.png', [
        '.###..###.',
        '#...##...#',
        '.###..###.',
        '##########',
        '#...##...#',
        '##########',
        '.#..##..#.',
        '.#..##..#.',
        '.#..##..#.',
        '.########.',
    ]),
    ('cupcake', 'A cupcake', 'ui/icon_creator_cupcake.png', [
        '.....##.....',
        '....####....',
        '..########..',
        '.##########.',
        '############',
        '############',
        '############',
        '.#.#.##.#.#.',
        '.#.#.##.#.#.',
        '..#.#..#.#..',
        '..#.#..#.#..',
        '...######...',
    ]),
    ('key', 'A brass key', 'gifts/gift_keepsakes_brass_key.png', [
        '.####.......',
        '##..##......',
        '#....#######',
        '#....#######',
        '##..##..#.##',
        '.####...#.#.',
        '........#...',
    ]),
    ('sleep_curl', '{cat}, fast asleep', 'cat:sleep_curl', [
        '.#...#.........',
        '.##.##.#####...',
        '.#####.#######.',
        '.######.######.',
        '.#.#.##.#######',
        '.######.#######',
        '.######.#######',
        '.#####.########',
        '..###.#########',
        '#....##########',
        '.##############',
        '..############.',
        '...##########..',
        '.....#####.....',
    ]),
    ('pinecone', 'A pine cone', 'gifts/gift_seasonal_pine_cone.png', [
        '.....#.....',
        '....###....',
        '..#######..',
        '.##.###.##.',
        '.#########.',
        '##.###.###.',
        '###########',
        '###.###.###',
        '###########',
        '##.###.###.',
        '.#########.',
        '.##.###.##.',
        '..#######..',
        '...#####...',
        '....###....',
    ]),
    ('house', 'A little house', 'ui/icon_house.png', [
        '..........##...',
        '.......#..##...',
        '......###.##...',
        '.....#######...',
        '....#########..',
        '...###########.',
        '..#############',
        '###############',
        '.#############.',
        '.#############.',
        '.#...###.#.###.',
        '.#...###.#.###.',
        '.#...#########.',
        '.#...#########.',
        '###############',
    ]),
    # Week 3
    ('paw_heart', 'A heart with a paw print', 'ui/icon_trust_heart_with_a_paw_print.png', [
        '.###..###.',
        '##########',
        '###.##.###',
        '##.####.##',
        '###....###',
        '.###..###.',
        '..######..',
        '...####...',
        '....##....',
    ]),
    ('padlock', 'A padlock', 'ui/icon_padlock.png', [
        '..####..',
        '.#....#.',
        '.#....#.',
        '.#....#.',
        '########',
        '########',
        '###..###',
        '###..###',
        '########',
        '.######.',
    ]),
    ('sit_side', '{cat}, sitting nicely', 'cat:sit_side', [
        '..#..#....',
        '..####....',
        '.#####....',
        '##.###....',
        '.#####....',
        '..###.....',
        '..####....',
        '..#####...',
        '..######..',
        '..#######.',
        '..#######.',
        '##########',
    ]),
    ('trophy', 'A trophy', 'arcade/ui/icon_game_trophy.png', [
        '.##########.',
        '#.########.#',
        '#.########.#',
        '.#.######.#.',
        '...######...',
        '....####....',
        '.....##.....',
        '.....##.....',
        '....####....',
        '...######...',
        '...######...',
        '..########..',
    ]),
    ('stretch', '{cat}, having a stretch', 'cat:stretch_side', [
        '............##.',
        '...........#..#',
        '...........#...',
        '..........###..',
        '.#.#.....#####.',
        '.###...#######.',
        '#####.########.',
        '.#############.',
        '######.....###.',
        '#####......#.##',
    ]),
    ('shell', 'A seashell', 'gifts/gift_keepsakes_small_seashell.png', [
        '.....#####.....',
        '...##.###.##...',
        '..###.###.###..',
        '.#.##.###.##.#.',
        '.#.##.###.##.#.',
        '##.##.###.##.##',
        '##.##.###.##.##',
        '##.##.###.##.##',
        '.##.##.#.##.##.',
        '..##.##.##.##..',
        '...##.###.##...',
        '....#######....',
        '...#########...',
    ]),
    ('camera', 'A camera', 'ui/icon_camera_for_photos.png', [
        '..###.....###..',
        '..###....###...',
        '.#############.',
        '######...######',
        '#####.###.#####',
        '####.##.##.####',
        '####.#...#.####',
        '####.##.##.####',
        '#####.###.#####',
        '######...######',
        '.#############.',
    ]),
    # Week 4
    ('bowl', 'A food bowl', 'ui/icon_feed_bowl.png', [
        '..######..',
        '.########.',
        '##########',
        '.##.##.##.',
        '.###..###.',
        '..##..##..',
        '..######..',
    ]),
    ('crown', 'A crown', 'ui/icon_crown.png', [
        '##..##..##',
        '##..##..##',
        '#...##...#',
        '##..##..##',
        '###.##.###',
        '##########',
        '#.##..##.#',
        '##########',
    ]),
    ('lantern', 'A paper lantern', 'gifts/gift_seasonal_tiny_paper_lantern.png', [
        '...####...',
        '..#....#..',
        '...####...',
        '.########.',
        '##########',
        '#........#',
        '##########',
        '#........#',
        '##########',
        '.########.',
        '...####...',
        '....##....',
    ]),
    ('bag', 'A bag with a paw print', 'ui/icon_shop_bag.png', [
        '....####....',
        '...##..##...',
        '...#....#...',
        '.##########.',
        '.##########.',
        '.###.##.###.',
        '.##.####.##.',
        '.####..####.',
        '.###....###.',
        '.###....###.',
        '.####..####.',
        '############',
    ]),
    ('bird', 'A little knitted bird', 'gifts/gift_toys_little_knitted_bird.png', [
        '...####........',
        '..######.......',
        '.##.####.......',
        '########....###',
        '.#######...####',
        '..#########.###',
        '..###.....####.',
        '..####...####..',
        '...####.####...',
        '....#######....',
        '.....#####.....',
    ]),
    ('cattree', 'A cat tree', 'ui/icon_way_cat_tree.png', [
        '.#######....',
        '..#####.....',
        '...##.......',
        '...##.......',
        '...##.######',
        '...##...##..',
        '...##...##..',
        '.##########.',
        '.##########.',
        '.###....###.',
        '.##......##.',
        '.###....###.',
        '.##########.',
        '############',
    ]),
    ('armchair', 'An armchair', 'ui/icon_sofa_for_furniture.png', [
        '...#########...',
        '..###########..',
        '..###########..',
        '..###########..',
        '.##.#######.##.',
        '###.#######.###',
        '###.........###',
        '###.#######.###',
        '###.#######.###',
        '###############',
        '###############',
        '.#...........#.',
    ]),
]


def clues(line):
    runs, run = [], 0
    for filled in line:
        if filled:
            run += 1
        elif run:
            runs.append(run)
            run = 0
    if run:
        runs.append(run)
    return runs or [0]


def placements(clue, n):
    if clue == [0]:
        return [[False] * n]
    out = []

    def place(i, start, line):
        if i == len(clue):
            out.append(line + [False] * (n - len(line)))
            return
        rest = sum(clue[i + 1:]) + len(clue) - i - 1
        for s in range(start, n - rest - clue[i] + 1):
            nxt = line + [False] * (s - len(line)) + [True] * clue[i]
            if i < len(clue) - 1:
                nxt.append(False)
            place(i + 1, len(nxt), nxt)

    place(0, 0, [])
    return out


def solve(rows, cols):
    """A line at a time from the clues alone; None where the lines never settle a square."""
    h, w = len(rows), len(cols)
    grid = [[None] * w for _ in range(h)]
    row_ways = [placements(c, w) for c in rows]
    col_ways = [placements(c, h) for c in cols]
    changed = True
    while changed:
        changed = False
        for r in range(h):
            row_ways[r] = [p for p in row_ways[r] if all(grid[r][c] is None or grid[r][c] == p[c] for c in range(w))]
            for c in range(w):
                if grid[r][c] is None and row_ways[r] and all(p[c] == row_ways[r][0][c] for p in row_ways[r]):
                    grid[r][c] = row_ways[r][0][c]
                    changed = True
        for c in range(w):
            col_ways[c] = [p for p in col_ways[c] if all(grid[r][c] is None or grid[r][c] == p[r] for r in range(h))]
            for r in range(h):
                if grid[r][c] is None and col_ways[c] and all(p[r] == col_ways[c][0][r] for p in col_ways[c]):
                    grid[r][c] = col_ways[c][0][r]
                    changed = True
    return grid


def problems(index, picture, files):
    pid, title, art, rows = picture
    out = []
    if len({len(r) for r in rows}) != 1:
        return ['rows of different lengths']
    if set(''.join(rows)) - {'#', '.'}:
        out.append('marks other than # and .')
    grid = [[ch == '#' for ch in row] for row in rows]
    h, w = len(grid), len(grid[0])
    rc = [clues(r) for r in grid]
    cc = [clues([grid[r][c] for r in range(h)]) for c in range(w)]
    if [0] in rc or [0] in cc:
        out.append('an empty row or column')
    solved = solve(rc, cc)
    if any(solved[r][c] != grid[r][c] for r in range(h) for c in range(w)):
        out.append('needs a guess')
    fill = sum(map(sum, grid)) / (h * w)
    if not 0.28 <= fill <= 0.75:
        out.append(f'{fill:.0%} filled')
    if art.startswith('cat:'):
        if art[4:] not in POSES:
            out.append(f'no pose {art[4:]}')
    elif art not in files:
        out.append(f'{art} is not in the app')
    size, weekday = max(w, h), index % 7
    if not (size <= 10 if weekday < 2 else size <= 12 if weekday < 4 else 12 <= size <= 15):
        out.append(f'{w}x{h} on weekday {weekday}')
    return out


def sheet(path):
    from PIL import Image, ImageDraw

    cell, gap = 12, 18
    tiles = []
    for index, (pid, title, art, rows) in enumerate(WEEKS):
        h, w = len(rows), len(rows[0])
        tile = Image.new('RGB', (2 * 15 * cell + gap * 2, 15 * cell + 34), (250, 244, 232))
        d = ImageDraw.Draw(tile)
        for r, row in enumerate(rows):
            for c, ch in enumerate(row):
                box = [c * cell, r * cell, c * cell + cell - 2, r * cell + cell - 2]
                d.rectangle(box, fill=(60, 45, 55)) if ch == '#' else d.rectangle(box, outline=(222, 212, 196))
        painting = None
        if art.startswith('cat:'):
            painting = os.path.join(ROOT, 'assets', 'cat', 'poses', 'plain', f'cat_short_slim_{art[4:]}.png')
        else:
            painting = os.path.join(ROOT, 'assets', art)
        if os.path.exists(painting):
            im = Image.open(painting).convert('RGBA')
            im = im.crop(im.getbbox())
            im.thumbnail((15 * cell, 15 * cell))
            tile.paste(im, (15 * cell + gap, 0), im)
        d.text((0, 15 * cell + 6), f'No. {index + 1}  {"MTWTFSS"[index % 7]}  {w}x{h}  {title}', fill=(40, 30, 30))
        tiles.append(tile)
    across = 4
    tw, th = tiles[0].width + gap, tiles[0].height + gap
    out = Image.new('RGB', (across * tw, ((len(tiles) + across - 1) // across) * th), (250, 244, 232))
    for i, tile in enumerate(tiles):
        out.paste(tile, ((i % across) * tw, (i // across) * th))
    out.save(path)


if __name__ == '__main__':
    with open(ART) as f:
        files = json.load(f)['files']
    bad = False
    for index, picture in enumerate(WEEKS):
        found = problems(index, picture, files)
        if found:
            bad = True
            print(f'{picture[0]}: ' + '; '.join(found))
    if len({p[0] for p in WEEKS}) != len(WEEKS):
        bad = True
        print('ids repeat')
    if bad:
        sys.exit(1)
    puzzles = [{'id': pid, 'title': title, 'art': art, 'rows': rows} for pid, title, art, rows in WEEKS]
    with open(OUT, 'w') as f:
        json.dump({'version': 2, 'puzzles': puzzles}, f, indent=1)
        f.write('\n')
    print(f'{len(puzzles)} puzzles, {len(puzzles) // 7} weeks -> {os.path.relpath(OUT, ROOT)}')
    if len(sys.argv) > 1:
        sheet(sys.argv[1])
