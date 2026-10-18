"""Cat manifest: turnarounds, puppet parts sheets, eyes, ears, whiskers, marking looks, outfits.
python3 cat.py <kind> <start> <n> [ref_job_id]"""
import json, sys

MASTER = "3553b9b6-f365-401a-bae2-690ec15397a8"      # mascot master plate (side view)
TURN = "80aec50a-eb9f-4a5a-a35e-db3a41a6c6ad"        # approved turnaround
IDENT = ("Identity, unchanged from the reference: a black cat with a round head a touch large for the body, big round amber "
         "eyes with a white catchlight, a small simplified nose, a subtle mouth line, both ears upright, dark navy-brown fur "
         "(never pure black) with a warm lit rim along the edges. Painterly, slightly stylised, painted-animation look; "
         "visible brushwork; high-key warm light from the upper left with violet-blue simplified shadows.")
BG = "Flat, plain pale cream background like the master plate, no ground, no cast shadow, no text, no labels."
BG_MAG = "Flat, solid pure magenta (#FF00FF) background, no ground, no shadow, no text, no labels."

SETS = {
 'short_slim': "short sleek fur, a slim graceful body, long slim legs and a long curling tail",
 'short_chunky': "short sleek fur and a CHUNKY, round, well-fed build: a wide barrel-shaped body clearly rounder and heavier than a normal cat, a little belly, thicker legs, fuller round cheeks, a thick tail",
 'long_slim': "a LONGHAIR coat: long, soft, flowing fur that clearly hangs off the body, a big fluffy mane-like ruff round the neck and chest, lynx-tufted ear tips, fluffy 'trousers' on the back legs, and a huge bushy plumed tail; the body underneath is slim",
 'long_chunky': "a LONGHAIR coat over a HEAVY, ROUND build: very long flowing fur, an enormous fluffy ruff, a wide barrel-shaped body clearly much rounder and heavier than a normal cat, short thick fluffy legs, lynx-tufted ears and a huge bushy plumed tail",
}
VIEWS = {
 'side': "side view facing left",
 'tqfront': "three-quarter front view, facing the lower left",
 'front': "front view, facing the viewer",
 'tqback': "three-quarter back view, facing away to the upper left",
}

def gp(prompt, ar, refs):
    p = {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": ar, "prompt": prompt}
    if refs: p["medias"] = [{"role": "image_references", "value": r} for r in refs]
    return p
BG_GREY = "Flat, plain mid-grey background, no ground, no cast shadow, no text, no labels."

def turnaround(set_id):
    return gp("Character turnaround sheet of the exact black cat from the reference images, as " + SETS[set_id] + ". Four views "
              "in a row, evenly spaced, all the same size and scale, standing in the same neutral pose on all four feet with the "
              "tail in a gentle upward curve: (1) side view facing left, (2) three-quarter front view facing the lower left, "
              "(3) front view facing the viewer, (4) three-quarter back view facing away to the upper left. " + IDENT + " " + BG,
              "16:9", [MASTER, TURN])

def parts(set_id, view, turn_ref):
    return gp("Puppet parts sheet for 2D cut-out animation of the exact cat from the reference image (" + SETS[set_id] + "), in "
              + VIEWS[view] + ". The cat's body is taken apart into separate pieces, laid out with clear space between them, "
              "nothing touching or overlapping. Top row, left to right: the head WITHOUT ears (complete face and eyes), then the "
              "two ears side by side, then the torso alone (no legs, no head, no tail). Bottom row, left to right: the four legs "
              "standing in a line (front near, front far, back near, back far), each leg with a rounded top end that tucks under "
              "the body. On the far right, three tails stacked: one raised in an upright curl, one curled round, one held low. "
              "Every piece in the same view, scale and lighting as the reference. " + IDENT + " " + BG,
              "16:9", [turn_ref])

EYES_T = ("Eye sprite sheet for the exact cat from the reference image, as seen in {v}: six eye sets laid out in a 3 by 2 grid "
          "with clear space between them, each set with a little of the surrounding dark fur so it can be laid over the face: "
          "(1) open and calm, (2) slow blink, half closed, (3) closed and content, (4) wide and surprised, (5) sleepy with "
          "drooping lids, (6) a judging squint. Big round amber eyes with a white catchlight. " + BG)
EARS_T = ("Ear sprite sheet for the exact cat from the reference image: four pairs of ROUNDED ears (softly rounded tips instead "
          "of pointed), one pair per view in a row: side view facing left, three-quarter front view, front view, three-quarter "
          "back view. Each ear separate, dark navy-brown fur with a warm rim light and pink-brown inner ear. " + BG)
WHISK_T = ("Whisker sprite sheet: three styles of cat whiskers in a row, each style as a left and a right fan of fine strokes: "
           "short and neat, long and sweeping, curly. Fine bright white painterly strokes isolated on a flat, solid pure black "
           "background. No cat, no face, no text.")
MARK = {
 'tuxedo': "a tuxedo: a crisp white bib covering the chest and belly, a white chin and white front paws",
 'locket': "a small white locket: one small white patch in the middle of the chest",
 'socks': "white socks: all four paws white up to the ankle",
}
MARK_WHERE = {
 'tuxedo': "the white bib on the chest and belly of the torso, the white chin on the head, white paws on the two front legs only",
 'locket': "the small white patch on the chest of the torso only; head, legs and tail stay fully dark",
 'socks': "white paws on all four legs only; head, torso and tail stay fully dark",
}
MARK_T = ("The exact cat from the reference images in the same three-quarter front standing pose, now with " + "{m}" +
          ". Everything else identical. " + IDENT + " " + BG_GREY)

OUTFITS = [
 ('beanie', 'head', "a mustard knitted beanie with a pompom and two ear holes"),
 ('flatcap', 'head', "a grey tweed flat cap"),
 ('buckethat', 'head', "a pale teal canvas bucket hat with two ear holes"),
 ('partyhat', 'head', "a teal and yellow striped paper party hat with an elastic strap"),
 ('bandana', 'neck', "a blue paisley bandana tied as a neckerchief"),
 ('scarf', 'neck', "a mustard knitted scarf wrapped round the neck with tasselled ends"),
 ('bowtie', 'neck', "a green velvet bow tie on a thin collar band"),
 ('roundglasses', 'face', "a pair of small round gold wire spectacles"),
 ('sunglasses', 'face', "a pair of small round sunglasses with tortoiseshell frames"),
 ('flowercrown', 'head', "a crown of small peach, butter-yellow and cream flowers and green leaves"),
 ('pumpkinhat', 'head', "a little knitted orange pumpkin hat with a green stalk"),
 ('santahat', 'head', "a small red Santa hat with a white pompom"),
 ('antlers', 'head', "a soft felt reindeer antlers headband"),
 ('crown', 'head', "a tiny gold crown with three points and small gems"),
 ('fisherman', 'body', "a cream cable-knit fisherman's jumper with leg openings"),
 ('raincoat', 'body', "a yellow hooded raincoat with toggles"),
 ('hoodie', 'body', "a soft grey hoodie with a front pocket"),
 ('xmasjumper', 'body', "a red Christmas jumper with a white snowflake pattern"),
 ('pyjamas', 'body', "pale blue and white striped pyjamas"),
 ('cardigan', 'body', "a sage-green button cardigan"),
 ('hawaiian', 'body', "a bright teal Hawaiian shirt with orange and yellow hibiscus flowers"),
 ('lifevest', 'body', "a small orange life vest with straps"),
 ('skeleton', 'body', "a black onesie printed with a cream skeleton pattern"),
 # 18 Oct 2026, for the launch shop (the beanie sheet added as a second reference for the style):
 ('beret', 'head', "a red wool beret"),
 ('strawberryhat', 'head', "a knitted red strawberry hat with tiny cream seed stitches, a green leafy top and two ear holes"),
 ('froghat', 'head', "a soft green knitted frog beanie with two round frog eyes on top and two ear holes"),
 ('sunhat', 'head', "a small round straw sun hat with a short brim and a peach ribbon band tied in a little bow (no cat ears drawn)"),
 ('nightcap', 'head', "a soft blue and white striped sleeping nightcap with a white pompom drooping to one side"),
 ('chefhat', 'head', "a small white pleated chef's toque"),
 ('bowler', 'head', "a tiny black felt bowler hat"),
 ('cowboyhat', 'head', "a small tan suede cowboy hat with a stitched band"),
 ('bunnyears', 'head', "a soft white felt bunny ears headband with pink inner ears"),
 ('heartglasses', 'face', "a pair of small heart-shaped sunglasses with pink frames and rose-tinted lenses"),
 ('pearls', 'neck', "a string of small cream pearls as a necklace"),
 ('bellcollar', 'neck', "a red leather collar with a small round gold bell"),
]
OUT_T_ = ("Costume sprite sheet: {d}, sized to fit the slim black cat from the reference image, drawn on its own WITHOUT the cat, "
         "in four views in a row matching the cat's views: side view facing left, three-quarter front view facing the lower "
         "left, front view, three-quarter back view facing the upper left. {fit} Painterly, visible brushwork, warm light "
         "from the upper left. " + BG_MAG)
OUT_T = OUT_T_
FIT = {'head': "Shaped to sit on top of the cat's head between its upright ears.",
       'neck': "Shaped to sit round the cat's neck.",
       'face': "Shaped to sit on the cat's face over its eyes.",
       'body': "Shaped to fit the cat's torso, with openings for the four legs, no head inside."}

def reqs(kind, ref=None):
    if kind == 'turn':
        return [(f"cat:turn_{s}", turnaround(s)) for s in SETS]
    if kind.startswith('parts_'):
        s = kind[6:]
        return [(f"cat:parts_{s}_{v}", parts(s, v, ref)) for v in VIEWS]
    if kind == 'extras':
        out = [(f"cat:eyes_{v}", gp(EYES_T.format(v=VIEWS[v]), "3:2", [ref])) for v in ('tqfront', 'front', 'side')]
        out.append(("cat:ears_rounded", gp(EARS_T, "16:9", [ref])))
        out.append(("cat:whiskers", gp(WHISK_T, "16:9", [])))
        out += [(f"cat:mark_{m}", gp(MARK_T.format(m=d), "1:1", [ref, MASTER])) for m, d in MARK.items()]
        return out
    if kind.startswith('markparts_'):
        # markparts_<set>  ref = "<turn_job>,<mark_tuxedo_job>,<mark_locket_job>,<mark_socks_job>"
        st = kind[10:]; turn, *marks = ref.split(',')
        out = []
        for (m, d), mref in zip(MARK.items(), marks):
            for v in VIEWS:
                p = parts(st, v, turn)
                p["prompt"] = p["prompt"].replace("Identity, unchanged", "Markings: the cat has " + d + "; paint " + MARK_WHERE[m] + ", matching the second reference image. The body shape comes from the first reference image. Identity, unchanged").replace(BG, BG_GREY)
                p["medias"].append({"role": "image_references", "value": mref})
                out.append((f"cat:markparts_{m}_{st}_{v}", p))
        return out
    if kind == 'outfits':
        return [(f"outfit:{i}", gp(OUT_T.format(d=d, fit=FIT[slot]), "16:9", [ref])) for i, slot, d in OUTFITS]

if __name__ == '__main__':
    kind = sys.argv[1]; start = int(sys.argv[2]); n = int(sys.argv[3]); ref = sys.argv[4] if len(sys.argv) > 4 else None
    sel = reqs(kind, ref)[start:start + n]
    names = [s[0] for s in sel]
    requests = [{"index": i, "params": p} for i, (_, p) in enumerate(sel)]
    json.dump({"names": names, "requests": requests, "ref": "surface"}, open(f'batch_{kind}_{start}.json', 'w'))
    print(json.dumps(requests))
