"""Writes cat/custom/catbuilder.json: the data the app's cat builder reads (bodies, ears, tails, patterns, white
markings, palettes, presets, and where every sprite and mask lives). Palettes come from tint.py so the reference
renderer and the app agree.  python3 catbuilder.py"""
import json, os
from tint import COLOURS, EYES, NOSES

ROOT = 'cat/custom'
VIEWS = ['side', 'tqfront', 'front', 'tqback']
STD = ['short_slim', 'short_chunky', 'long_slim', 'long_chunky']
POSES = ['sit_side', 'sit_tqfront', 'sit_front', 'sit_back', 'loaf_side', 'loaf_tqfront', 'sleep_curl', 'stretch_side']
EXPRS = ['calm', 'slowblink', 'content', 'surprised', 'sleepy', 'squint']

LABEL = {
 'black': 'Black', 'smoke': 'Smoke', 'blue': 'Blue (grey)', 'lilac': 'Lilac', 'chocolate': 'Chocolate',
 'cinnamon': 'Cinnamon', 'fawn': 'Fawn', 'brown': 'Brown', 'red': 'Red', 'ginger': 'Ginger', 'cream': 'Cream',
 'white': 'White', 'silver': 'Silver', 'seal': 'Seal', 'golden': 'Golden', 'rose': 'Rose (bare skin)',
}
EYE_LABEL = {'amber': 'Amber', 'gold': 'Gold', 'copper': 'Copper', 'green': 'Green', 'hazel': 'Hazel', 'blue': 'Blue',
             'aqua': 'Aqua', 'lilac': 'Lilac'}
NOSE_LABEL = {'pink': 'Pink', 'brick': 'Brick', 'black': 'Black', 'grey': 'Grey', 'chocolate': 'Chocolate'}


def hexc(c): return '#%02x%02x%02x' % tuple(c)


def bodies():
    out = {}
    for b in STD:
        fur, build = b.split('_')
        out[b] = {
            'label': f"{'Shorthair' if fur == 'short' else 'Longhair'}, {build}", 'fur': fur, 'build': build,
            'scale': 1.0, 'own_ears': 'pointed', 'own_tail': 'long', 'ear_swaps': True, 'tail_swaps': True,
            'expression_heads': 'stdnoear',
            'weight_pair': f'{fur}_slim' if build == 'chunky' else f'{fur}_chunky',
            'rare': False,
        }
    out['persian'] = {'label': 'Persian', 'fur': 'long', 'build': 'chunky', 'scale': 1.0, 'own_ears': 'small rounded',
                      'own_tail': 'plume', 'ear_swaps': False, 'tail_swaps': False, 'expression_heads': 'persian',
                      'weight_pair': None, 'rare': False}
    out['siamese'] = {'label': 'Siamese / Oriental', 'fur': 'short', 'build': 'slim', 'scale': 1.0,
                      'own_ears': 'large', 'own_tail': 'whip', 'ear_swaps': False, 'tail_swaps': False,
                      'expression_heads': 'siamese', 'weight_pair': None, 'rare': False}
    out['mainecoon'] = {'label': 'Maine Coon', 'fur': 'long', 'build': 'chunky', 'scale': 1.15, 'own_ears': 'tufted',
                        'own_tail': 'bushy', 'ear_swaps': False, 'tail_swaps': False, 'expression_heads': 'mainecoon',
                        'weight_pair': None, 'rare': False}
    out['sphynx'] = {'label': 'Sphynx', 'fur': 'none', 'build': 'slim', 'scale': 1.0, 'own_ears': 'large',
                     'own_tail': 'whip', 'ear_swaps': False, 'tail_swaps': False, 'expression_heads': 'sphynx',
                     'weight_pair': None, 'rare': False, 'note': 'hairless: the coat colour is the skin colour'}
    return out


def presets():
    P = []
    def p(id, name, body, coat, eyes, nose, pattern=None, pcol=None, white=None, ears='own', tail='own', note=''):
        e = eyes if isinstance(eyes, list) else [eyes, eyes]
        P.append({'id': id, 'name': name, 'body': body, 'ears': ears, 'tail': tail, 'coat': coat, 'pattern': pattern,
                  'pattern_colour': pcol, 'white': white, 'eye_left': e[0], 'eye_right': e[1], 'nose': nose,
                  **({'note': note} if note else {})})
    p('midnight', 'Midnight', 'short_slim', 'black', 'amber', 'black', note='the HouseCat mascot and the default cat')
    p('bombay', 'Bombay', 'short_chunky', 'black', 'copper', 'black')
    p('tuxedo', 'Tuxedo', 'short_slim', 'black', 'green', 'black', white='white_tuxedo')
    p('ginger_tabby', 'Ginger Tabby', 'short_chunky', 'ginger', 'gold', 'brick', 'tabby_mackerel', 'red')
    p('silver_tabby', 'Silver Tabby', 'short_slim', 'silver', 'green', 'brick', 'tabby_classic', 'black')
    p('brown_tabby', 'Brown Tabby', 'short_slim', 'cinnamon', 'hazel', 'brick', 'tabby_mackerel', 'seal')
    p('tortoiseshell', 'Tortoiseshell', 'short_slim', 'black', 'copper', 'black', 'tortie', 'ginger')
    p('calico', 'Calico', 'short_chunky', 'ginger', 'amber', 'pink', 'tortie', 'black', 'white_bicolour')
    p('british_blue', 'British Blue', 'short_chunky', 'blue', 'copper', 'grey', ears='rounded')
    p('russian_blue', 'Russian Blue', 'short_slim', 'blue', 'green', 'grey')
    p('scottish_fold', 'Scottish Fold', 'short_chunky', 'cream', 'gold', 'pink', 'tabby_mackerel', 'cinnamon', ears='folded')
    p('bengal', 'Bengal', 'short_slim', 'golden', 'green', 'brick', 'spotted', 'seal')
    p('oriental', 'Oriental Havana', 'siamese', 'chocolate', 'green', 'chocolate')
    p('seal_point', 'Seal Point Siamese', 'siamese', 'fawn', 'blue', 'chocolate', 'colourpoint', 'seal')
    p('himalayan', 'Himalayan', 'persian', 'cream', 'blue', 'chocolate', 'colourpoint', 'seal')
    p('white_persian', 'White Persian', 'persian', 'white', ['blue', 'copper'], 'pink', note='odd-eyed')
    p('maine_coon', 'Maine Coon', 'mainecoon', 'brown', 'gold', 'brick', 'tabby_classic', 'seal')
    p('ragdoll', 'Ragdoll', 'long_chunky', 'cream', 'blue', 'pink', 'colourpoint', 'seal', 'white_mitts')
    p('turkish_van', 'Turkish Van', 'long_slim', 'red', ['blue', 'amber'], 'pink', white='white_van', note='odd-eyed')
    p('smoke_longhair', 'Smoke Longhair', 'long_slim', 'smoke', 'copper', 'grey')
    p('japanese_bobtail', 'Japanese Bobtail', 'short_slim', 'black', ['gold', 'blue'], 'pink', 'tortie', 'ginger',
      'white_van', tail='bobtail', note='mi-ke (tricolour), odd-eyed')
    p('sphynx', 'Sphynx', 'sphynx', 'rose', 'aqua', 'pink')
    p('lilac_sphynx', 'Lilac Sphynx', 'sphynx', 'lilac', 'gold', 'pink', 'colourpoint', 'smoke')
    return P


def paths():
    return {
        'parts': 'base/parts/cat_{body}_{view}_{part}.png',
        'part_names': ['head', 'ear_far', 'ear_near', 'torso', 'leg_front_far', 'leg_front_near', 'leg_back_far',
                       'leg_back_near', 'tail_up', 'tail_curl', 'tail_low'],
        'swap_ears': 'base/ears/ear_{ears}_{view}_{side}.png',
        'bobtail': 'base/tails/bobtail_{view}_{pose}.png',
        'expression_heads': 'base/expr/head_{heads}_{view}_{expr}.png',
        'expression_views': ['tqfront', 'front', 'side'],
        'expressions': EXPRS,
        'poses': 'base/poses/cat_{body}_{pose}{variant}.png',
        'pose_names': POSES,
        'pose_variant': "'' for the body's own ears and tail; '__<ears>' (rounded, folded, tufted, oriental) or "
                        "'__bobtail' for the four standard bodies",
        'whole_reference': 'base/whole/cat_{body}_{view}_whole.png (breeds; the standard sets use cat/base/<set>/)',
        'pattern_mask': 'masks/{pattern}/{same path as the sprite, without base/}',
        'white_mask': 'masks/{white}/{same path as the sprite, without base/}',
        'features_mask': 'masks/features/{same path as the sprite, without base/}',
    }


def main():
    data = {
        'version': 1,
        'about': "HouseCat cat builder. Every sprite under base/ is painted WHITE; the coat, pattern, white markings, eyes "
                 "and nose are applied in code with the coat recipe (docs/SPEC.md 'Coat recipe'; reference "
                 "implementation tools/asset-pipeline/tint.py). Masks are 8-bit greyscale PNGs the same size as their "
                 "sprite; a missing mask means 0 everywhere. The black cat (preset 'midnight') is the mascot and the "
                 "default.",
        'root': 'assets/cat/custom',
        'views': VIEWS,
        'paths': paths(),
        'bodies': bodies(),
        'ears': {
            'own': {'label': "The body's own ears", 'rare': False},
            'rounded': {'label': 'Rounded', 'rare': False},
            'folded': {'label': 'Folded (Scottish Fold)', 'rare': False},
            'tufted': {'label': 'Tufted (lynx tips)', 'rare': False},
            'oriental': {'label': 'Oriental (very large)', 'rare': False},
        },
        'tails': {'own': {'label': "The body's own tail", 'rare': False}, 'bobtail': {'label': 'Bobtail', 'rare': False}},
        'patterns': {
            'none': {'label': 'Solid'},
            'tabby_mackerel': {'label': 'Mackerel tabby', 'rare': False},
            'tabby_classic': {'label': 'Classic tabby', 'rare': False},
            'spotted': {'label': 'Spotted', 'rare': False},
            'tortie': {'label': 'Tortoiseshell / patched', 'rare': False},
            'colourpoint': {'label': 'Colourpoint', 'rare': False},
        },
        'white_markings': {
            'none': {'label': 'None'},
            'white_mitts': {'label': 'Mitts and boots', 'rare': False},
            'white_tuxedo': {'label': 'Tuxedo (bib, paws, chin)', 'rare': False},
            'white_bicolour': {'label': 'Bicolour (white underside and face)', 'rare': False},
            'white_van': {'label': 'Van (white with coloured head patches and tail)', 'rare': False},
        },
        'swap_mask_rule': "Swap ears and the bobtail carry the colour-pattern masks but never white markings; the "
                          "expression heads carry both. Breed bodies keep their own ears and tail.",
        'palettes': {
            'coat': {k: {'label': LABEL[k], 'rgb': list(v), 'hex': hexc(v)} for k, v in COLOURS.items()},
            'eyes': {k: {'label': EYE_LABEL[k], 'rgb': list(v), 'hex': hexc(v),
                         'rare': False} for k, v in EYES.items()},
            'nose': {k: {'label': NOSE_LABEL[k], 'rgb': list(v), 'hex': hexc(v)} for k, v in NOSES.items()},
            'free_picker': "Coat and pattern colours may also come from a free colour picker; clamp the luminance of a "
                           "picked coat to 40-250 so the painted shading still reads.",
        },
        'odd_eyed': {'rare': False, 'note': "eye_left / eye_right are the eyes on the left / right of the IMAGE. A side "
                     "view shows one eye: it is in the left (red) channel of the features mask and takes eye_left."},
        'rare_note': "Every builder option is free at launch (Josh, 17 Oct 2026); extra cats are the paid item "
                     "(housecat.cat.slot<n>). The 'rare' flags are all off and stay as the switch if paid looks "
                     "(housecat.look.<name>) are ever added: flip a flag, no new art.",
        'naming': {'required': True, 'max_length': 20, 'editable_later': True, 'profanity_filter': True,
                   'note': "The player always types their cat's own name (groups show it, so it goes through the "
                           "profanity filter). Preset names name the look, never the cat. Offer three suggestions "
                           "and a shuffle button.",
                   'suggestions': ['Pip', 'Miso', 'Olive', 'Biscuit', 'Juniper', 'Pepper', 'Bramble', 'Tofu', 'Mochi',
                                   'Hazel', 'Willow', 'Nutmeg', 'Basil', 'Clementine', 'Pudding', 'Marmalade', 'Sage',
                                   'Fig', 'Dumpling', 'Moss', 'Inky', 'Teddy', 'Maple', 'Pickle']},
        'presets': presets(),
        'outfits': {
            'note': "Outfits (assets/outfits, 23 x 4 views) are layered over any look; nothing is painted per cat. Head items "
                    "anchor between the ears on the head part, neck items at the neck, body items over the torso. 'fit' "
                    "holds a per-body, per-view, per-slot nudge [dx, dy, scale] in the part's own pixels; all start "
                    "neutral and are set once by eye in a debug screen. Head items sit 'tall_ears_lift' of the ear height "
                    "higher on the tall ears listed, so a hat never cuts through them.",
            'tall_ears': ['siamese', 'sphynx', 'mainecoon', 'oriental', 'tufted'],
            'tall_ears_lift': 0.35,
            'fit': {b: {v: {'head': [0, 0, 1.0], 'neck': [0, 0, 1.0], 'body': [0, 0, 1.0]} for v in VIEWS}
                    for b in STD + ['persian', 'siamese', 'mainecoon', 'sphynx']},
        },
        'look_fields': ['body', 'ears', 'tail', 'coat', 'pattern', 'pattern_colour', 'white', 'eye_left', 'eye_right',
                        'nose', 'eye_size', 'whisker_length', 'age'],
    }
    # sanity: every preset refers to things that exist
    for pr in data['presets']:
        assert pr['body'] in data['bodies'], pr
        assert pr['coat'] in COLOURS and (pr['pattern_colour'] is None or pr['pattern_colour'] in COLOURS), pr
        assert pr['eye_left'] in EYES and pr['eye_right'] in EYES and pr['nose'] in NOSES, pr
        assert pr['pattern'] in (None, *data['patterns']) and pr['white'] in (None, *data['white_markings']), pr
        if pr['ears'] != 'own' or pr['tail'] != 'own':
            assert data['bodies'][pr['body']]['ear_swaps'], pr
    os.makedirs(ROOT, exist_ok=True)
    json.dump(data, open(f'{ROOT}/catbuilder.json', 'w'), indent=1)
    print(len(data['presets']), 'presets')


if __name__ == '__main__':
    main()
