"""The cat's walk and run as films (Josh, 19 Oct: of the rebuilt puppet and a generated film, "B is the best by far").

Each body has a white-cat film per view (side, three-quarter front) and gait (walk; run, filmed in slow motion):
Higgsfield Kling 3.0 pro, 5 s, 1080p, started from the puppet's own white frame on chroma green, the camera tracking
the cat so it walks in place (assets/cat/films/<body>_<view>_<gait>.mp4). The same frame is rendered again from every
coat mask, a part-by-part shade, the parts' coverage and a few points (`renderThePuppetsMovement`,
HOUSECAT_PUPPET_PASSES; assets/cat/films/start/<body>), so the masks are known in the film's first frame. This carries
them through the film and writes one stride of it as builder sprites the game tints into any look (CoatRecipe), like
the puppet's parts:

  1. Key the green (as the logo's curl film); a haze of dust is let go. Kling holds most pictures for two of its 24
     frames a second: each picture is kept once.
  2. Optical flow (RAFT) from each picture back to the one before, chained: where each pixel was in the start frame.
  3. One stride: the earliest, shortest stretch whose end is the same pose as its start, also by where the legs were in
     the start frame, and that lasts as long as a whole stride (`PERIOD`; half a stride, the near legs where the far
     ones were, is never taken). Over it the chain forward
     from its start is blended with a chain back from its end (tied to its start), so the loop has no seam.
  4. The masks looked up where each pixel came from. The head, body and tail track well; the legs do not (they cross
     and hide each other), so a leg takes the start frame's front or hind leg pattern at the same distance down it
     from the body (stripes, socks and points land where they were). The irises are found again in each picture by
     their colour, near where they were tracked (shut in a blink). The fur mask is the picture's own (tint.py's), as
     build_cat_art.py makes it. The thin light line the start frame had round the neck is painted over.
  5. How fast the floor goes by under a planted paw (the stride's length on the floor; rough, so the game paces the
     films by Tuning.Puppet.filmWalkPace and filmRunPace instead); where the cat's feet are; the ears' and tail's points followed through the stride.
  6. The stride's pictures, cropped round the cat and scaled to the puppet's size: white painting (JPEG), alpha, the fur,
     pattern and white-marking masks at half size, the features at full size, and the film's own ears, tail and head
     (to swap ears and tails), with films/films.json.

    uv run --with numpy --with pillow --with scipy --with scikit-image --with opencv-python-headless --with torch \\
        --with torchvision --with imageio-ffmpeg python tools/asset-pipeline/walk/filmwalk.py \\
        <film.mp4> <start folder> <body> <view> <gait> <start frame> <out> [breed scale]

<start folder> holds <view>_<gait>_<pass>_<frame>.png (and _points_<frame>.json) from the render; <out> is
assets/cat/films/frames (build_cat_art.py copies it into App/Art/cat/custom): base|alpha|masks/<kind>/films/
cat_<body>_<view>_<gait>_NN.png and films/films.json. All of it: tools/asset-pipeline/walk/films.sh.
"""
import json
import os
import subprocess
import sys

import cv2
import imageio_ffmpeg
from scipy import ndimage
import numpy as np
import torch
from PIL import Image
from torchvision.models.optical_flow import Raft_Large_Weights, raft_large

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from tint import _fur_mask  # noqa: E402

# Greenness (G minus the larger of R and B) where a pixel starts and stops being background (curlkey.py's).
SOLID, CLEAR = 18, 70
# The puppet's render: the cat's standing height (the CatNode's height) in the film's pixels, before the breed's scale.
RENDER_HEIGHT = 780
# Stored frames: the cat this many pixels tall (the puppet's parts put it about 430 tall), and at most this many a loop
# (every picture of a walk's stride is kept: Kling shows 12 or 24 a second).
STORE_HEIGHT = 340
MOST_FRAMES = {'walk': 40, 'run': 16}
# A stride lasts this many seconds of film, by gait: one stride, so the game's cadence holds whichever film is on (a
# longer loop would be two or three, a shorter one half a stride with the near and far legs swapped). Kling shows 12 or
# 24 pictures a second, film by film. The runs are filmed in slow motion (at full speed a gallop was only three or four
# pictures; slowed, a stride is a second or more, of which 16 pictures are kept). The film settles into its stride
# after `SETTLE` pictures.
PERIOD = {'walk': (0.55, 1.75), 'run': (1.0, 3.75)}
SETTLE = 4
# Two frames differing by less than this (mean, 0-255) are the same picture shown again.
REPEAT = 2.5
# Flow is worked at this width (the stored frames are smaller still).
TRACK_WIDTH = 960
# Every coat mask carried from the start frame (the patterns and white markings at half size), the features (irises,
# nose) at full size, and the parts that can be swapped for others (ears, tail). The fur mask is the frame's own.
MASKS = ['whiskers', 'tabby_classic', 'tabby_mackerel', 'spotted', 'tortie', 'colourpoint', 'white_bicolour',
         'white_mitts', 'white_tuxedo', 'white_van']
PARTS = {'ears': 'part-_ear_', 'tail': 'part-_tail', 'head': 'part-_head'}


def probe(path):
    """The film's width and height."""
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    info = subprocess.run([ff, '-i', path], capture_output=True, text=True).stderr
    size = next(part for part in info.split() if 'x' in part and part.split('x')[0].isdigit() and part.split('x')[-1].rstrip(',').isdigit())
    return tuple(int(v) for v in size.rstrip(',').split('x'))


def decode(path, size=None, frames=None):
    """The film's frames (RGB), scaled to `size`, or only the frames numbered in `frames`."""
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    w, h = size or probe(path)
    filters = [f'scale={w}:{h}:flags=area'] if size else []
    if frames is not None:
        filters.append('select=' + '+'.join(f'eq(n\\,{n})' for n in frames))
    command = [ff, '-loglevel', 'error', '-i', path] + (['-vf', ','.join(filters)] if filters else [])
    command += ['-vsync', '0', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-']
    raw = subprocess.run(command, capture_output=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3)


def key(rgb):
    a = rgb.astype(np.float32)
    green = a[..., 1] - np.maximum(a[..., 0], a[..., 2])
    alpha = np.clip((CLEAR - green) / (CLEAR - SOLID), 0, 1)
    # Only the cat: a haze of dust kicked up behind a running cat is let go (what is not near the cat's solid body).
    solid = (alpha > 0.6).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(solid, connectivity=8)
    if count > 1:
        areas = stats[1:, cv2.CC_STAT_AREA]
        keep = np.zeros(count, bool)
        keep[1:] = areas >= areas.max() * 0.02
        body = cv2.dilate(keep[labels].astype(np.uint8), np.ones((9, 9), np.uint8))
        alpha *= cv2.GaussianBlur(body.astype(np.float32), (0, 0), 2)
    # Green spill on the fur's edge pulled back to the fur's own colour.
    a[..., 1] = np.minimum(a[..., 1], np.maximum(a[..., 0], a[..., 2]) + 4)
    return a, alpha


class Flow:
    """RAFT on the GPU: where each pixel of one frame was in another, worked at the tracking size."""

    def __init__(self, width, height):
        self.device = 'mps' if torch.backends.mps.is_available() else 'cpu'
        self.model = raft_large(weights=Raft_Large_Weights.DEFAULT).eval().to(self.device)
        self.size = (width, height)
        # A multiple of 8 each way.
        self.work = (int(np.ceil(width / 8)) * 8, int(np.ceil(height / 8)) * 8)

    def prepare(self, rgb, alpha):
        image = rgb.astype(np.float32) * alpha[..., None] + 110 * (1 - alpha[..., None])
        if image.shape[1::-1] != self.work:
            image = cv2.copyMakeBorder(image, 0, self.work[1] - image.shape[0], 0, self.work[0] - image.shape[1],
                                       cv2.BORDER_REPLICATE)
        tensor = torch.from_numpy(image).permute(2, 0, 1)[None] / 127.5 - 1
        return tensor.to(self.device)

    @torch.no_grad()
    def __call__(self, frame, other):
        """For each pixel of `frame` (rgb, alpha), the offset to where it is in `other`."""
        flows = self.model(self.prepare(*frame), self.prepare(*other), num_flow_updates=16)
        w, h = self.size
        return flows[-1][0].permute(1, 2, 0).cpu().numpy()[:h, :w].copy()


def follow(coords, flow, grid):
    """Coordinates looked up through a flow: for each pixel, `coords` where the flow takes it."""
    xs, ys = grid
    cx, cy = coords[0].astype(np.float32), coords[1].astype(np.float32)
    mx = cv2.remap(cx, xs + flow[..., 0], ys + flow[..., 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    my = cv2.remap(cy, xs + flow[..., 0], ys + flow[..., 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    return mx, my


def fur(rgb, alpha):
    """tint.py's fur mask from the frame itself (1 = tint, 0 = keep the white painting: pink inner ears, nose, pads), as
    build_cat_art.py makes it for a sprite: carried from the start frame, a pixel tracked off the cat would stay white."""
    mask = _fur_mask(rgb)
    inside = ndimage.binary_erosion(alpha > 0.5, iterations=7)
    return np.where(~inside & (alpha > 0), 1.0, mask)


def save_mask(values, path):
    """A mask (0-1) in 16 levels of grey, as build_cat_art.py saves the builder's (they compress far better)."""
    levels = np.round(np.clip(values, 0, 1) * 15) * 17
    Image.fromarray(levels.astype(np.uint8)).save(path, optimize=True)


def without_collar(rgb, alpha, head):
    """The film without the thin light line round the neck: the puppet's start frame had the head's rim of light over
    the body there, and the film kept it. Painted over (inpainted) along where the head meets the body, inside the
    cat (its outline is left alone). `head` is the tracked head at the tracking size."""
    height, width = alpha.shape
    head = cv2.resize(head, (width, height), interpolation=cv2.INTER_LINEAR) > 0.5
    reach = max(3, width // 320)
    ring = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * reach + 1, 2 * reach + 1))
    band = cv2.dilate(head.astype(np.uint8), ring) & ~cv2.erode(head.astype(np.uint8), ring).astype(bool)
    inside = cv2.erode((alpha > 0.5).astype(np.uint8), np.ones((4 * reach + 1, 4 * reach + 1), np.uint8)) > 0
    band = (band.astype(bool) & inside).astype(np.uint8)
    if not band.any():
        return rgb
    return cv2.inpaint(rgb, band * 255, reach, cv2.INPAINT_TELEA)


def filled(rgb, alpha):
    """The cat's colour carried out past its edge (each clear pixel takes its nearest solid one), so tinting and
    scaling never bring in green."""
    solid = alpha > 0.5
    if not solid.any():
        return rgb
    _, labels = cv2.distanceTransformWithLabels((~solid).astype(np.uint8), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
    where = np.zeros(labels.max() + 1, np.int64)
    sy, sx = np.nonzero(solid)
    where[labels[sy, sx]] = sy * rgb.shape[1] + sx
    out = rgb.reshape(-1, 3)[where[labels]].reshape(rgb.shape)
    out[solid] = rgb[solid]
    return out


# The part shades in the start frame's ids pass (PuppetMotionRender): the body's parts and each leg.
SHADES = np.array([0, 20, 40, 80, 100, 120, 160, 190, 220, 250])
BODY_SHADES = [40, 80, 100, 120]
TORSO, HEAD, EARS, TAIL = 40, 80, 100, 120
LEGS = {'front': 160, 'back': 220}
# A leg's pattern is read off the start frame's near leg in this many steps from the body to the paw.
LEG_STEPS = 40


def shades(image):
    """The ids pass's anti-aliased greys snapped to the nearest part's shade."""
    return SHADES[np.abs(image[..., None].astype(np.int16) - SHADES).argmin(-1)].astype(np.uint8)


def reach(region, sources):
    """How far each pixel of `region` is from `sources` going only through `region` (inf where it cannot be reached)."""
    from skimage.graph import MCP_Geometric
    starts = list(zip(*np.nonzero(sources & region)))
    if not starts:
        return np.full(region.shape, np.inf)
    distance, _ = MCP_Geometric(np.where(region, 1.0, np.inf)).find_costs(starts)
    return distance


def grown(mask, pixels):
    return cv2.dilate(mask.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * pixels + 1, 2 * pixels + 1))) > 0


def leg_map(ids, alpha):
    """The legs: what is below the torso's underside, column by column (the torso tracks well; a leg's own tracking
    does not), not the head, ears or tail. How far down a leg each pixel is, by the shortest way inside the legs from the
    torso; and whether it is a front leg, by which side of the torso's middle it is (both views face left). The same in
    the start frame and the film's, so a film's leg takes the start frame's pattern at the same distance down."""
    solid = alpha > 0.4
    torso = cv2.morphologyEx(((ids == TORSO) & solid).astype(np.uint8), cv2.MORPH_OPEN, np.ones((5, 5), np.uint8)) > 0
    if not torso.any():
        return None
    height, width = alpha.shape
    columns = np.nonzero(torso.any(axis=0))[0]
    lowest = height - 1 - np.argmax(torso[::-1, columns], axis=0)
    bottom = np.interp(np.arange(width), columns, lowest)
    legs = solid & (np.arange(height)[:, None] > bottom[None, :]) & ~np.isin(ids, [HEAD, EARS, TAIL])
    distance = reach(legs, grown(torso, 1))
    middle = np.nonzero(torso)[1].mean()
    front = np.arange(width)[None, :].repeat(height, 0) < middle
    return legs & np.isfinite(distance), distance, front


def leg_profiles(ids, solid, layers):
    """Each end's legs' masks from the body down to the paw, in `LEG_STEPS` steps, and how long the legs are."""
    found = leg_map(ids, solid)
    if found is None:
        return {}
    legs, distance, front = found
    profiles = {}
    for end in ('front', 'back'):
        inside = legs & (front if end == 'front' else ~front)
        if inside.sum() < 50:
            continue
        length = float(np.percentile(distance[inside], 98))
        steps = np.clip((distance[inside] / length * (LEG_STEPS - 1)).round().astype(int), 0, LEG_STEPS - 1)
        counts = np.bincount(steps, None, LEG_STEPS)
        profile = {}
        for name, layer in layers.items():
            values = np.bincount(steps, layer[inside], LEG_STEPS) / np.maximum(counts, 1)
            # Steps with no pixels take their neighbours'.
            empty = counts == 0
            if empty.any() and (~empty).any():
                values[empty] = np.interp(np.nonzero(empty)[0], np.nonzero(~empty)[0], values[~empty])
            profile[name] = values
        profiles[end] = (length, profile)
    return profiles


def legs_patterned(ids, alpha, profiles, tracked):
    """The masks with the legs' read off the start frame's at the same distance down (the body's stay as tracked),
    blended in over a couple of pixels where a leg meets the body."""
    found = leg_map(ids, alpha) if profiles else None
    if found is None:
        return tracked
    legs, distance, front = found
    weight = cv2.GaussianBlur(legs.astype(np.float32), (0, 0), 1.5)
    out = {}
    for name, layer in tracked.items():
        value = layer.copy()
        for end, (length, profile) in profiles.items():
            if name not in profile:
                continue
            side = legs & (front if end == 'front' else ~front)
            steps = np.clip((np.where(side, distance, 0) / length * (LEG_STEPS - 1)).round().astype(int), 0, LEG_STEPS - 1)
            value = np.where(side, weight * profile[name][steps] + (1 - weight) * layer, value)
        out[name] = value
    return out


def irises(rgb, ids, tracked):
    """The irises found again in the frame (the white cat's eyes are orange), each near where it was tracked: shut in a
    blink, never a ring of the iris colour round the eye. The nose stays as tracked."""
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV_FULL).astype(np.float32)
    hue, sat, val = hsv[..., 0] * 360 / 255, hsv[..., 1] / 255, hsv[..., 2] / 255
    orange = (hue > 8) & (hue < 55) & (sat > 0.45) & (val > 0.25) & grown(np.isin(ids, [HEAD, EARS]), 6)
    out = tracked.copy()
    for channel in (0, 1):
        near = grown(tracked[..., channel] > 0.15, 6)
        found = (orange & near).astype(np.float32)
        out[..., channel] = cv2.GaussianBlur(found, (0, 0), 0.8)
    return out


def main():
    film, start_dir, body, view, gait, start, out = sys.argv[1:8]
    breed = float(sys.argv[8]) if len(sys.argv) > 8 else 1.0
    # Tracked at `TRACK_WIDTH`; the stored frames are read again at full size, only those.
    W, H = probe(film)
    f = W / TRACK_WIDTH
    w, h = TRACK_WIDTH, int(round(H / f))
    # Kling's 24 frames a second hold most pictures for two: keep each picture once, with when it was shown.
    shown, small = [], []
    for t, frame in enumerate(decode(film, (w, h))):
        if small and np.abs(frame[::2, ::2].astype(np.int16) - previous[::2, ::2]).mean() < REPEAT:
            continue
        previous = frame
        rgb, alpha = key(frame)
        small.append((rgb.clip(0, 255).astype(np.uint8), alpha.astype(np.float32)))
        shown.append(t)
    # A stride is looked for from the first `SETTLE + 20` pictures, so no more are tracked than its longest end needs.
    low, high = (round(s * 24) for s in PERIOD[gait])
    last = shown[min(len(shown) - 1, SETTLE + 20)] + high
    small = [picture for picture, t in zip(small, shown) if t <= last]
    count = len(small)
    prefix = f'{start_dir}/{view}_{gait}'

    def pass_image(name, mode='L'):
        return np.asarray(Image.open(f'{prefix}_{name}_{start}.png').convert(mode))

    white = pass_image('white', 'RGB')
    if white.shape[:2] != (H, W):
        sys.exit(f'the start frame is {white.shape[1]}x{white.shape[0]}, the film {W}x{H}')
    rgb0, alpha0 = key(cv2.resize(white, (w, h), interpolation=cv2.INTER_AREA))
    start_frame = (rgb0.clip(0, 255).astype(np.uint8), alpha0)
    flow = Flow(w, h)
    grid = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))
    print(f'{body} {view} {gait}: {count} pictures of {len(shown and range(shown[-1] + 1))} frames, {W}x{H}', flush=True)

    # Where each pixel of each frame was in the puppet's frame: chained back frame by frame. On the way, how the
    # cat's lowest pixels move frame to frame (the floor going by under a planted paw).
    maps = [follow(grid, flow(small[0], start_frame), grid)]
    lows = {}
    for t in range(1, count):
        back = flow(small[t], small[t - 1])
        maps.append(follow(maps[t - 1], back, grid))
        maps[t - 1] = (maps[t - 1][0].astype(np.float16), maps[t - 1][1].astype(np.float16))
        alpha = small[t][1] > 0.5
        rows = np.nonzero(alpha.any(axis=1))[0]
        if len(rows):
            band = alpha.copy()
            band[: rows.max() - max(3, h // 70)] = False
            lows[t] = -back[band]

    # The stride: frames alike at its two ends (small greys of the cat), then the one whose ends also map to the same
    # places in the first frame (the same legs where they were, not swapped near for far).
    thumbs = [cv2.resize(cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) * alpha, (240, 135),
                         interpolation=cv2.INTER_AREA) for rgb, alpha in small]
    candidates = []
    for a in range(SETTLE, min(count, SETTLE + 20)):
        for b in range(a + 1, count):
            if low <= shown[b] - shown[a] <= high:
                candidates.append((float(np.abs(thumbs[a] - thumbs[b]).mean()), a, b))
    candidates.sort()
    best = None
    for score, a, b in candidates[:60]:
        inside = (small[a][1] > 0.5) & (small[b][1] > 0.5)
        drift = float(np.hypot(maps[a][0].astype(np.float32) - maps[b][0], maps[a][1].astype(np.float32) - maps[b][1])[inside].mean())
        # The shortest stride that comes round cleanly (a longer loop is two or three strides, fewer frames each).
        total = score + drift * 0.5 + 0.02 * a + 0.03 * (shown[b] - shown[a])
        if best is None or total < best[0]:
            best = (total, a, b, score, drift)
    _, a, b, score, drift = best
    print(f'  stride {a}->{b} ({b - a} frames), likeness {score:.2f}, legs {drift:.1f}px', flush=True)

    # The stride's maps: the chain forward from its start blended with a chain back from its end, tied to its start.
    behind = {b: follow(maps[a], flow(small[b], small[a]), grid)}
    for t in range(b - 1, a - 1, -1):
        behind[t] = follow(behind[t + 1], flow(small[t], small[t + 1]), grid)
    closed = []
    for t in range(a, b):
        k = (t - a) / (b - a)
        closed.append(((1 - k) * maps[t][0].astype(np.float32) + k * behind[t][0],
                       (1 - k) * maps[t][1].astype(np.float32) + k * behind[t][1]))

    if os.environ.get('FILMWALK_DEBUG'):
        np.savez_compressed(os.environ['FILMWALK_DEBUG'], mx=np.stack([m[0] for m in closed]).astype(np.float16),
                            my=np.stack([m[1] for m in closed]).astype(np.float16),
                            alpha=np.stack([small[t][1] for t in range(a, b)]).astype(np.float16),
                            rgb=np.stack([small[t][0] for t in range(a, b)]))
    moves = np.concatenate([lows[t] for t in range(a + 1, b + 1) if t in lows])
    hist, xe, ye = np.histogram2d(moves[:, 0], moves[:, 1], bins=120, range=[[-30, 30], [-30, 30]])
    i, j = np.unravel_index(np.argmax(cv2.GaussianBlur(hist, (5, 5), 1)), hist.shape)
    floor_step = np.array([(xe[i] + xe[i + 1]) / 2, (ye[j] + ye[j + 1]) / 2]) * f
    print(f'  floor {floor_step.round(2)} px a frame', flush=True)

    # The start pose's masks and parts (rendered over black: divided by the cat's coverage, from a pass of every part
    # solid white).
    solid_pass = cv2.resize(pass_image('part-.').astype(np.float32) / 255, (w, h), interpolation=cv2.INTER_AREA)
    coverage = np.maximum(solid_pass, 0.05)
    layers = {}
    for name in MASKS + list(PARTS.values()):
        if os.path.exists(f'{prefix}_{name}_{start}.png'):
            image = cv2.resize(pass_image(name).astype(np.float32) / 255, (w, h), interpolation=cv2.INTER_AREA)
            layers[name] = np.clip(image / coverage, 0, 1)
    features = cv2.resize(pass_image('features', 'RGB').astype(np.float32) / 255, (w, h), interpolation=cv2.INTER_AREA)
    features = np.clip(features / coverage[..., None], 0, 1)
    # The part shades over black are anti-aliased at the edges, where a leg half over the black would read as the head:
    # divided by the coverage, taken where the cat is solid, and each edge pixel takes its nearest solid pixel's.
    raw = cv2.resize(pass_image('ids').astype(np.float32), (w, h), interpolation=cv2.INTER_AREA)
    ids = shades(np.clip(raw / coverage, 0, 255))
    # Where the ears join the head and end, and where the tail joins the body, in the start frame (the render's
    # points pass), followed through the film so the game can put swapped ears and a bobtail on it.
    points_path = f'{prefix}_points_{start}.json'
    start_points = json.load(open(points_path)) if os.path.exists(points_path) else {}
    core = solid_pass > 0.9
    _, nearest = cv2.distanceTransformWithLabels((~core).astype(np.uint8), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
    where = np.zeros(nearest.max() + 1, np.int64)
    cy, cx = np.nonzero(core)
    where[nearest[cy, cx]] = cy * w + cx
    ids = ids.reshape(-1)[where[nearest]].reshape(h, w)
    ids[solid_pass < 0.4] = 0
    profiles = leg_profiles(ids, solid_pass, {name: layers[name] for name in MASKS if name in layers})

    # The stored frames: evenly over the stride, cropped round the cat over the whole stride, scaled.
    # (A longer loop, two strides of a slow gallop, keeps 12 pictures a second of film so it plays no choppier.)
    kept = min(b - a, max(MOST_FRAMES[gait], round((shown[b] - shown[a]) / 2)))
    picks = [a + int(round(k * (b - a) / kept)) for k in range(kept)]
    union = np.zeros((h, w), bool)
    for t in range(a, b):
        union |= small[t][1] > 0.02
    ys, xs = np.nonzero(union)
    pad = 8
    sbox = [max(0, xs.min() - pad), max(0, ys.min() - pad), min(w, xs.max() + pad + 1), min(h, ys.max() + pad + 1)]
    box = [int(round(v * f)) for v in sbox]
    box[2], box[3] = min(W, box[2]), min(H, box[3])
    height_px = RENDER_HEIGHT * breed
    scale = STORE_HEIGHT / RENDER_HEIGHT
    size = (int(round((box[2] - box[0]) * scale)), int(round((box[3] - box[1]) * scale)))
    half = (max(1, size[0] // 2), max(1, size[1] // 2))
    # The CatNode's origin (its feet on the floor) in the film: the floor where the planted paws stand over the stride,
    # and the render's middle moved as far as the cat has drifted across the frame since the start (the camera follows
    # it, not exactly).
    floors = [np.nonzero((small[t][1] > 0.5).any(axis=1))[0].max() + 1 for t in range(a, b)]

    def middle(alpha):
        return np.nonzero(alpha > 0.5)[1].mean()

    drift_x = (np.mean([middle(small[t][1]) for t in range(a, b)]) - middle(alpha0)) * f
    feet = (W / 2 + drift_x, float(np.median(floors)) * f)

    def crop(image, to, small_scale=False):
        x0, y0, x1, y1 = sbox if small_scale else box
        return cv2.resize(image[y0:y1, x0:x1], to, interpolation=cv2.INTER_AREA)

    name = f'cat_{body}_{view}_{gait}'
    for folder in ['films', 'base/films', 'alpha/films'] + [f'masks/{m}/films' for m in MASKS + ['fur', 'features'] + list(PARTS)]:
        os.makedirs(f'{out}/{folder}', exist_ok=True)
    entries = {}
    tracked_points = {}
    full = decode(film, frames=[shown[t] for t in picks])
    for k, t in enumerate(picks):
        rgb, alpha = key(full[k])
        mx, my = closed[t - a]
        rel = f'films/{name}_{k:02d}.png'
        painting = filled(rgb.clip(0, 255).astype(np.uint8), alpha)
        if 'part-_head' in layers:
            painting = without_collar(painting, alpha, cv2.remap(layers['part-_head'], mx, my, cv2.INTER_LINEAR))
        Image.fromarray(crop(painting, size)).save(f'{out}/base/{rel}.jpg', quality=90)
        Image.fromarray(crop((alpha * 255).astype(np.uint8), size)).save(f'{out}/alpha/{rel}')
        save_mask(crop(fur(rgb, alpha), half), f'{out}/masks/fur/{rel}')
        inside = small[t][1] > 0.5
        frame_ids = cv2.remap(ids, mx, my, cv2.INTER_NEAREST)
        tracked = {mask: cv2.remap(layers[mask], mx, my, cv2.INTER_LINEAR) for mask in MASKS if mask in layers}
        tracked = legs_patterned(frame_ids, small[t][1], profiles, tracked)
        present = ['fur']
        for mask, moved in tracked.items():
            if moved[inside].max(initial=0) < 0.02:
                continue
            save_mask(crop(moved, half, True), f'{out}/masks/{mask}/{rel}')
            present.append(mask)
        moved = irises(small[t][0], frame_ids, cv2.remap(features, mx, my, cv2.INTER_LINEAR))
        Image.fromarray((np.round(np.clip(crop(moved, size, True), 0, 1) * 15) * 17).astype(np.uint8)).save(f'{out}/masks/features/{rel}', optimize=True)
        present.append('features')
        for part, layer in PARTS.items():
            if layer in layers:
                moved = cv2.remap(layers[layer], mx, my, cv2.INTER_LINEAR)
                save_mask(crop(moved, half, True), f'{out}/masks/{part}/{rel}')
                present.append(part)
        entries[rel] = {'masks': sorted(present), 'master': [box[2] - box[0], box[3] - box[1]],
                        'scale': scale, 'size': list(size)}
        # Each point where the pixel that came from it is (the nearest), in the frame's master pixels.
        solid = small[t][1] > 0.3
        for point, (px, py) in start_points.items():
            gap = np.where(solid, (mx - px / f) ** 2 + (my - py / f) ** 2, np.inf)
            y, x = np.unravel_index(np.argmin(gap), gap.shape)
            tracked_points.setdefault(point, []).append([float(x * f - box[0]), float(y * f - box[1])])

    index_path = f'{out}/films/films.json'
    index = json.load(open(index_path)) if os.path.exists(index_path) else {'films': {}, 'files': {}}
    index['files'] = {k: v for k, v in index['files'].items() if not k.startswith(f'films/{name}_')}
    index['files'].update(entries)
    index['films'][f'{body}/{view}/{gait}'] = {
        'frames': [f'films/{name}_{k:02d}.png' for k in range(kept)],
        # The cat's standing height (the CatNode's, breed and all) in the frames' master pixels.
        'height': height_px,
        # The CatNode's origin (between its feet on the floor) in the frames' master pixels from the top left.
        'feet': [feet[0] - box[0], feet[1] - box[1]],
        'size': [box[2] - box[0], box[3] - box[1]],
        # How far the floor goes by in a stride (master pixels, x right and y down) and how long a stride is filmed.
        'stride': [float(floor_step[0] * (b - a)), float(floor_step[1] * (b - a))],
        'seconds': (shown[b] - shown[a]) / 24,
        # Points of the start frame followed through the frames (master pixels from the top left, a pair a frame).
        'points': tracked_points,
        # Where the same points were in the start frame, against the frames' master pixels.
        'start': {k: [v[0] - box[0], v[1] - box[1]] for k, v in start_points.items()},
        'source': {'film': os.path.basename(film), 'from': shown[a], 'to': shown[b]},
    }
    json.dump(index, open(index_path, 'w'), indent=1, sort_keys=True)
    print(f'  {kept} frames {size[0]}x{size[1]}, box {box}', flush=True)


if __name__ == '__main__':
    main()
