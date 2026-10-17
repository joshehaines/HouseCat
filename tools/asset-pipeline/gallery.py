"""Build the review page: housecat_art_book.html (thumbnails embedded as WebP data URIs, sounds as MP3)."""
import base64, io, json, os, glob, subprocess, html, shutil, tempfile
from PIL import Image

D = 'deliver/assets'
# Run from a folder holding deliver/assets and cat/ (both the repo's assets), previews/ and gallery.css.
OUT = os.environ.get('HOUSECAT_ART_BOOK', 'housecat_art_book.html')
TOTAL = [0]

def uri(path, max_px=200, q=78, crop=True, jpg=False):
    im = Image.open(path)
    im = im.convert('RGBA')
    if crop and im.getbbox(): im = im.crop(im.getbbox())
    im.thumbnail((max_px, max_px), Image.LANCZOS)
    b = io.BytesIO()
    if jpg:
        im.convert('RGB').save(b, 'JPEG', quality=q); mt = 'image/jpeg'
    else:
        im.save(b, 'WEBP', quality=q, method=6); mt = 'image/webp'
    TOTAL[0] += b.tell()
    return f'data:{mt};base64,' + base64.b64encode(b.getvalue()).decode()

def nice(stem):
    return stem.replace('_', ' ')

def tiles(items, size='m'):
    out = [f'<div class="grid {size}">']
    for src, label in items:
        out.append(f'<figure class="tile"><img loading="lazy" src="{src}" alt="{html.escape(label)}"><figcaption>{html.escape(label)}</figcaption></figure>')
    out.append('</div>')
    return '\n'.join(out)

def section(id_, title, note, body):
    return f'<section id="{id_}"><header class="sh"><h2>{title}</h2><p>{note}</p></header>{body}</section>'

S = []
nav = []

# composites
comp = [('previews/demo_bedroom_midday_lavender_stripe.png', 'Bedroom, midday light'),
        ('previews/demo_bedroom_evening_blush_floral.png', 'Bedroom, evening light'),
        ('previews/widget_composite.png', 'Widget: the cat on the sill, sky behind the glass'),
        ('previews/_dbg_exterior.jpg', 'Exterior: cottage on the coast in summer, sky drawn in code')]
body = '<div class="hero-grid">' + ''.join(
    f'<figure class="shot"><img src="{uri(p, 1100, 82, crop=False, jpg=True)}" alt="{t}"><figcaption>{t}</figcaption></figure>' for p, t in comp) + '</div>'
S.append(section('together', 'How it fits together', 'Built only from the delivered files, the way the app will build them: tiles and a light map for the walls and floor, the terrain through the window, furniture by its reference position, the cat at half sofa height.', body)); nav.append(('together', 'Composites'))

# furniture
ROOMS = [('living', 'Living room'), ('bedroom', 'Bedroom'), ('kitchen', 'Kitchen'), ('garden', 'Garden'), ('study', 'Study'), ('attic', 'Attic'),
         ('pass_housewarming', 'Season pass: Housewarming'), ('pass_midwinter', 'Season pass: Midwinter'), ('pass_firstlight', 'Season pass: First Light'),
         ('housewarming_pack', 'Housewarming pack'), ('founders', "Founders' plaque")]
body = ''
for r, t in ROOMS:
    fs = sorted(f for f in glob.glob(f'{D}/furniture/{r}/*_R.png'))
    items = [(uri(f, 220), nice(os.path.basename(f)[len(f'furn_{r}_'):-6])) for f in fs]
    body += f'<h3>{t} <span class="count">{len(fs)} items × R and L</span></h3>' + tiles(items)
S.append(section('furniture', 'Furniture', 'Shown facing right (R); every item also has an L version for the other wall. Small items carry a suggested scale in the manifest.', body)); nav.append(('furniture', 'Furniture'))

# surfaces
walls = [(uri(f, 160, 75, crop=False), nice(os.path.basename(f)[5:-4])) for f in sorted(glob.glob(f'{D}/rooms/walls/*.png'))]
floors = [(uri(f, 160, 75, crop=False), nice(os.path.basename(f)[6:-4])) for f in sorted(glob.glob(f'{D}/rooms/floors/*.png'))]
wins = [(uri(f, 200), nice(os.path.basename(f)[:-4])) for f in sorted(glob.glob(f'{D}/rooms/windows/*.png')) + sorted(glob.glob(f'{D}/rooms/doors/*.png')) if '_opening' not in f]
strips = [(uri(f, 360), nice(os.path.basename(f)[6:-4])) for f in sorted(glob.glob(f'{D}/rooms/garden_strips/*.png'))]
lms = [(uri(f, 200, crop=False), nice(os.path.basename(f)[3:-4])) for f in sorted(glob.glob(f'{D}/rooms/lightmaps/lm_*.png'))]
body = (f'<h3>Wallpapers <span class="count">{len(walls)}</span></h3>' + tiles(walls, 's sq') +
        f'<h3>Floors <span class="count">{len(floors)}</span></h3>' + tiles(floors, 's sq') +
        f'<h3>Windows and doors <span class="count">{len(wins)}</span></h3>' + tiles(wins) +
        f'<h3>Garden boundaries <span class="count">{len(strips)}</span></h3>' + tiles(strips, 'w') +
        f'<h3>Light maps <span class="count">5 times of day × 3 planes</span></h3>' + tiles(lms, 's sq'))
S.append(section('rooms', 'Walls, floors and light', 'Flat seamless tiles, projected onto the corner room in code and multiplied by the light map for the time of day.', body)); nav.append(('rooms', 'Rooms'))

# world
houses = [(uri(f, 260), nice(os.path.basename(f)[4:-4])) for f in sorted(glob.glob(f'{D}/world/houses/*.png')) if '_glass' not in f]
terr = [(uri(f, 260, crop=False), nice(os.path.basename(f)[5:-4])) for f in sorted(glob.glob(f'{D}/world/terrain/*.png'))]
weather = [(uri(f, 120), nice(os.path.basename(f)[:-4])) for f in sorted(glob.glob(f'{D}/world/weather/*.png'))]
mapimg = uri(f'{D}/world/map/map_painted.png', 1400, 80, crop=False, jpg=True)
body = (f'<h3>Houses <span class="count">8, with door-open and snow versions</span></h3>' + tiles(houses, 'l') +
        f'<h3>Terrain <span class="count">8 biomes × 4 seasons</span></h3>' + tiles(terr, 'l') +
        f'<h3>Weather sprites</h3>' + tiles(weather, 's') +
        f'<h3>World map</h3><figure class="shot wide"><img src="{mapimg}" alt="Painted world map"><figcaption>Real coastlines, painted land and sea; a biome mask decides the terrain under each pin</figcaption></figure>')
S.append(section('world', 'The world outside', 'Houses and terrain are painted at noon; time of day, sky and weather are added in code.', body)); nav.append(('world', 'World'))

# cat
wholes = [(uri(f, 220), nice(os.path.basename(f)[4:-10])) for f in sorted(glob.glob(f'{D}/cat/base/*/cat_*_whole.png'))]
PARTS = ['head', 'ear_far', 'ear_near', 'torso', 'leg_front_near', 'leg_front_far', 'leg_back_near', 'leg_back_far', 'tail_up', 'tail_curl', 'tail_low']
parts = [(uri(f'{D}/cat/base/short_slim/cat_short_slim_tqfront_{p}.png', 160), nice(p)) for p in PARTS]
expr = [(uri(f, 160), nice(os.path.basename(f)[5:-4])) for f in sorted(glob.glob(f'{D}/cat/expressions/*.png'))]
marked = []
for m in ['tuxedo', 'locket', 'socks']:
    for p in ['head', 'torso', 'leg_front_near', 'leg_back_near']:
        marked.append((uri(f'{D}/cat/marked/{m}/cat_short_chunky_tqfront_{p}.png', 150), f'{m} · {nice(p)}'))
extras = [(uri(f, 150), nice(os.path.basename(f)[:-4])) for f in sorted(glob.glob(f'{D}/cat/ears_rounded/*tqfront*.png')) + sorted(glob.glob(f'{D}/cat/whiskers/*_L.png'))]
body = (f'<h3>Four body sets × four views</h3>' + tiles(wholes) +
        f'<h3>Puppet parts <span class="count">short slim, three-quarter front; 11 parts per view</span></h3>' + tiles(parts, 's') +
        f'<h3>Expressions <span class="count">replacement heads</span></h3>' + tiles(expr, 's') +
        f'<h3>Markings <span class="count">full repainted part sets; short chunky shown</span></h3>' + tiles(marked, 's') +
        f'<h3>Rounded ears and whiskers</h3>' + tiles(extras, 's'))
S.append(section('cat', 'The cat', 'A cut-out puppet: parts are posed and animated in code, so every look is a combination of parts, tints and scale.', body)); nav.append(('cat', 'Cat'))

# cat builder: white bases tinted with the reference coat recipe
import presetsheet as PS
from tint import render as _render, load_masks as _lm, COLOURS as _C, EYES as _E, NOSES as _N
def tint_uri(rel, look, pattern=None, white=None, max_px=190):
    base = Image.open(f'{D}/cat/custom/base/{rel}')
    im = _render(base, look, _lm(f'{D}/cat/custom', rel, pattern, white))
    tmp = os.path.join(tempfile.gettempdir(), '_housecat_tint.png'); im.save(tmp)
    return uri(tmp, max_px)
def L(coat, eyes='amber', nose='pink', pc=None, eyes2=None):
    return {'coat': _C[coat], 'pattern_colour': _C[pc] if pc else (0, 0, 0), 'eye_left': _E[eyes],
            'eye_right': _E[eyes2 or eyes], 'nose': _N[nose]}
pre = []
for pr in PS.CB['presets']:
    rel = PS.pose_rel(pr, 'sit_tqfront')
    pre.append((tint_uri(rel, PS.look_of(pr), pr['pattern'], pr['white'], 210), pr['name']))
whites = [(uri(f'{D}/cat/custom/base/whole/cat_{b}_tqfront_whole.png', 170), b) for b in ['persian', 'siamese', 'mainecoon', 'sphynx']]
whites = [(uri(f'{D}/cat/custom/base/poses/cat_{b}_sit_tqfront.png', 170), nice(b)) for b in ['short_slim', 'short_chunky', 'long_slim', 'long_chunky']] + \
         [(u, {'mainecoon': 'Maine Coon', 'persian': 'Persian', 'siamese': 'Siamese', 'sphynx': 'Sphynx'}[b]) for u, b in whites]
pats = [(tint_uri('poses/cat_short_slim_sit_tqfront.png', L('cream', 'green', 'brick', 'seal'), pt), nice(pt)) for pt in
        ['tabby_mackerel', 'tabby_classic', 'spotted', 'tortie', 'colourpoint']]
wm = [(tint_uri('poses/cat_short_chunky_sit_tqfront.png', L('black', 'gold', 'pink'), None, w), nice(w[6:])) for w in
      ['white_mitts', 'white_tuxedo', 'white_bicolour', 'white_van']]
ears = [(tint_uri(f'poses/cat_short_slim_sit_tqfront{v}.png', L('blue', 'copper', 'grey')), lab) for v, lab in
        [('', 'pointed (own)'), ('__rounded', 'rounded'), ('__folded', 'folded'), ('__tufted', 'tufted'), ('__oriental', 'oriental'), ('__bobtail', 'bobtail')]]
eyes = [(tint_uri('expr/head_stdnoear_front_calm.png', L('silver', e, 'brick', eyes2=e2)), f'{e} / {e2}' if e2 != e else e) for e, e2 in
        [('amber', 'amber'), ('green', 'green'), ('blue', 'blue'), ('copper', 'copper'), ('aqua', 'aqua'), ('blue', 'copper')]]
body = (f'<h3>Presets <span class="count">{len(pre)} one-tap starting points, every field editable after; Midnight is the mascot and the default</span></h3>' + tiles(pre, 'm') +
        '<h3>Eight bodies, painted white <span class="count">the coat is applied in code</span></h3>' + tiles(whites, 's') +
        '<h3>Patterns <span class="count">masks over any coat; the pattern colour is free</span></h3>' + tiles(pats, 's') +
        '<h3>White markings <span class="count">combine with any pattern (calico = tortoiseshell + bicolour)</span></h3>' + tiles(wm, 's') +
        '<h3>Ears and tail <span class="count">the four standard bodies; the resting poses have every combination</span></h3>' + tiles(ears, 's') +
        '<h3>Eyes <span class="count">any colour, odd eyes allowed; the nose takes its own colour. Shown on the ear-less expression head: the chosen ears go on as separate parts</span></h3>' + tiles(eyes, 's'))
S.append(section('builder', 'Cat builder', 'Any cat: eight bodies, five ear shapes and a bobtail, any coat colour, five patterns, four white markings, any eye and nose colour. Every sprite is painted white and the look is applied by one shader, checked against the reference renderer in tools/asset-pipeline/tint.py.', body)); nav.append(('builder', 'Builder'))

from extra import POSES
body = ''
for coat, label in [('plain', 'All black'), ('tuxedo', 'Tuxedo'), ('locket', 'Locket'), ('socks', 'Socks')]:
    st = {'plain': 'short_slim', 'tuxedo': 'short_chunky', 'locket': 'long_slim', 'socks': 'long_chunky'}[coat]
    items = [(uri(f'{D}/cat/poses/{coat}/cat_{st}_{p}.png', 170), nice(p)) for p in POSES]
    body += f'<h3>{label} <span class="count">{nice(st)} shown; all four body types painted</span></h3>' + tiles(items, 's')
S.append(section('poses', 'Resting poses', 'Whole paintings for the poses the cat spends most of its time in, for every body type and coat (128 in all). Sit from behind is the widget pose: the cat looking out of the window.', body)); nav.append(('poses', 'Poses'))

icon_main = uri(f'{D}/brand/icon/AppIcon_1024.png', 520, crop=False)
icon_tiles = [(uri(f'{D}/brand/icon/AppIcon_layer1_background.png', 260, crop=False), 'layer 1: background'),
              (uri(f'{D}/brand/icon/AppIcon_layer2_cat.png', 260, crop=False), 'layer 2: cat')] + \
             [(uri(f, 260, crop=False), 'alternate: ' + nice(os.path.basename(f)[12:-9])) for f in sorted(glob.glob(f'{D}/brand/icon/alt_*.png'))]
logos = ''.join(f'<figure class="logo {"dark" if "dark" in f else "light"}"><img src="{uri(f, 640)}" alt="HouseCat logo"><figcaption>{nice(os.path.basename(f)[5:-4])}</figcaption></figure>' for f in sorted(glob.glob(f'{D}/brand/logo/*.png')))
body = (f'<div class="iconrow"><figure class="appicon"><img src="{icon_main}" alt="HouseCat app icon"><figcaption>App icon</figcaption></figure>'
        f'<div class="iconside">{tiles(icon_tiles, "s sq")}</div></div><h3>Logo</h3><div class="logos">{logos}</div>')
S.insert(0, section('brand', 'Icon and logo', 'The app icon comes as a flat 1024 and as two layers for iOS 26, which makes the dark, tinted and clear versions itself. Three alternate concepts are included if you prefer one.', body)); nav.insert(0, ('brand', 'Icon'))

fxs = []
for n in ['fire', 'candle', 'steam', 'smoke', 'water_trickle', 'water_ripple', 'butterfly']:
    sub = 'water' if n.startswith('water') else n
    fxs.append((uri(f'{D}/fx/{sub}/fx_{n}_strip.png', 520, crop=False), nice(n) + ' loop'))
robin = [(uri(f, 150), nice(os.path.basename(f)[9:-4])) for f in sorted(glob.glob(f'{D}/fx/robin/*.png'))]
reac = [(uri(f, 120), nice(os.path.basename(f)[13:-4])) for f in sorted(glob.glob(f'{D}/fx/reactions/*.png'))]
body = (f'<h3>Loops <span class="count">frames side by side; the app plays them at about 10 a second</span></h3>' + tiles(fxs, 'w fx') +
        f'<h3>Garden robin</h3>' + tiles(robin, 's') + f'<h3>Reactions</h3>' + tiles(reac, 's'))
S.append(section('fx', 'Things that move', 'Flames for the fireplaces, candle and lamp (with their attach points worked out), steam, chimney smoke, water, the garden robin and butterfly, and the little icons that float over the cat.', body)); nav.append(('fx', 'Motion'))

outfits = [(uri(f, 200), nice(os.path.basename(f)[7:-12])) for f in sorted(glob.glob(f'{D}/outfits/*_tqfront.png'))]
S.append(section('outfits', 'Outfits', '23 outfits, each in all four views (three-quarter front shown).', tiles(outfits))); nav.append(('outfits', 'Outfits'))

gifts = [(uri(f, 140), nice(os.path.basename(f)[5:-4].split('_', 1)[1])) for f in sorted(glob.glob(f'{D}/gifts/*.png'))]
S.append(section('gifts', 'Gifts', '60 things the cat brings home: toys, treats, oddities, keepsakes and seasonal finds.', tiles(gifts, 's'))); nav.append(('gifts', 'Gifts'))

ui = [(uri(f, 130), nice(os.path.basename(f)[5:-4])) for f in sorted(glob.glob(f'{D}/ui/*.png'))]
S.append(section('ui', 'Icons', '30 interface icons.', tiles(ui, 's'))); nav.append(('ui', 'Icons'))

wid = [(uri(f, 240, crop=False), nice(os.path.basename(f)[7:-4])) for f in sorted(glob.glob(f'{D}/widget/*.png')) if '_glass' not in f]
S.append(section('widget', 'Widget frames', 'The window the widget cat sits in; the glass is transparent so the live sky and weather show through. Square for small and large widgets, wide for medium.', tiles(wid, 'l'))); nav.append(('widget', 'Widget'))

# audio
man = json.load(open(f'{D}/manifest.json'))['files']
rows = []
for f in sorted(glob.glob(f'{D}/audio/*.wav')):
    k = os.path.basename(f)[:-4]
    if shutil.which('ffmpeg'):
        mp3 = subprocess.run(['ffmpeg', '-v', 'error', '-i', f, '-ac', '1', '-b:a', '56k', '-f', 'mp3', '-'], capture_output=True).stdout
        mime = 'audio/mpeg'
    else:  # macOS without ffmpeg: AAC from the built-in afconvert
        out = os.path.join(tempfile.gettempdir(), '_housecat_audio.m4a')
        subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac', '-c', '1', '-b', '56000', f, out], check=True)
        mp3, mime = open(out, 'rb').read(), 'audio/mp4'
    TOTAL[0] += len(mp3)
    meta = man.get(f'audio/{k}.wav', {})
    tag = ('<span class="pill rec">recording</span>' if 'recording' in meta.get('source', '') else '') + ('<span class="pill">loop</span>' if meta.get('loop') else '')
    rows.append(f'<li><div class="an"><span class="mono">{k}</span>{tag}<small>{html.escape(meta.get("note", ""))}</small></div>'
                f'<audio controls preload="none" src="data:{mime};base64,{base64.b64encode(mp3).decode()}"></audio></li>')
S.append(section('audio', 'Sound', 'The cat voices and purr are real recordings (public domain and CC0, credited in the files). Interface sounds and ambience are made in code.', '<ul class="audio">' + ''.join(rows) + '</ul>')); nav.append(('audio', 'Sound'))

EYE = [
 ('Small items came out big', 'Mugs, kettles, slippers, cat beds and other small things were painted at furniture size. Each has a suggested scale in the manifest; they need a look in the room view.'),
 ('Three-quarter back heads show a face', 'The model draws a face on every head. If it reads wrong in the puppet, use the side head or regenerate.'),
 ('Some R/L pairs differ', 'Each orientation was painted separately, so a few pairs differ in small details (the First Light bird box roof, the hamper lining). Mirroring R for L is the fallback.'),
 ('Door-open and snow houses are repaints', 'They are not pixel-aligned with the base house, so cross-fade rather than swap.'),
 ('Tuxedo paws', 'On some views only one front paw is white.'),
 ('Tortoiseshell reads as bold patches', 'The tortie mask came out as large patches rather than fine brindling, so it doubles as the calico patches. Fine for a cartoon cat; a finer brindle could be added later as a sixth pattern.'),
 ('Swap ears on the puppet need a placement pass', 'The swap ears are separate parts, so the code places them where the body\'s own ears sit (from the parts head). Folded and tufted ears may want a small per-view offset, set once by eye in data.'),
]
eye = '<ol class="eye">' + ''.join(f'<li><strong>{a}</strong><span>{b}</span></li>' for a, b in EYE) + '</ol>'

_man = json.load(open(f'{D}/manifest.json'))['files']
NFILES = len(_man); NCAT = sum(1 for k in _man if k.startswith('cat/'))
navhtml = ''.join(f'<a href="#{i}">{t}</a>' for i, t in nav)
CSS = open('gallery.css').read()
page = f"""<title>HouseCat Art Book</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Young+Serif&family=Atkinson+Hyperlegible:wght@400;700&family=JetBrains+Mono:wght@400&display=swap">
<style>{CSS}</style>
<div class="wrap">
<header class="top">
  <p class="eyebrow">HouseCat · delivered 17 October 2026</p>
  <h1>HouseCat Art Book</h1>
  <p class="lede">Every asset for the first build, painted in Higgsfield and cut, keyed and tiled in code. The full-size masters are in <span class="mono">Cat App/housecat/assets</span> on your Mac, with a manifest that tells the code how to use each one.</p>
  <dl class="facts">
    <div><dt>Files</dt><dd>{NFILES:,}</dd></div><div><dt>Furniture</dt><dd>113 items × 2</dd></div><div><dt>Wall &amp; floor tiles</dt><dd>63</dd></div>
    <div><dt>Cat files</dt><dd>{NCAT:,}</dd></div><div><dt>Outfits</dt><dd>23 × 4 views</dd></div><div><dt>Terrains</dt><dd>32</dd></div>
  </dl>
</header>
<nav class="jump" aria-label="Sections">{navhtml}<a href="#eye">Needs your eye</a></nav>
<section id="eye" class="eyebox"><header class="sh"><h2>Needs your eye</h2><p>Nothing here blocks the code build; each is a judgement call for you.</p></header>{eye}</section>
{''.join(S)}
<footer class="foot"><p>Job IDs for every image: <span class="mono">tools/asset-pipeline/pipeline_state.json</span>. Inventory and conventions: <span class="mono">docs/ASSETS.md</span>.</p></footer>
</div>"""
open(OUT, 'w').write(page)
print(round(TOTAL[0] / 1e6, 2), 'MB embedded;', round(os.path.getsize(OUT) / 1e6, 2), 'MB page')
