"""Self-check for Content/*.json. Run:  python3 -I tools/content/check_content.py
Exits non-zero on any error; prints warnings (soft rules) separately."""
import json
import os
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
CONTENT = os.path.join(ROOT, 'Content')
ASSETS = os.path.join(ROOT, 'assets')
FILES = ['lines.json', 'catalogue.json', 'gifts.json', 'outfits.json', 'objectives.json', 'seasons.json',
         'minigames.json']

errors, warnings = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


# ------------------------------------------------------------------ word rules
AMERICAN = [
    r'\bcolors?\b', r'colored', r'favorites?\b', r'favorite', r'\bgray', r'\bmoms?\b',
    r'\bmommy', r'apartments?', r'cookies?\b', r'sweaters?', r'vacation', r'\byards?\b', r'flashlights?',
    r'pajamas?', r'\bcozy', r'cozier', r'\bcenter', r'theater', r'\bhonor', r'neighbor\b', r'neighbors',
    r'behavior', r'\bhumor', r'flavor', r'\bfavor\b', r'\bfavors\b', r'\blabor\b', r'\brumor', r'\bmold\b',
    r'\bpants\b', r'\btrash\b', r'garbage', r'diaper', r'elevator', r'sidewalk', r'\bcandy\b(?! cane)',
    r'\bmath\b', r'faucet', r'\bcloset', r'airplane', r'aluminum', r'\bcatalog\b', r'jewelry', r'\bgotten\b',
    r'traveling', r'traveled', r'canceled', r'\bplow', r'\bcheckers?\b', r'\bmustache', r'\bfall\b(?= (?:is|has|season))',
    r'\b(?:this|last|next|in the|in) fall\b', r'\bvest\b', r'\bstroller', r'\bcell ?phone', r'\bsoccer',
    r'\btoward\b', r'\bpacifier', r'\bpuke\b', r'\bjello\b', r'\bfries\b'
]
IZE_OK = {'size', 'sizes', 'sized', 'prize', 'prizes', 'seize', 'seized', 'capsize', 'maize', 'baize', 'citizen'}
META = [r'\bapps?\b', r'\btap\b', r'\btapping\b', r'\bscreens?\b', r'\bbuttons?\b', r'level up', r'\bclick',
        r'\bnotifications?\b', r'\bdownload', r'\bsubscri', r'\bwidget\b', r'\biphone', r'\bipad']
MONEY = [r'\bmoney\b', r'\bbuy', r'\bbought\b', r'\bpurchas', r'\bshop', r'\bprices?\b', r'\bpay\b', r'\bpaid\b',
         r'[£$€]', r'\bthe pass\b', r'season pass', r'battle pass', r'\bstreak', r'\bbeans\b', r'\bsale\b',
         r'\boffer\b', r'\bpremium\b', r'\bclub\b', r'\bcosts?\b', r'\bcostly', r'\bcheap', r'\bexpensive', r'\bsubscription',
         r'\bunlock', r'\bloot']
BABY = [r'\bwittle\b', r'\bsmol\b', r'\bfurbaby', r'\bkitty\b', r'\bnom\b', r'\bbaby\b', r'\bpeekaboo\b',
        r'\bmeow\b', r'\bpurrfect', r'\bhooman', r'\bheckin', r'\bpawsome', r'\bteh\b']
BANNED_HALLOWEEN = [r'\bwitch', r'\bbroom', r'\bcauldron', r'\bspell\b', r'\bcoven']
EMOJI = re.compile('[\U0001F000-\U0001FAFF☀-➿️‍⬀-⯿]')

WEATHER = [r'\bsun\b', r"\bsun's\b", r'\bsunny', r'\bsunshine', r'\bsunbeams?\b', r'\brain', r'\bstorm',
           r'\bthunder', r'\blightning', r'\bsnow', r'\bfog', r'\bmist\b', r'\bmisty', r'\bwind\b', r'\bwindy', r'\bgust',
           r'\bblustery', r'\bheat\b', r'\bheatwave', r'\bhot\b', r'\bcold\b', r'\bchilly', r'\bclouds?\b', r'\bcloudy',
           r'\bovercast', r'\bdrizzle', r'\bblowy']
SEASON_WORDS = [r'\bspring\b', r'\bsummer', r'\bautumn', r'\bwinter']
TIME_WORDS = [r'\bdawn', r'\bdusk', r'\bmornings?\b', r'\bafternoon', r'\bevenings?\b', r'\bnights?\b',
              r'\btonight', r'\bmidnight', r'\bmidday', r'\bnoon', r'\bsunrise', r'\bsunset', r'\bbreakfast',
              r'\blunch', r'\bdinner', r'\bteatime', r'\bbedtime', r'\bgoodnight']
# context prefixes where each word family may appear
WEATHER_OK = ('weather.', 'behaviour.sunbeam')
SEASON_OK = ('season.',)
TIME_OK = ('time.', 'arrival.late_night', 'arrival.early', 'feed.nag_morning', 'feed.nag_evening',
           'progress.streak_at_risk')

PLACEHOLDER_RE = re.compile(r'\{[a-z]+\}')


def hits(patterns, text):
    return [p for p in patterns if re.search(p, text, re.IGNORECASE)]


def british(text, where):
    for p in AMERICAN:
        if re.search(p, text, re.IGNORECASE):
            err(f"{where}: American spelling/vocabulary /{p}/ in {text!r}")
    for w in re.findall(r"[A-Za-z]+", text):
        lw = w.lower()
        if re.search(r'iz(e|es|ed|ing|ation|ations)$', lw) and lw not in IZE_OK:
            err(f"{where}: -ize spelling {w!r} in {text!r}")
    if EMOJI.search(text):
        err(f"{where}: emoji in {text!r}")


def line_rules(text, where, ctx=None, meta=True, money=True):
    british(text, where)
    if meta:
        for p in hits(META, text):
            err(f"{where}: meta word /{p}/ in {text!r}")
    if money:
        for p in hits(MONEY, text):
            err(f"{where}: money/pass/streak word /{p}/ in {text!r}")
    for p in hits(BABY, text):
        err(f"{where}: baby talk /{p}/ in {text!r}")
    if ctx is not None:
        if not ctx.startswith(WEATHER_OK):
            for p in hits(WEATHER, text):
                err(f"{where}: weather word /{p}/ outside a weather context: {text!r}")
        if not ctx.startswith(SEASON_OK):
            for p in hits(SEASON_WORDS, text):
                err(f"{where}: season word /{p}/ outside a season context: {text!r}")
        if not ctx.startswith(TIME_OK):
            for p in hits(TIME_WORDS, text):
                err(f"{where}: time word /{p}/ outside a time context: {text!r}")
        if ctx == 'event.halloween':
            for p in hits(BANNED_HALLOWEEN, text):
                err(f"{where}: witch reference at Halloween: {text!r}")


def load():
    data = {}
    for f in FILES:
        path = os.path.join(CONTENT, f)
        try:
            with open(path, encoding='utf-8') as fh:
                data[f] = json.load(fh)
        except Exception as e:  # noqa: BLE001
            err(f"{f}: not valid JSON or missing ({e})")
    return data


def unique(ids, where):
    c = Counter(ids)
    for k, n in c.items():
        if n > 1:
            err(f"{where}: duplicate id {k!r} ×{n}")


def keys_exact(obj, keys, where):
    if set(obj) != set(keys):
        missing, extra = set(keys) - set(obj), set(obj) - set(keys)
        if missing:
            err(f"{where}: missing keys {sorted(missing)}")
        if extra:
            warn(f"{where}: extra keys {sorted(extra)} (ignored by Codable)")


def sprite_ok(path, manifest, where):
    if path not in manifest:
        err(f"{where}: sprite {path!r} not in manifest")
    if not os.path.isfile(os.path.join(ASSETS, path)):
        err(f"{where}: sprite {path!r} not on disk")


# ------------------------------------------------------------------ lines
def check_lines(d):
    f = 'lines.json'
    keys_exact(d, ['version', 'placeholders', 'contexts', 'lines'], f)
    ph = set(d['placeholders'])
    if ph != {"{cat}", "{item}", "{weather}", "{temp}", "{place}", "{streak}", "{sitter}", "{together}"}:
        err(f"{f}: placeholder list differs from the brief")
    ctx_ids = [c['id'] for c in d['contexts']]
    unique(ctx_ids, f + ' contexts')
    for c in d['contexts']:
        keys_exact(c, ['id', 'condition'], f"{f} context {c.get('id')}")
        if not re.fullmatch(r'[a-z]+\.[a-z0-9_]+', c['id']):
            err(f"{f}: context id {c['id']!r} is not group.name snake_case")
    pairs = Counter()
    seen_variants = Counter()
    per_ctx = defaultdict(set)
    total = 0
    for e in d['lines']:
        where = f"{f} {e.get('context')}/{e.get('personality')}"
        keys_exact(e, ['context', 'personality', 'variants', 'meow'], where)
        if e['context'] not in ctx_ids:
            err(f"{where}: unknown context")
        if e['personality'] not in ('aloof', 'velcro', 'gremlin', 'loaf'):
            err(f"{where}: bad personality")
        if e['meow'] not in ('short', 'long', 'chirp', 'trill', 'purr', 'grumble', 'silent'):
            err(f"{where}: bad meow {e['meow']!r}")
        pairs[(e['context'], e['personality'])] += 1
        per_ctx[e['context']].add(e['personality'])
        want = 10 if e['context'] == 'behaviour.idle' else 3
        if len(e['variants']) != want:
            err(f"{where}: {len(e['variants'])} variants, want {want}")
        for v in e['variants']:
            total += 1
            seen_variants[v] += 1
            if len(v) > 70:
                err(f"{where}: {len(v)} chars > 70: {v!r}")
            used = PLACEHOLDER_RE.findall(v)
            for p in used:
                if p not in ph:
                    err(f"{where}: unknown placeholder {p} in {v!r}")
            if used and len(v) > 60:
                warn(f"{where}: {len(v)} chars with a placeholder (aim <= 60): {v!r}")
            if v != v.strip() or '  ' in v:
                err(f"{where}: stray whitespace in {v!r}")
            line_rules(v, where, ctx=e['context'])
            if e['personality'] == 'aloof' and v.count('!') > 0:
                warn(f"{where}: Aloof exclamation mark: {v!r}")
    for k, n in pairs.items():
        if n > 1:
            err(f"{f}: {k} appears {n} times")
    for c in ctx_ids:
        if per_ctx[c] != {'aloof', 'velcro', 'gremlin', 'loaf'}:
            err(f"{f}: context {c} missing {sorted({'aloof', 'velcro', 'gremlin', 'loaf'} - per_ctx[c])}")
    for v, n in seen_variants.items():
        if n > 1:
            err(f"{f}: line used {n} times: {v!r}")
    # every CONTENT.md context group is present
    need = ['arrival.first_ever', 'arrival.first_of_day', 'arrival.second_visit', 'arrival.late_night', 'arrival.early',
            'arrival.from_mac', 'arrival.from_watch', 'missed.one_day', 'missed.few_days', 'missed.week_plus',
            'missed.sulky', 'missed.thawing', 'missed.fine', 'feed.fed', 'feed.already_fed', 'feed.nag_morning',
            'feed.nag_evening', 'feed.by_sitter', 'feed.by_coowner', 'pet.first', 'pet.repeat', 'pet.too_many',
            'play.start', 'play.win', 'play.lose', 'play.used_up', 'gift.common', 'gift.uncommon', 'gift.rare',
            'gift.legendary', 'gift.none_missed_yesterday', 'weather.sun', 'weather.cloud', 'weather.rain',
            'weather.storm', 'weather.snow', 'weather.fog', 'weather.wind', 'weather.heat', 'weather.sunday_summary',
            'season.spring', 'season.summer', 'season.autumn', 'season.winter', 'time.dawn', 'time.day', 'time.dusk',
            'time.night', 'home.placed_liked', 'home.placed_none', 'home.removed', 'home.room_unlocked',
            'home.wallpaper_changed', 'home.empty_room', 'progress.level_up', 'progress.trust_wary',
            'progress.trust_curious', 'progress.trust_comfortable', 'progress.trust_bonded', 'progress.trust_devoted',
            'progress.trust_soulmate', 'progress.streak_7', 'progress.streak_30', 'progress.streak_100',
            'progress.streak_365', 'progress.streak_at_risk', 'progress.pause_on', 'progress.pause_off',
            'together.monthly', 'together.yearly', 'together.hundred_days', 'together.grown_up',
            'together.share_caption', 'social.sitter_present', 'social.coowner_arrived', 'social.group_visitor',
            'social.paw_print_received', 'social.gift_received', 'social.gift_sent', 'stray.appears',
            'stray.reaction', 'stray.leaves', 'stray.adopted', 'objective.daily_done', 'objective.weekly_done',
            'objective.achievement', 'pass.tier_claimed', 'pass.season_ending', 'pass.new_season', 'outfit.on_hat',
            'outfit.on_scarf', 'outfit.on_glasses', 'outfit.on_jumper', 'outfit.off', 'health.steps', 'health.sleep',
            'health.workout', 'behaviour.nap_start', 'behaviour.nap_end', 'behaviour.window_watch',
            'behaviour.sunbeam', 'behaviour.zoomies', 'behaviour.scratching', 'behaviour.hiding', 'behaviour.idle',
            'event.black_cat_day', 'event.halloween', 'event.christmas', 'event.new_year', 'event.housewarming']
    for n in need:
        if n not in ctx_ids:
            err(f"{f}: missing context {n}")
    return len(ctx_ids), len(d['lines']), total


# ------------------------------------------------------------------ catalogue
ROOMS6 = ('living', 'bedroom', 'kitchen', 'garden', 'study', 'attic')
AFF = {'sit', 'sleep', 'hide', 'perch', 'scratch', 'eat', 'watch', 'bat', 'none'}
POSES = {None, 'sit_side', 'sit_tqfront', 'sit_front', 'sit_back', 'loaf_side', 'loaf_tqfront', 'sleep_curl',
         'stretch_side'}
FX_NAMES = {'fire', 'steam', 'candle', 'smoke', 'water_trickle', 'water_ripple', 'butterfly', 'robin', 'reactions'}


def check_catalogue(d, manifest, outfits):
    f = 'catalogue.json'
    keys_exact(d, ['version', 'sets', 'items', 'surfaces', 'excluded'], f)
    unique([s['id'] for s in d['sets']] + [i['id'] for i in d['items']] + [s['id'] for s in d['surfaces']], f)
    items = {i['id']: i for i in d['items']}
    surfaces = {s['id']: s for s in d['surfaces']}
    sets = {s['id']: s for s in d['sets']}
    outfit_by = {o['id']: o for o in outfits['outfits']}

    # manifest coverage
    pairs = {(v['room'], v['item']) for v in manifest.values() if v.get('class') == 'furniture'}
    # Items left out on purpose (alcohol; Josh, 18 Oct) must say why.
    excluded = {e['id'] for e in d['excluded'] if e.get('reason')}
    want_ids = {f"{r}_{i}" for r, i in pairs} - excluded
    if set(items) != want_ids:
        err(f"{f}: items differ from manifest furniture pairs: {sorted(set(items) ^ want_ids)}")

    item_keys = ['id', 'name', 'set', 'room', 'footprint', 'layer', 'decal', 'affordances', 'capacity', 'motion',
                 'pool', 'level', 'beans', 'sku', 'description', 'catPose', 'sprites', 'suggestedScale', 'fx']
    for i in d['items']:
        w = f"{f} item {i['id']}"
        keys_exact(i, item_keys, w)
        mv = [v for k, v in manifest.items() if v.get('class') == 'furniture' and f"{v['room']}_{v['item']}" == i['id']]
        if mv and i['room'] != mv[0]['room']:
            err(f"{w}: room {i['room']!r} != manifest {mv[0]['room']!r}")
        if len(i['name']) > 24:
            err(f"{w}: name over 24 chars")
        if len(i['description']) > 90:
            err(f"{w}: description {len(i['description'])} chars > 90")
        line_rules(i['description'], w + ' description', money=False, meta=True)
        british(i['name'], w + ' name')
        fp = i['footprint']
        if set(fp) != {'w', 'd'} or not all(isinstance(fp[k], int) and 1 <= fp[k] <= 3 for k in fp):
            err(f"{w}: bad footprint {fp}")
        if i['layer'] not in ('floor', 'wall'):
            err(f"{w}: bad layer")
        if not isinstance(i['decal'], bool) or (i['decal'] and i['layer'] != 'floor'):
            err(f"{w}: bad decal")
        aff = i['affordances']
        if not aff or not set(aff) <= AFF or ('none' in aff and aff != ['none']):
            err(f"{w}: bad affordances {aff}")
        if not isinstance(i['capacity'], int) or i['capacity'] < 0 or ((i['capacity'] == 0) != (aff == ['none'])):
            err(f"{w}: bad capacity {i['capacity']} for {aff}")
        m = i['motion']
        t = m.get('type')
        if t == 'static':
            keys_exact(m, ['type'], w + ' motion')
        elif t in ('sway', 'bob', 'spin', 'glow'):
            keys_exact(m, ['type', 'pivot', 'period'], w + ' motion')
            if not (len(m['pivot']) == 2 and all(0 <= x <= 1 for x in m['pivot']) and m['period'] > 0):
                err(f"{w}: bad motion {m}")
        elif t == 'frames':
            keys_exact(m, ['type', 'fx', 'frames', 'period'], w + ' motion')
            if m['fx'] not in FX_NAMES or m['frames'] < 1 or m['period'] <= 0:
                err(f"{w}: bad frames motion {m}")
        else:
            err(f"{w}: bad motion type {t!r}")
        if i['catPose'] not in POSES:
            err(f"{w}: bad catPose {i['catPose']!r}")
        if i['catPose'] is not None and aff == ['none']:
            err(f"{w}: catPose on an item with no affordance")
        if not isinstance(i['level'], int) or i['level'] < 1:
            err(f"{w}: bad level")
        pool = i['pool']
        b, s = i['beans'], i['sku']
        if pool == 'beans':
            if not isinstance(b, int) or s is not None:
                err(f"{w}: beans pool needs beans and no sku")
        elif pool in ('set', 'housewarming', 'founders'):
            if s is None or b is not None:
                err(f"{w}: paid pool needs sku and no beans")
        elif pool in ('free', 'pass-free', 'pass-paid'):
            if s is not None or b is not None:
                err(f"{w}: {pool} has beans or sku")
        else:
            err(f"{w}: bad pool {pool!r}")
        if set(i['sprites']) != {'R', 'L'}:
            err(f"{w}: sprites need R and L")
        for face, p in i['sprites'].items():
            sprite_ok(p, manifest, w)
            mv_ = manifest.get(p, {})
            if mv_.get('facing') != face or mv_.get('variant') or p.endswith('_painted.png'):
                err(f"{w}: sprite {face} {p} is not the primary {face} sprite")
        mR = manifest.get(i['sprites']['R'], {})
        if i['suggestedScale'] != mR.get('suggested_scale'):
            err(f"{w}: suggestedScale {i['suggestedScale']} != manifest {mR.get('suggested_scale')}")
        mfx = mR.get('motion_fx')
        if mfx:
            if not i['fx'] or len(i['fx'].get('anchor') or []) != 2:
                err(f"{w}: manifest has motion_fx but fx is {i['fx']}")
            elif mfx.get('anchor') is not None and i['fx']['anchor'] != mfx['anchor']:
                err(f"{w}: fx anchor {i['fx']['anchor']} != manifest {mfx['anchor']}")
        if i['fx'] is not None and i['fx'].get('fx') not in FX_NAMES:
            err(f"{w}: unknown fx {i['fx'].get('fx')!r}")
        if t == 'frames' and m['fx'] in ('fire', 'candle', 'steam', 'water_trickle', 'water_ripple') and not i['fx']:
            warn(f"{w}: frames motion {m['fx']} has no fx anchor")

    # counts and pools
    room_items = [i for i in d['items'] if i['room'] in ROOMS6]
    pass_items = [i for i in d['items'] if i['room'].startswith('pass_')]
    pack = [i for i in d['items'] if i['room'] == 'housewarming_pack']
    founders = [i for i in d['items'] if i['room'] == 'founders']
    expect(len(room_items), 80, 'room items')
    expect(len(pass_items), 23, 'season-pass items (mulled wine excluded)')
    expect(len(pack), 5, 'Housewarming pack items (champagne excluded)')
    expect(len(founders), 3, "founders' plaque finishes")
    pc = Counter(i['pool'] for i in room_items)
    expect(pc['free'], 8, 'free room items')
    expect(pc['beans'], 30, 'Bean room items')
    expect(pc['set'], 42, 'set room items')
    expect(len(pc), 3, 'pools among room items')
    lv = Counter(i['level'] for i in room_items if i['pool'] == 'beans')
    expect(dict(lv), {1: 8, 3: 8, 6: 8, 9: 6}, 'Bean tiers')
    for i in room_items:
        if i['pool'] == 'beans':
            lo, hi = (30, 60) if i['level'] == 1 else (30, 600)  # 30-Bean floor (Josh, 18 Oct)
            if not lo <= i['beans'] <= hi:
                err(f"{f}: {i['id']} costs {i['beans']} Beans, outside {lo}-{hi} for level {i['level']}")
    cheapest = sorted(i['beans'] for i in room_items if i['pool'] == 'beans' and i['level'] == 1)
    if sum(cheapest[:3]) > 150 or sum(cheapest[:5]) <= 150:
        err(f"{f}: 150-Bean allowance should buy 3-4 level-1 items (prices {cheapest})")
    if items.get('kitchen_bowl', {}).get('pool') != 'free':
        err(f"{f}: kitchen_bowl must be free")
    for i in pass_items:
        if i['pool'] not in ('pass-free', 'pass-paid') or i['set'] != i['room']:
            err(f"{f}: {i['id']} pass item pool/set wrong")
    for rm in ('pass_housewarming', 'pass_midwinter', 'pass_firstlight'):
        c = Counter(i['pool'] for i in pass_items if i['room'] == rm)
        want = {'pass-free': 3, 'pass-paid': 4 if rm == 'pass_midwinter' else 5}
        expect(dict(c), want, f'{rm} pools')
    for i in pack:
        if i['pool'] != 'housewarming' or i['sku'] != 'housecat.season.housewarming':
            err(f"{f}: {i['id']} pack pool/sku wrong")
    for i in founders:
        if i['pool'] != 'founders' or i['sku'] != 'housecat.founders' or i['layer'] != 'wall':
            err(f"{f}: {i['id']} founders pool/sku/layer wrong")

    # sets
    expect(len(sets), 6, 'paid sets')
    expect(sorted(s['name'] for s in d['sets']),
           sorted(["Rainy London", "Cottagecore", "Midnight", "Cosy Study", "Riviera", "Cabin"]), 'set names')
    set_outfits = []
    for s in d['sets']:
        w = f"{f} set {s['id']}"
        keys_exact(s, ['id', 'name', 'sku', 'bundleSku', 'bundleBeans', 'outfit', 'wallpaper', 'floor'], w)
        if s['sku'] != f"housecat.set.{s['id']}" or s['bundleSku'] != f"housecat.bundle.{s['id']}":
            err(f"{w}: sku pattern")
        members = [i for i in room_items if i['set'] == s['id']]
        expect(len(members), 7, f"{s['id']} items")
        for i in members:
            if i['pool'] != 'set' or i['sku'] != s['sku']:
                err(f"{w}: {i['id']} pool/sku mismatch")
        o = outfit_by.get(s['outfit'])
        if not o or o['pool'] != 'paid':
            err(f"{w}: outfit {s['outfit']!r} is not a paid outfit")
        set_outfits.append(s['outfit'])
        for key, kind in (('wallpaper', 'wall'), ('floor', 'floor')):
            sf = surfaces.get(s[key])
            if not sf or sf['kind'] != kind or sf['pool'] != 'set' or sf['set'] != s['id']:
                err(f"{w}: {key} {s[key]!r} does not resolve to a set {kind}")
    unique(set_outfits, f + ' set outfits')
    for i in room_items:
        if i['pool'] == 'set' and i['set'] not in sets:
            err(f"{f}: {i['id']} set {i['set']!r} unknown")
        if i['pool'] != 'set' and i['set'] is not None:
            err(f"{f}: {i['id']} has a set but pool {i['pool']}")

    # surfaces
    msurf = {k for k, v in manifest.items() if v.get('class') in ('rooms/walls', 'rooms/floors')}
    if {s['sprite'] for s in d['surfaces']} != msurf:
        err(f"{f}: surfaces differ from manifest tiles")
    for s in d['surfaces']:
        w = f"{f} surface {s['id']}"
        keys_exact(s, ['id', 'kind', 'room', 'name', 'pool', 'beans', 'set', 'sprite'], w)
        sprite_ok(s['sprite'], manifest, w)
        if os.path.basename(s['sprite'])[:-4] != s['id']:
            err(f"{w}: id does not match sprite")
        if len(s['name']) > 24:
            err(f"{w}: name over 24")
        british(s['name'], w)
        if s['pool'] == 'beans' and not isinstance(s['beans'], int):
            err(f"{w}: beans pool without a price")
        if s['pool'] != 'beans' and s['beans'] is not None:
            err(f"{w}: price on a {s['pool']} surface")
        if s['pool'] not in ('free', 'beans', 'set', 'pass-paid', 'housewarming'):
            err(f"{w}: bad pool")
    for rm in ROOMS6:
        for kind in ('wall', 'floor'):
            c = Counter(s['pool'] for s in d['surfaces'] if s['room'] == rm and s['kind'] == kind)
            if c['free'] != 3:
                err(f"{f}: {rm} {kind}s have {c['free']} free, want 3")
        n = sum(1 for s in d['surfaces'] if s['room'] == rm)
        if n < 5:
            err(f"{f}: {rm} has only {n} surfaces")
        for kind in ('wall', 'floor'):
            n = sum(1 for s in d['surfaces'] if s['room'] == rm and s['kind'] == kind)
            if n < 5:
                warn(f"{f}: {rm} has {n} {kind}s (SPEC says five of each); the manifest has no more")
    return items, surfaces


def expect(got, want, what):
    if got != want:
        err(f"count {what}: got {got}, want {want}")


# ------------------------------------------------------------------ gifts / outfits
def check_gifts(d, manifest):
    f = 'gifts.json'
    keys_exact(d, ['version', 'gifts'], f)
    unique([g['id'] for g in d['gifts']], f)
    mg = {k for k, v in manifest.items() if v.get('class') == 'gifts'}
    if {g['sprite'] for g in d['gifts']} != mg:
        err(f"{f}: gifts differ from the manifest")
    expect(len(d['gifts']), 60, 'gifts')
    expect(dict(Counter(g['rarity'] for g in d['gifts'])), {'common': 30, 'uncommon': 17, 'rare': 9, 'legendary': 4},
           'gift rarities')
    expect(dict(Counter(g['category'] for g in d['gifts'])),
           {'toys': 12, 'treats': 12, 'oddities': 12, 'keepsakes': 12, 'seasonal': 12}, 'gift categories')
    months_covered = set()
    for g in d['gifts']:
        w = f"{f} {g['id']}"
        keys_exact(g, ['id', 'name', 'category', 'rarity', 'description', 'months', 'sprite'], w)
        sprite_ok(g['sprite'], manifest, w)
        if manifest.get(g['sprite'], {}).get('category') != g['category']:
            err(f"{w}: category differs from the manifest")
        if g['id'] != os.path.basename(g['sprite'])[len('gift_'):-4]:
            err(f"{w}: id does not match sprite")
        if len(g['name']) > 24:
            err(f"{w}: name over 24")
        if len(g['description']) > 90:
            err(f"{w}: description over 90")
        line_rules(g['description'], w, money=False)
        british(g['name'], w)
        if g['category'] == 'seasonal':
            if not g['months'] or not all(isinstance(m, int) and 1 <= m <= 12 for m in g['months']):
                err(f"{w}: seasonal gift needs months 1-12")
            months_covered |= set(g['months'])
        elif g['months']:
            err(f"{w}: months on a non-seasonal gift")
    if months_covered != set(range(1, 13)):
        warn(f"{f}: no seasonal gift in months {sorted(set(range(1, 13)) - months_covered)}")


def check_outfits(d, manifest):
    f = 'outfits.json'
    keys_exact(d, ['version', 'outfits'], f)
    unique([o['id'] for o in d['outfits']], f)
    # The body garments' paintings for each body and pose (outfits/body/) are drawn by GarmentPlacement, not listed here.
    mo = {k for k, v in manifest.items() if v.get('class') == 'outfits' and not k.startswith('outfits/body/')}
    used = set()
    expect(len(d['outfits']), 35, 'outfits (23, and 12 more on 18 Oct)')
    # No founders' pack any more; the small crown is the Housewarming pass's (CLAUDE.md, 18 Oct).
    expect(dict(Counter(o['pool'] for o in d['outfits'])),
           {'paid': 25, 'earned': 4, 'pass-paid': 3, 'pass-free': 3}, 'outfit pools')
    expect(sorted(o['earnedBy'] for o in d['outfits'] if o['pool'] == 'earned'),
           sorted(['streak_30', 'streak_100', 'referral', 'launch_event']), 'earnedBy')
    for o in d['outfits']:
        w = f"{f} {o['id']}"
        keys_exact(o, ['id', 'name', 'slot', 'views', 'pool', 'sku', 'earnedBy', 'months', 'sprites'], w)
        if o['slot'] not in ('head', 'neck', 'body'):
            err(f"{w}: bad slot")
        if len(o['name']) > 24:
            err(f"{w}: name over 24")
        british(o['name'], w)
        if 'red' in o['name'].lower() and o['slot'] == 'neck':
            err(f"{w}: red neckwear")
        if o['pool'] == 'paid' and o['sku'] != f"housecat.outfit.{o['id']}":
            err(f"{w}: paid outfit sku")
        if o['pool'] == 'founders' and o['sku'] != 'housecat.founders':
            err(f"{w}: founders sku")
        if o['pool'] in ('earned', 'pass-free', 'pass-paid') and o['sku'] is not None:
            err(f"{w}: sku on a non-sold outfit")
        if (o['pool'] == 'earned') != (o['earnedBy'] is not None):
            err(f"{w}: earnedBy mismatch")
        if set(o['views']) != set(o['sprites']):
            err(f"{w}: views/sprites mismatch")
        for view, p in o['sprites'].items():
            sprite_ok(p, manifest, w)
            if p != f"outfits/outfit_{o['id']}_{view}.png":
                err(f"{w}: sprite {p} does not match id/view")
            used.add(p)
        if not all(isinstance(m, int) and 1 <= m <= 12 for m in o['months']):
            err(f"{w}: bad months")
    if used != mo:
        err(f"{f}: outfit sprites differ from manifest: {sorted(mo ^ used)[:5]}")
    # Each body garment is painted over every body's resting poses and torso views: the same set for each.
    worn = defaultdict(set)
    for p in (k for k, v in manifest.items() if v.get('class') == 'outfits' and k.startswith('outfits/body/')):
        name = os.path.basename(p)[len('outfit_'):-len('.png')]
        owner = [o['id'] for o in d['outfits'] if o['slot'] == 'body' and name.startswith(o['id'] + '_')]
        if len(owner) != 1:
            err(f"{f}: body garment painting {p} names no body outfit")
            continue
        worn[owner[0]].add(name[len(owner[0]) + 1:])
        if not os.path.isfile(os.path.join(ASSETS, p)):
            err(f"{f}: body garment painting {p!r} not on disk")
    body = [o['id'] for o in d['outfits'] if o['slot'] == 'body']
    every = set().union(*worn.values()) if worn else set()
    for oid in body:
        if worn[oid] != every or not every:
            err(f"{f}: {oid} is not painted for {sorted(every - worn[oid])[:5] or 'any body'}")
    by = {o['id']: o for o in d['outfits']}
    if by.get('santahat', {}).get('months') != [12]:
        err(f"{f}: Santa hat should be December")
    for oid in ('pumpkinhat', 'skeleton'):
        if by.get(oid, {}).get('months') != [10]:
            err(f"{f}: {oid} should be October")
    if by.get('crown', {}).get('pool') != 'pass-paid':
        err(f"{f}: the small crown is the Housewarming pass's top prize (pass-paid)")
    return by


# ------------------------------------------------------------------ objectives
PERIOD = {'pet', 'feed', 'feed_before_9', 'play_minigame', 'win_minigame', 'three_star_minigame', 'place_item',
          'widget_visit', 'tap_window', 'nap', 'mac_visit', 'watch_visit', 'visit_day', 'find_gift', 'open_room',
          'send_paw_print', 'change_surface', 'buy_item_beans', 'wear_outfit'}
LIFETIME = {'total_feeds', 'total_pets', 'total_gifts', 'distinct_gifts', 'legendary_gifts', 'items_owned',
            'rooms_opened', 'rooms_visited', 'longest_streak', 'level', 'trust_tier', 'minigame_wins',
            'three_star_games', 'naps', 'season_changed', 'home_moved', 'pass_tiers_claimed', 'seasons_completed',
            'paw_prints_sent', 'groups_joined', 'sitting_days', 'gifts_sent', 'outfits_worn', 'surfaces_changed',
            'cats_adopted', 'sunday_cards', 'together_days',
            # the path's and the newer ladders' (19 Oct)
            'games_played', 'days_visited', 'care_days', 'rooms_furnished', 'cat_used_items', 'homes_visited'}
# Lifetime too, but they count in the room or the screen a path step names: never an achievement's.
PATH_ONLY = {'room_pieces', 'screen_seen'}
SCREENS = {'map'}   # what the app records as seen (GameSession.saw)
PAID_METRICS = {'gifts_sent', 'cats_adopted'}   # only reachable by paying: never an objective
OBJECTIVE_BANNED = [r'\bapps?\b', r'\btap\b', r'\bscreens?\b', r'\bbuttons?\b', r'level up now', r'\bbuy',
                    r'\bpurchas', r'\bshop', r'\bmoney', r'[£$€]', r'\bpay']
# Ladders of three where sensible; level 30 is home_level's fourth rung, the other cats' homes have two (3/7).
LADDER_RUNGS = {'home_level': 4, 'explore_homes': 2}


def check_objectives(d):
    f = 'objectives.json'
    keys_exact(d, ['version', 'daily', 'weekly', 'achievements', 'path'], f)
    all_ = d['daily'] + d['weekly'] + d['achievements']
    unique([o['id'] for o in all_], f)
    unique([o['name'] for o in all_], f + ' names')
    expect(len(d['daily']), 20, 'daily objectives')
    expect(len(d['weekly']), 12, 'weekly objectives')
    expect(len(d['achievements']), 81, 'achievements (60, and 21 more on 19 Oct)')
    groups = Counter(o['id'].split('_')[0] for o in d['achievements'])
    expect(dict(groups), {'care': 15, 'home': 16, 'social': 8, 'streak': 9, 'collection': 11, 'explore': 8,
                          'play': 6, 'seasons': 8}, 'achievement groups')
    for kind, lst in (('daily', d['daily']), ('weekly', d['weekly']), ('achievement', d['achievements'])):
        for o in lst:
            w = f"{f} {o['id']}"
            keys_exact(o, ['id', 'name', 'text', 'metric', 'target', 'beans', 'passPoints', 'ladder'], w)
            if len(o['name']) > 24:
                err(f"{w}: name over 24")
            if len(o['text']) > 70:
                err(f"{w}: text over 70")
            line_rules(o['text'], w, money=False, meta=False)
            for p in hits(OBJECTIVE_BANNED, o['text'] + ' ' + o['name']):
                err(f"{w}: banned word /{p}/")
            british(o['name'], w)
            if not isinstance(o['target'], int) or o['target'] < 1:
                err(f"{w}: bad target")
            if kind in ('daily', 'weekly'):
                if o['metric'] not in PERIOD:
                    err(f"{w}: metric {o['metric']!r} not a period metric")
                if kind == 'daily' and o['metric'] == 'visit_day':
                    err(f"{w}: visit_day is weekly only")
                lo, hi, pp = (10, 20, 5) if kind == 'daily' else (50, 100, 20)
                if not lo <= o['beans'] <= hi or o['passPoints'] != pp:
                    err(f"{w}: reward {o['beans']}/{o['passPoints']} outside {lo}-{hi} + {pp}")
                if o['ladder'] is not None:
                    err(f"{w}: ladder on a {kind} objective")
            else:
                if o['metric'] not in LIFETIME:
                    err(f"{w}: metric {o['metric']!r} not a lifetime metric")
                if not 25 <= o['beans'] <= 500 or o['passPoints'] != 0:
                    err(f"{w}: reward {o['beans']}/{o['passPoints']}")
            if o['metric'] in PAID_METRICS:
                err(f"{w}: metric {o['metric']} can only be reached by paying")
    ladders = Counter(o['ladder'] for o in d['achievements'] if o['ladder'])
    for lad, n in ladders.items():
        if n != LADDER_RUNGS.get(lad, 3):
            err(f"{f}: ladder {lad} has {n} rungs, want {LADDER_RUNGS.get(lad, 3)}")
        rungs = [o for o in d['achievements'] if o['ladder'] == lad]
        if len({o['metric'] for o in rungs}) != 1:
            err(f"{f}: ladder {lad} mixes metrics")
        if [o['target'] for o in rungs] != sorted(o['target'] for o in rungs) or \
                [o['beans'] for o in rungs] != sorted(o['beans'] for o in rungs):
            err(f"{f}: ladder {lad} is not ascending")
    for o in d['achievements']:
        if o['metric'] == 'trust_tier' and not 1 <= o['target'] <= 6:
            err(f"{f}: {o['id']} trust tier out of range")
        if o['metric'] == 'rooms_opened' and o['target'] > 6:
            err(f"{f}: {o['id']} more rooms than exist")


def keys_within(obj, keys, optional, where):
    """keys_exact, with keys a decoder may go without (Codable optionals)."""
    missing, extra = set(keys) - set(obj), set(obj) - set(keys) - set(optional)
    if missing:
        err(f"{where}: missing keys {sorted(missing)}")
    if extra:
        warn(f"{where}: extra keys {sorted(extra)} (ignored by Codable)")


def path_words(text, limit, where):
    if len(text) > limit:
        err(f"{where}: {len(text)} chars > {limit}: {text!r}")
    for p in PLACEHOLDER_RE.findall(text):
        if p != '{cat}':
            err(f"{where}: placeholder {p} (the path has only {{cat}}) in {text!r}")
    line_rules(text, where, money=False, meta=False)
    for p in hits(OBJECTIVE_BANNED, text):
        err(f"{where}: banned word /{p}/ in {text!r}")


def check_path(d, items, outfits):
    """The path (CONTENT.md §5): three chapters of steps in order, each counted by a metric the game keeps and paying
    Beans, XP and a little pass XP; a chapter pays its own reward. Its outfits are never a season's."""
    f = 'objectives.json path'
    path = d.get('path', [])
    expect([c.get('name') for c in path], ['Moving in', 'Getting to know you', 'Making it home'], 'path chapters')
    steps = [s for c in path for s in c.get('steps', [])]
    ids = [c['id'] for c in path] + [s['id'] for s in steps]
    unique(ids, f)
    clash = set(ids) & {o['id'] for o in d['daily'] + d['weekly'] + d['achievements']}
    if clash:
        err(f"{f}: ids also an objective's: {sorted(clash)}")

    def gives(o, w):
        if o.get('outfit') is not None:
            ov = outfits.get(o['outfit'])
            if not ov:
                err(f"{w}: unknown outfit {o['outfit']!r}")
            elif ov['pool'] in ('pass-free', 'pass-paid'):
                err(f"{w}: outfit {o['outfit']!r} is a season's ({ov['pool']})")
        if o.get('item') is not None and o['item'] not in items:
            err(f"{w}: unknown piece {o['item']!r}")

    for c in path:
        w = f"{f} {c['id']}"
        keys_within(c, ['id', 'name', 'when', 'done', 'beans', 'xp', 'steps'], ['outfit', 'item'], w)
        if len(c['name']) > 24:
            err(f"{w}: name over 24")
        british(c['name'], w)
        british(c['when'], w + ' when')
        path_words(c['done'], 60, w + ' done')
        if not isinstance(c['beans'], int) or c['beans'] < 1 or not isinstance(c['xp'], int) or c['xp'] < 0:
            err(f"{w}: reward {c['beans']} Beans / {c['xp']} XP")
        gives(c, w)
        for s in c['steps']:
            ws = f"{f} {s['id']}"
            keys_within(s, ['id', 'name', 'text', 'metric', 'target', 'beans', 'xp'],
                        ['passPoints', 'room', 'screen', 'outfit', 'item', 'optional'], ws)
            if len(s['name']) > 24:
                err(f"{ws}: name over 24")
            british(s['name'], ws)
            for p in hits(OBJECTIVE_BANNED, s['name']):
                err(f"{ws}: banned word /{p}/ in the name")
            path_words(s['text'], 60, ws)
            m = s['metric']
            if m not in LIFETIME | PATH_ONLY:
                err(f"{ws}: metric {m!r} is not a lifetime metric")
            if m in PAID_METRICS:
                err(f"{ws}: metric {m} can only be reached by paying")
            if (m == 'room_pieces') != (s.get('room') is not None):
                err(f"{ws}: a room is for room_pieces, and room_pieces needs one")
            elif s.get('room') is not None and s['room'] not in ROOMS6:
                err(f"{ws}: unknown room {s['room']!r}")
            if (m == 'screen_seen') != (s.get('screen') is not None):
                err(f"{ws}: a screen is for screen_seen, and screen_seen needs one")
            elif s.get('screen') is not None and s['screen'] not in SCREENS:
                err(f"{ws}: unknown screen {s['screen']!r} (the app records {sorted(SCREENS)})")
            if not isinstance(s['target'], int) or s['target'] < 1:
                err(f"{ws}: bad target")
            elif m == 'rooms_opened' and s['target'] > 6:
                err(f"{ws}: more rooms than exist")
            elif m == 'trust_tier' and not 1 <= s['target'] <= 6:
                err(f"{ws}: trust tier out of range")
            pay = [s['beans'], s['xp'], s.get('passPoints', 0)]
            if not all(isinstance(n, int) and n >= 0 for n in pay):
                err(f"{ws}: bad reward {pay}")
            elif s['beans'] + s['xp'] == 0 and s.get('outfit') is None:
                err(f"{ws}: pays nothing")
            gives(s, ws)
            if not isinstance(s.get('optional', False), bool):
                err(f"{ws}: optional must be true or false")
        # The chapter is done without its optional steps (a pass step, when no season may be on): they come last.
        flags = [s.get('optional') is True for s in c['steps']]
        late = [s['id'] for i, s in enumerate(c['steps']) if not flags[i] and any(flags[:i])]
        if late:
            err(f"{w}: required steps after an optional one (optional steps come last): {late}")


# ------------------------------------------------------------------ seasons / minigames
def check_seasons(d, items, surfaces, outfits):
    """CONTENT.md §7 and build_seasons.py (19 Oct): thirty tiers, the free track's rewards on the first twenty (three
    pieces and its outfit last), the premium track's on all thirty (pieces, a wallpaper and a floor, a second outfit and
    the season's own outfit last). A season with no paintings of its own (Black Cat) takes them from the Bean shop."""
    f = 'seasons.json'
    keys_exact(d, ['version', 'seasonLengthDays', 'tiers', 'freeTiers', 'launchAt', 'seasons'], f)
    expect(d['seasonLengthDays'], 28, 'season length')
    expect(d['tiers'], 30, 'tiers')
    expect(d['freeTiers'], 20, 'free tiers')
    expect([s['id'] for s in d['seasons']], ['blackcat', 'housewarming', 'midwinter', 'firstlight'], 'seasons')
    unique([s['id'] for s in d['seasons']], f)
    expect([s['id'] for s in d['seasons'] if s['christmas']], ['midwinter'], 'Christmas seasons')
    if d['launchAt'] not in [s['startAt'] for s in d['seasons'] if s['id'] == 'housewarming']:
        err(f"{f}: launchAt {d['launchAt']} is not the start of Housewarming, the launch season")
    from datetime import date
    prev_end = None
    for s in d['seasons']:
        w = f"{f} {s['id']}"
        keys_exact(s, ['id', 'name', 'theme', 'startAt', 'endAt', 'provisional', 'christmas', 'sku', 'freeTrack', 'paidTrack'], w)
        if s['provisional'] is not True:
            err(f"{w}: provisional must be true")
        if s['sku'] != f"housecat.pass.{s['id']}":
            err(f"{w}: sku pattern")
        a, b = date.fromisoformat(s['startAt']), date.fromisoformat(s['endAt'])
        # December is the Christmas season (1-28 Dec); the season meeting 1 December runs to it.
        if s['christmas']:
            if (a.month, a.day) != (12, 1) or (b - a).days != 28:
                err(f"{w}: the Christmas season runs four weeks from 1 December")
        elif not (28 <= (b - a).days <= 30 if (b.month, b.day) == (12, 1) else (b - a).days == 28):
            err(f"{w}: not four weeks")
        if not s['christmas'] and a.month == 12 and a.day <= 28:
            err(f"{w}: December belongs to the Christmas season")
        if prev_end and a != prev_end:
            err(f"{w}: not back to back")
        prev_end = b
        line_rules(s['theme'], w + ' theme', money=False)
        folder = 'pass_' + s['id']
        own = {i for i, v in items.items() if v['room'] == folder}   # its own paintings (8, Midwinter 7), if any
        for track, pools, n in (('freeTrack', 'free', d['freeTiers']), ('paidTrack', 'paid', d['tiers'])):
            t = s[track]
            expect([r['tier'] for r in t], list(range(1, n + 1)), f"{w} {track} tiers")
            kinds = Counter(r['kind'] for r in t)
            for r in t:
                ww = f"{w} {track} tier {r['tier']}"
                keys_exact(r, ['tier', 'kind', 'id', 'amount'], ww)
                if r['kind'] == 'beans':
                    if r['id'] is not None or not isinstance(r['amount'], int) or r['amount'] <= 0:
                        err(f"{ww}: bad beans reward")
                elif r['kind'] == 'item':
                    it = items.get(r['id'])
                    if own and (not it or it['pool'] != f'pass-{pools}' or it['room'] != folder):
                        err(f"{ww}: item {r['id']!r} does not resolve to a {folder} pass-{pools} item")
                    elif not own and (not it or it['pool'] != 'beans'):
                        err(f"{ww}: item {r['id']!r} is not a piece from the Bean shop")
                    if r['amount'] is not None:
                        err(f"{ww}: amount on an item")
                elif r['kind'] == 'outfit':
                    if r['id'] not in outfits or r['amount'] is not None:
                        err(f"{ww}: outfit {r['id']!r} does not resolve")
                elif r['kind'] == 'surface':
                    sf = surfaces.get(r['id'])
                    want_sf = (lambda x: x['pool'] == 'pass-paid' and x['room'] == folder) if own else \
                        (lambda x: x['pool'] == 'beans')
                    if not sf or not want_sf(sf) or pools != 'paid':
                        err(f"{ww}: surface {r['id']!r} does not resolve")
                else:
                    err(f"{ww}: bad kind")
            # The track ends with an outfit; a season with its own paintings tops it with its own.
            last = t[-1] if t else {}
            if last.get('kind') != 'outfit':
                err(f"{w}: {track} must end with an outfit")
            elif own and outfits.get(last['id'], {}).get('pool') != f'pass-{pools}':
                err(f"{w}: {track} ends with {last['id']!r}, not a pass-{pools} outfit of its own")
            if pools == 'free':
                expect(dict(kinds), {'item': 3, 'outfit': 1, 'beans': n - 4}, f"{w} free track")
            else:
                # The pieces the free track's three leave (a season short of a piece pays Beans there instead).
                paid_items = len(own) - 3 if own else 5
                expect(dict(kinds), {'item': paid_items, 'surface': 2, 'outfit': 2, 'beans': n - paid_items - 4},
                       f"{w} paid track")
                sk = {surfaces[r['id']]['kind'] for r in t if r['kind'] == 'surface' and r['id'] in surfaces}
                if sk != {'wall', 'floor'}:
                    err(f"{w}: paid track needs a wallpaper and a floor")
        if s['christmas'] and s['paidTrack'] and s['paidTrack'][-1]['id'] != 'santahat':
            err(f"{w}: the Christmas season's top prize is the Santa hat")
        got = {r['id'] for tr in ('freeTrack', 'paidTrack') for r in s[tr] if r['kind'] == 'item'}
        if own and got != own:
            err(f"{w}: track items differ from the season's {len(own)} pieces")


def check_minigames(d):
    f = 'minigames.json'
    keys_exact(d, ['version', 'playsPerDay', 'xpPerPlay', 'starBeans', 'passPointsPerPlay', 'games'], f)
    expect(d['playsPerDay'], 5, 'plays per day')
    expect(d['xpPerPlay'], 5, 'XP per play')
    expect(d['starBeans'], [2, 4, 6], 'star Beans')
    expect(d['passPointsPerPlay'], 5, 'pass points per play')
    unique([g['id'] for g in d['games']], f)
    want = {'laser_pointer': (20, [30, 80, 150]), 'knock_it_off': (20, [25, 60, 120]), 'string_chase': (20, [5, 25, 70]),
            'hide_and_seek': (20, [5, 40, 100])}
    expect({g['id'] for g in d['games']}, set(want), 'mini-games')
    for g in d['games']:
        w = f"{f} {g['id']}"
        keys_exact(g, ['id', 'name', 'durationSeconds', 'score', 'stars', 'rules'], w)
        if g['id'] in want and (g['durationSeconds'], g['stars']) != want[g['id']]:
            err(f"{w}: duration/stars differ from CONTENT.md")
        british(g['rules'], w)


def main():
    manifest = json.load(open(os.path.join(ASSETS, 'manifest.json')))['files']
    data = load()
    if errors:
        report(None)
        return
    n_ctx, n_entries, n_lines = check_lines(data['lines.json'])
    outfits = check_outfits(data['outfits.json'], manifest)
    items, surfaces = check_catalogue(data['catalogue.json'], manifest, data['outfits.json'])
    check_gifts(data['gifts.json'], manifest)
    check_objectives(data['objectives.json'])
    check_path(data['objectives.json'], items, outfits)
    check_seasons(data['seasons.json'], items, surfaces, outfits)
    check_minigames(data['minigames.json'])
    report((n_ctx, n_entries, n_lines, len(items), len(surfaces)))


def report(stats):
    for w in warnings:
        print('WARN ', w)
    for e in errors:
        print('ERROR', e)
    if stats:
        print(f"lines: {stats[0]} contexts, {stats[1]} entries, {stats[2]} lines; catalogue: {stats[3]} items, "
              f"{stats[4]} surfaces")
    print(f"{len(errors)} errors, {len(warnings)} warnings")
    sys.exit(1 if errors else 0)


if __name__ == '__main__':
    main()
