"""Cat builder (full customisation): request builder + queue.
Every sheet is a white base (tinted to any colour in code) or a pattern overlay painted as an aligned edit of a white base.
Names live in pipeline_state.json as cust:<id>.
  python3 custom.py next N [tag]   -> writes batch_cust_<tag>.json, prints the requests JSON for generate_image_batch
  python3 custom.py status         -> counts by phase
"""
import json, sys, os

SETS = ['short_slim', 'short_chunky', 'long_slim', 'long_chunky']
VIEWS = ['side', 'tqfront', 'front', 'tqback']
EXPR_VIEWS = ['tqfront', 'front', 'side']
BREEDS = ['persian', 'siamese', 'mainecoon', 'sphynx']
CLOSEST = {'persian': 'long_chunky', 'siamese': 'short_slim', 'mainecoon': 'long_chunky', 'sphynx': 'short_slim'}
PATTERNS = ['tabby_mackerel', 'white_bicolour', 'tortie', 'colourpoint', 'white_tuxedo', 'tabby_classic', 'spotted',
            'white_mitts', 'white_van']
COLOUR_PATTERNS = [p for p in PATTERNS if not p.startswith('white_')]
EARS = ['rounded', 'folded', 'tufted', 'oriental']

BG = "Flat, plain mid-grey background, no ground, no cast shadow, no text, no labels."
WHITE = ("a pure white cat: soft white fur with gentle cool grey-violet shading in the shadows, a warm rim light, pink inner "
         "ears, a pink nose, and the same big round amber eyes with a white catchlight")
SKIN = ("pale, near-white, warm-neutral bare skin (not pink) with soft cool grey-violet shading in the folds and wrinkles, a warm "
        "rim light, pink inner ears, a pink nose, and big amber eyes with a white catchlight")

BREED = {
 'persian': ("Persian (Himalayan type)",
             "a round head with a flat face, a short snub nose set between the eyes and full round cheeks, big round eyes, "
             "small rounded ears set low and wide apart, a very long, thick, fluffy coat with a big ruff round the neck and "
             "fluffy britches, a cobby body on short sturdy legs, and a big plumed tail",
             "a round head with a flat face, a short snub nose set between the eyes, full round cheeks, small rounded ears set "
             "low and wide apart, and long fluffy fur with a big ruff"),
 'siamese': ("Siamese / Oriental",
             "a long wedge-shaped head with a straight profile and a fine muzzle, very large, wide-based pointed ears, "
             "almond-shaped eyes, a long slender elegant body on long fine legs, dainty oval paws, a long thin whip tail, and "
             "very short, sleek, close-lying fur",
             "a long wedge-shaped head with a fine muzzle, very large wide-based pointed ears, almond-shaped eyes and very "
             "short sleek fur"),
 'mainecoon': ("Maine Coon",
               "a big, rugged, muscular cat with a long rectangular body, a squarish muzzle and high cheekbones, large tall "
               "ears with long lynx tufts at the tips and fluffy ear furnishings, a shaggy medium-long coat that is shorter on "
               "the shoulders and longer on the belly and britches, a full ruff, big round tufted paws, and a long, bushy, "
               "plumed tail",
               "a big head with a squarish muzzle and high cheekbones, large tall ears with long lynx tufts and fluffy ear "
               "furnishings, shaggy fur and a full ruff"),
 'sphynx': ("Sphynx",
            "a hairless cat with no fur at all, soft bare skin with gentle wrinkles on the forehead, neck and shoulders, very "
            "large wide-set ears, prominent cheekbones, big lemon-shaped eyes, a lean muscular body with a rounded belly, long "
            "legs, and a long thin whip tail; only a few very short whiskers",
            "a hairless head with soft bare skin and gentle forehead wrinkles, very large wide-set ears, prominent cheekbones "
            "and big lemon-shaped eyes"),
}

PAT = {  # {fur} = fur | skin
 'tabby_mackerel': "the white {fur} now has crisp dark charcoal-grey mackerel tabby markings: narrow parallel stripes running "
                   "down the sides like a fish skeleton, a dark line along the spine, bars across the chest, rings around the "
                   "legs and the tail, a dark tail tip, and the classic 'M' on the forehead with fine lines running back from "
                   "the outer corners of the eyes.",
 'tabby_classic': "the white {fur} now has bold dark charcoal-grey classic (blotched) tabby markings: wide swirling marbled "
                  "bands with a bullseye swirl on each side of the body, a butterfly shape across the shoulders, three lines "
                  "down the spine, broad rings on the legs and tail, a dark tail tip, necklace bands across the chest, and the "
                  "'M' on the forehead.",
 'spotted': "the white {fur} now has dark charcoal-grey Bengal-style spotted markings: scattered rosettes and broken spots over "
            "the body and legs, bars on the upper legs, rings on the tail with a dark tip, and the 'M' with streaks on the "
            "forehead.",
 'tortie': "the white {fur} now has dark charcoal-grey tortoiseshell mottling: large and small irregular soft-edged patches and "
           "brindled streaks scattered at random over about half of the {fur}, including a split down part of the face.",
 'colourpoint': "the {fur} now has Siamese colourpoint shading in dark charcoal-grey: the face mask around the eyes, nose and "
                "muzzle, the ears, the lower legs and paws, and the whole tail are dark, fading smoothly and softly into the "
                "pale body, which stays pale.",
 'white_tuxedo': "the {fur} is now painted a solid dark charcoal-grey everywhere EXCEPT these areas, which stay exactly the "
                 "original white: a white bib on the chest and throat, white paws on all four feet, and a white chin and muzzle "
                 "tip. The ears and tail are dark.",
 'white_bicolour': "the {fur} is now painted a solid dark charcoal-grey on the back, sides, top of the head, ears and tail, while "
                   "the chest, belly, all four legs, the muzzle and an inverted V up the middle of the face stay exactly the "
                   "original white.",
 'white_mitts': "the {fur} is now painted a solid dark charcoal-grey everywhere EXCEPT neat white mittens on the front paws, white "
                "boots up to the hocks on the back legs, and a white chin, which stay exactly the original white.",
 'white_van': "the {fur} stays white almost everywhere, except the tail and two patches on the top of the head (including the "
              "ears), which are painted a solid dark charcoal-grey.",
}
UNIT = {'parts': 'piece', 'pose': 'cat', 'expr': 'head', 'ears': 'ear', 'bobtail': 'tail'}
NOTE = {'parts': " This is a puppet parts sheet: paint each separate piece with exactly the part of the pattern it would carry "
                 "on the assembled cat.",
        'ears': " Paint each ear as it would look on a cat with this coat.",
        'bobtail': " Paint each tail as it would look on a cat with this coat."}


def gp(prompt, refs, ar):
    return {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": ar, "prompt": prompt,
            "medias": [{"role": "image_references", "value": r} for r in refs]}


def catalogue():
    """Ordered list of (id, kind, refs(list of name-or-jobid), prompt, aspect)."""
    S = json.load(open('pipeline_state.json'))
    J = lambda k: S[k]['job_id']
    out = []
    # ---- phase 1: white base for the four existing body sets + swap parts + breed turnarounds
    for st in SETS:
        for v in VIEWS:
            out.append((f'w_parts_{st}_{v}', 'parts', [J(f'cat:parts_{st}_{v}')],
                        "The exact same puppet parts sheet as the reference image: identical layout, every piece with identical "
                        f"shape, size and position, identical brushwork and lighting, but the cat is now {WHITE}. Nothing else "
                        f"changes. {BG}", '16:9'))
    for st in SETS:
        out.append((f'w_pose_{st}', 'pose', [J(f'pose:{st}_plain')],
                    "The exact same pose sheet as the reference image, identical layout, poses, shapes, sizes and positions of "
                    f"all eight cats, identical brushwork and lighting, but every cat is now {WHITE}. Nothing else changes. {BG}",
                    '16:9'))
    for v in EXPR_VIEWS:
        out.append((f'w_expr_{v}', 'expr', [J(f'cat:eyes_{v}')],
                    "The exact same sheet of six cat heads as the reference image, identical layout, head shapes, sizes, "
                    "positions and facial expressions, identical brushwork and lighting, but every head is now " + WHITE +
                    " (the eyes keep exactly the same expressions and lid shapes). Nothing else changes. " + BG, '3:2'))
    ear_ref = [J('cat:ears_rounded')]
    EARD = {
     'rounded': None,
     'folded': "Each ear is now a Scottish Fold ear: small, folded forward and down into a neat rounded cap that lies close to "
               "the head, with only a hint of pink inner ear showing at the fold.",
     'tufted': "Each ear is now a Maine Coon / lynx ear: taller and larger, pointed, with a long wispy lynx tuft at the tip and "
               "long fluffy ear furnishings sprouting from inside.",
     'oriental': "Each ear is now a very large Oriental / Siamese ear: tall, with a very wide base and a pointed tip, flared "
                 "outwards, thin, with short sleek fur.",
    }
    for e in EARS:
        if EARD[e] is None:
            p = ("The exact same sheet of eight separate cat ears as the reference image, identical layout, shapes, sizes, "
                 "positions and views, identical brushwork and lighting, but the ears are now pure white: soft white fur with "
                 "gentle cool grey-violet shading, a warm rim light, and soft pink inner ears. Nothing else changes. " + BG)
        else:
            p = ("The same sheet of eight separate cat ears as the reference image, same layout: four pairs in a single row in "
                 "the same positions, the same views and about the same base width, nothing touching, the same brushwork and "
                 f"lighting. {EARD[e]} The ears are pure white: soft white fur with gentle cool grey-violet shading, a warm rim "
                 f"light, and soft pink inner ears. {BG}")
        out.append((f'w_ears_{e}', 'ears', ear_ref, p, '16:9'))
    out.append(('w_bobtail', 'bobtail', [J('cat:parts_short_chunky_side')],
                "A sheet of twelve separate short bobtails for 2D cut-out animation, for the cat in the reference image but in "
                "pure white fur (soft white with gentle cool grey-violet shading and a warm rim light), matching its brushwork, "
                "lighting and scale. Each bobtail is a short fluffy pom-pom stub of a tail, about a quarter the length of a "
                "normal tail, with a rounded base end that tucks under the body. Laid out in a grid with clear space between "
                "them, nothing touching: four columns (left to right: side view, three-quarter front view, front view, "
                "three-quarter back view) and three rows (top: held up; middle: curled into a little hook; bottom: held low). "
                "All twelve the same size. " + BG, '16:9'))
    for b in BREEDS:
        name, desc, _ = BREED[b]
        coat = SKIN if b == 'sphynx' else WHITE
        if b == 'sphynx' and 'cust:w_turn_sphynx_v1' in S:   # first try came out taupe: lighten it, keep the design
            out.append(('w_turn_sphynx', 'turn', [S['cust:w_turn_sphynx_v1']['job_id']],
                        "The exact same image as the reference, identical in every way: the same four views, poses, shapes, "
                        "wrinkles, ears, eyes and brushwork. The only change: the bare skin is now much paler, a very pale, "
                        "almost white porcelain tone (like white fur, not pink, not beige, not grey), with soft cool grey-violet "
                        "shading in the folds and wrinkles and a warm rim light; the inner ears and nose stay pink and the eyes "
                        "stay amber. " + BG, '16:9'))
            continue
        out.append((f'w_turn_{b}', 'turn', [J(f'cat:turn_{CLOSEST[b]}')],
                    "The same turnaround sheet layout as the reference image: four full-body standing views of one cat in the "
                    "same order and positions (side view facing left, three-quarter front, front, three-quarter back), the same "
                    f"scale, painterly brushwork and lighting. But the cat is now a {name}: {desc}. Colour: {coat}. {BG}",
                    '16:9'))
    # ---- phase 2: breed white bases (layout from the closest set's white sheet, look from the breed turnaround)
    for b in BREEDS:
        name, desc, head = BREED[b]
        coat = SKIN if b == 'sphynx' else WHITE
        c = CLOSEST[b]
        for v in VIEWS:
            out.append((f'w_parts_{b}_{v}', 'parts', [f'cust:w_parts_{c}_{v}', f'cust:w_turn_{b}'],
                        "Edit the first reference image, a puppet parts sheet for 2D cut-out animation. Keep the exact same "
                        "layout: the same eleven separate pieces (the head WITHOUT ears, the two ears, the torso alone, four legs, "
                        "three tails) in the same positions and order, the same view and roughly the same sizes, nothing touching "
                        "or overlapping, the same brushwork and lighting. Redraw every piece as the "
                        f"{name} cat from the second reference image: {desc}. Colour: {coat}. {BG}", '16:9'))
        out.append((f'w_pose_{b}', 'pose', [f'cust:w_pose_{c}', f'cust:w_turn_{b}'],
                    "Edit the first reference image, a pose sheet of eight cats. Keep the exact same layout: the same eight "
                    "poses in the same positions and order, the same scale, nothing touching, the same brushwork and lighting. "
                    f"Redraw every cat as the {name} cat from the second reference image: {desc}. Colour: {coat}. {BG}",
                    '16:9'))
        for v in EXPR_VIEWS:
            out.append((f'w_expr_{b}_{v}', 'expr', [f'cust:w_expr_{v}', f'cust:w_turn_{b}'],
                        "Edit the first reference image, a sheet of six cat heads with six facial expressions. Keep the exact "
                        "same layout, positions, sizes and view, and the same six expressions (eye and lid shapes). Redraw every "
                        f"head as the {name} cat from the second reference image: {head}. Colour: {coat}. {BG}", '3:2'))
    # ---- phase 3/4: pattern overlays (existing sets first, then breeds)
    def bases(group):
        if group == 'sets':
            r = [(f'w_parts_{st}_{v}', 'parts') for st in SETS for v in VIEWS] + [(f'w_pose_{st}', 'pose') for st in SETS]
            r += [(f'w_expr_{v}', 'expr') for v in EXPR_VIEWS]
            return r
        if group == 'swap':
            return [(f'w_ears_{e}', 'ears') for e in EARS] + [('w_bobtail', 'bobtail')]
        b = group
        return ([(f'w_parts_{b}_{v}', 'parts') for v in VIEWS] + [(f'w_pose_{b}', 'pose')] +
                [(f'w_expr_{b}_{v}', 'expr') for v in EXPR_VIEWS])
    for group in ['sets', 'swap'] + BREEDS:
        for p in PATTERNS:
            if group == 'swap' and p.startswith('white_'): continue
            fur = 'skin' if group == 'sphynx' else 'fur'
            for bid, kind in bases(group):
                prompt = ("The exact same image as the reference, identical in every way: the same layout, every "
                          f"{UNIT[kind]} with identical shape, size, position and pose, the same brushwork, lighting, eyes, nose "
                          f"and inner ears. The only change: {PAT[p].format(fur=fur)}{NOTE.get(kind, '')} Everything else stays "
                          "exactly as it is. Flat, plain mid-grey background, no text.")
                out.append((f'ov_{p}__{bid}', kind, [f'cust:{bid}'], prompt, '3:2' if kind == 'expr' else '16:9'))
    return out


def resolve(S, r):
    if r.startswith('cust:'):
        v = S.get(r)
        if not v or not v.get('job_id') or v.get('status') not in ('completed', 'downloaded'): return None
        return v['job_id']
    return r


def pending(S, name):
    v = S.get(name)
    return (not v) or (not v.get('job_id')) or v.get('status') in ('failed', 'nsfw', 'error', 'cancelled')


def nxt(n, tag):
    S = json.load(open('pipeline_state.json'))
    names, reqs = [], []
    for cid, kind, refs, prompt, ar in catalogue():
        nm = f'cust:{cid}'
        if not pending(S, nm): continue
        rr = [resolve(S, r) for r in refs]
        if any(x is None for x in rr): continue
        reqs.append({'index': len(reqs), 'params': gp(prompt, rr, ar)}); names.append(nm)
        if len(reqs) >= n: break
    json.dump({'names': names, 'requests': reqs, 'ref': 'surface'}, open(f'batch_cust_{tag}.json', 'w'), indent=1)
    print(json.dumps(reqs))


def status():
    S = json.load(open('pipeline_state.json'))
    cat = catalogue(); c = {}
    for cid, *_ in cat:
        ph = cid.split('_')[0] + ('_breed' if any(b in cid for b in BREEDS) else '')
        st = S.get(f'cust:{cid}', {}).get('status', 'todo')
        c.setdefault(ph, {}).setdefault(st, 0); c[ph][st] += 1
    print(len(cat), json.dumps(c))


if __name__ == '__main__':
    if sys.argv[1] == 'next': nxt(int(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else 'x')
    elif sys.argv[1] == 'status': status()
