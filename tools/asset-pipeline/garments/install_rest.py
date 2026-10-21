"""Installs chosen curled-up and stretching layers (from work/cand/rest/<garment>_<body>_<index>/) into the repo: the
masters into assets/outfits/body/, the app's HEIC copies (0.4) into App/Art/outfits/body/, and their entries in
App/Art/art.json and assets/manifest.json.
python install_rest.py '<[[garment, body, pose, index], ...]>'"""
import json, os, shutil, subprocess, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, 'work')
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
SCALE, QUALITY = 0.4, '82'

art_path, man_path = f'{REPO}/App/Art/art.json', f'{REPO}/assets/manifest.json'
art, man = json.load(open(art_path)), json.load(open(man_path))
for g, b, pose, idx in json.loads(sys.argv[1]):
    name = f'outfit_{g}_{b}_{pose}.png'
    src = f'{WORK}/cand/rest/{g}_{b}_{idx}/{name}'
    rel = f'outfits/body/{name}'
    shutil.copyfile(src, f'{REPO}/assets/{rel}')
    w, h = Image.open(src).size
    heic = rel[:-4] + '.heic'
    subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', QUALITY, '-z', str(max(1, round(h * SCALE))),
                    str(max(1, round(w * SCALE))), src, '--out', f'{REPO}/App/Art/{heic}'], capture_output=True, check=True)
    art['files'][rel] = {'master': [w, h], 'scale': SCALE, 'file': heic}
    man['files'][rel] = {'class': 'outfits', 'px': [w, h]}
    print('installed', rel)
with open(art_path, 'w') as f:
    json.dump(art, f, indent=1, sort_keys=True)
    f.write('\n')
with open(man_path, 'w') as f:
    json.dump(man, f, indent=1)
    f.write('\n')
