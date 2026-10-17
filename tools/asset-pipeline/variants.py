"""Ear / tail variants of the white pose sheets and ear-less expression heads, so an ear or tail swap in the cat builder
also shows in the whole-painting resting poses and in the expression heads (the puppet parts already swap freely).
  python3 variants.py next N <tag>   -> request JSON on stdout, writes batch_cust_<tag>.json (record with cq.py rec <tag>)
Pattern masks for these sheets are cut from the PARENT sheet's overlays (the edit changes only ears / tail), see custcut.py.
"""
import json, sys
STATE = 'pipeline_state.json'
STD = ['short_slim', 'short_chunky', 'long_slim', 'long_chunky']
EARS = ['rounded', 'folded', 'tufted', 'oriental']
EARD = {
 'rounded': "small, neat ears with soft rounded tips instead of points, with pink insides",
 'folded': "Scottish Fold ears: small, folded forward and down into a neat rounded cap that lies close to the head, with "
           "only a hint of pink inner ear showing at the fold",
 'tufted': "Maine Coon / lynx ears: taller and larger, pointed, with a long wispy lynx tuft at each tip and long fluffy "
           "ear furnishings sprouting from inside",
 'oriental': "very large Oriental / Siamese ears: tall, with a very wide base and a pointed tip, flared outwards, thin, "
             "with short sleek fur and pink insides",
}
BG = "Flat, plain mid-grey background, no ground, no cast shadow, no text, no labels."


def J(k):
    return json.load(open(STATE))[k]['job_id']


def catalogue():
    out = []
    for v in ('tqfront', 'front', 'side'):
        out.append((f'w_expr_noear_{v}', '3:2', [J(f'cust:w_expr_{v}')],
            "Edit the reference image, a sheet of six white cat heads with six facial expressions. Keep everything exactly "
            "the same: the layout, every head's position, size and angle, the expressions, eyes, eyelids, nose, mouth, "
            "whiskers, the brushwork and the lighting. The only change: remove the ears from every head completely. No ears "
            "at all: the top of each head is a smooth, rounded, furry crown, like a puppet head piece that gets separate "
            "ears attached later. " + BG))
    for b in STD:
        for e in EARS:
            out.append((f'w_pose_{b}__{e}', '16:9', [J(f'cust:w_pose_{b}'), J(f'cust:w_ears_{e}')],
                "Edit the first reference image, a pose sheet of eight white cats. Keep everything exactly the same: the "
                "layout, every cat's position, size and pose, the body, legs and tail, the face, eyes, nose and whiskers, "
                "the brushwork and the lighting. The only change: every cat's ears become " + EARD[e] + ", like the ears "
                "in the second reference image, turned to suit each cat's head angle. An ear hidden behind the head stays "
                "hidden. " + BG))
        out.append((f'w_pose_{b}__bobtail', '16:9', [J(f'cust:w_pose_{b}'), J('cust:w_bobtail')],
            "Edit the first reference image, a pose sheet of eight white cats. Keep everything exactly the same: the layout, "
            "every cat's position, size and pose, the body, legs, head, ears, face, eyes and nose, the brushwork and the "
            "lighting. The only change: every cat's long tail is replaced by a short, fluffy pom-pom bobtail like the ones "
            "in the second reference image, about a quarter of the length. Where the long tail used to cover the body or "
            "paws, paint the cat's white fur there instead; where it stuck out, show the plain background. " + BG))
    return out


def nxt(n, tag):
    s = json.load(open(STATE))
    todo = [c for c in catalogue() if f'cust:{c[0]}' not in s][:n]
    json.dump({'names': [f'cust:{c[0]}' for c in todo]}, open(f'batch_cust_{tag}.json', 'w'))
    req = [{'index': i, 'params': {'model': 'gpt_image_2_5', 'quality': 'high', 'resolution': '2k', 'aspect_ratio': ar,
            'prompt': p, 'medias': [{'role': 'image_references', 'value': m} for m in meds]}}
           for i, (name, ar, meds, p) in enumerate(todo)]
    print(json.dumps(req))


if __name__ == '__main__':
    if sys.argv[1] == 'next': nxt(int(sys.argv[2]), sys.argv[3])
    else:
        s = json.load(open(STATE)); c = catalogue()
        print(len(c), sum(1 for x in c if f'cust:{x[0]}' in s and s[f'cust:{x[0]}'].get('status') == 'downloaded'))
