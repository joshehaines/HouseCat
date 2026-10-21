"""The body garments, painted over the cat's own paintings (needs numpy, Pillow, SciPy). For each body:
1. python sheet.py <body> <dark|white|ginger>: the nine paintings on one sheet, tinted so the garment stands out,
   and a mask of everything below the head (work/sheets/).
2. Upload the sheet and its mask (upload.sh to a presigned URL), their media IDs into work/media.json
   ("<body>_<tint>.png", "<body>_mask.png").
3. python requests.py <garment> [<tint> <body,body>]: the batch of Ideogram 4.5 masked edits as JSON (a redo of
   some bodies on another tint is indexed +100); submit it and wait for the jobs.
4. python process.py <garment> '<jobs json>' [--better] [--tint=<tint>]: downloads, cuts out the layers into
   work/layers/<garment>/ and writes work/out/check_<garment>.png to look at.
5. python defringe.py <garment> after a ginger-tinted run; python install.py <garment>: into assets/ and App/Art.
Curled up and stretching (21 Oct): sheet.py <body> <tint> rest <garment> makes a sheet of those two poses with the cat
sitting and lying in the garment below them to match; rest_requests() is their batch (redo=True for a pose that came out
empty or a patch); extract.extract(..., rest=True) cuts them out, defringe.py after ginger, install_rest.py installs them.
A pose the model keeps painting outside the mask may take another tint (the Siamese's onesie curled up: ginger, not white).
Never name the fur's colour in the prompt: the mask is soft and the model recolours the cat to match."""
import json, os, sys
WORK = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'work')
BODIES = ['short_slim', 'short_chunky', 'long_slim', 'long_chunky', 'persian', 'siamese', 'sphynx', 'mainecoon']
GARMENTS = {
    'fisherman': ('dark', "a cream cable-knit fisherman's jumper", 'jumper'),
    'raincoat': ('dark', 'a yellow raincoat with toggles and the hood down', 'raincoat'),
    'hoodie': ('ginger', 'a soft grey hoodie with a front pocket and the hood down', 'hoodie'),
    'xmasjumper': ('dark', 'a red Christmas jumper with a white snowflake pattern', 'jumper'),
    'pyjamas': ('dark', 'a pale blue and white striped pyjama top', 'pyjama top'),
    'cardigan': ('dark', 'a sage-green button cardigan', 'cardigan'),
    'hawaiian': ('dark', 'a bright teal Hawaiian shirt with orange and yellow hibiscus flowers', 'shirt'),
    'lifevest': ('dark', 'a small orange life vest with straps', 'life vest'),
    'skeleton': ('white', 'a black onesie printed with a cream skeleton pattern', 'onesie'),
}
# A fuller description for redos where the first one came out too small (a life vest painted as a harness).
REDO = {'lifevest': ('a bright orange life jacket with black straps and buckles, covering its chest, back and belly', 'life jacket')}
def prompt(g, redo=False):
    _, desc, noun = GARMENTS[g]
    if redo and g in REDO:
        desc, noun = REDO[g]
    return (f'The same nine cats, unchanged, now each dressed in {desc} on its body. Keep every head, ear, tail and paw '
            f'exactly as painted. The {noun} is painted in the same soft painterly style and gentle lighting as the cats, '
            'with visible brushwork.')
def rest_prompt(g, redo=False):
    """For a sheet from sheet.py's build_rest: the curled-up and stretching cats dressed as the two below them are.
    `redo`: for a try that dressed only the stretching cat's hips, or nothing."""
    _, desc, noun = GARMENTS[g]
    if g in REDO:
        desc, noun = REDO[g]
    return (f'The same four cats, unchanged. The two cats at the top, one curled up asleep and one stretching, are now dressed '
            f'in {desc} on their bodies, exactly as the two cats below wear it: the same {noun}, its colour, details and fit. '
            f'Curled up, the {noun} covers its back and side, not the tail curled round in front of it. '
            + (f'Stretching, the {noun} covers its shoulders, chest and back down to its hips. ' if redo else '') +
            f'Keep every head, ear, tail and paw exactly as painted. The {noun} is painted in the same soft painterly style and '
            'gentle lighting as the cats, with visible brushwork.')

def rest_requests(g, bodies, media, tint=None, start=700, redo=False):
    """The batch for the curled-up and stretching sheets; media maps '<body>_<tint>_rest_<g>.png' and
    '<body>_rest_mask.png' to their media IDs. Indexed start + the garment's place * 10 + the body's."""
    tint = tint or GARMENTS[g][0]
    return [{'index': start + list(GARMENTS).index(g) * 10 + BODIES.index(b), 'params': {
        'model': 'ideogram_4_5', 'quality': 'high', 'resolution': '2k', 'aspect_ratio': '1:1', 'magic_prompt': 'off',
        'prompt': rest_prompt(g, redo),
        'medias': [{'role': 'image_references', 'value': media[f'{b}_{tint}_rest_{g}.png']}, {'role': 'mask', 'value': media[f'{b}_rest_mask.png']}]}}
        for b in bodies]

if __name__ == '__main__':
    # python requests.py <garment> [<tint> <body,body>] - a redo of some bodies, on another tint if need be
    g = sys.argv[1]
    media = json.load(open(f'{WORK}/media.json'))
    tint = sys.argv[2] if len(sys.argv) > 2 else GARMENTS[g][0]
    only = sys.argv[3].split(',') if len(sys.argv) > 3 else BODIES
    reqs = []
    for i, b in enumerate(BODIES):
        if b not in only:
            continue
        reqs.append({'index': list(GARMENTS).index(g) * 10 + i + (100 if len(sys.argv) > 3 else 0), 'params': {
            'model': 'ideogram_4_5', 'quality': 'high', 'resolution': '2k', 'aspect_ratio': '1:1', 'magic_prompt': 'off',
            'prompt': prompt(g, len(sys.argv) > 3),
            'medias': [{'role': 'image_references', 'value': media[f'{b}_{tint}.png']}, {'role': 'mask', 'value': media[f'{b}_mask.png']}]}})
    print(json.dumps(reqs, separators=(',', ':')))
