"""Copies a garment's layers into the repo: the masters into assets/outfits/body/, the app's HEIC copies (0.4, as
build_app_art.py makes them) into App/Art/outfits/body/, and their entries in App/Art/art.json and assets/manifest.json.
python install.py <garment> [...]"""
import glob, json, os, shutil, subprocess, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, 'work')  # sheets, edits, layers and check-sheets (not in git)
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
SCALE, QUALITY = 0.4, '82'

art_path, man_path = f'{REPO}/App/Art/art.json', f'{REPO}/assets/manifest.json'
art, man = json.load(open(art_path)), json.load(open(man_path))
os.makedirs(f'{REPO}/assets/outfits/body', exist_ok=True)
os.makedirs(f'{REPO}/App/Art/outfits/body', exist_ok=True)
total = 0
for g in sys.argv[1:]:
    files = sorted(glob.glob(f'{WORK}/layers/{g}/outfit_{g}_*.png'))
    assert len(files) == 72, (g, len(files))
    for src in files:
        name = os.path.basename(src)
        rel = f'outfits/body/{name}'
        dst = f'{REPO}/assets/{rel}'
        shutil.copyfile(src, dst)
        w, h = Image.open(dst).size
        heic = rel[:-4] + '.heic'
        subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', QUALITY, '-z', str(max(1, round(h * SCALE))),
                        str(max(1, round(w * SCALE))), dst, '--out', f'{REPO}/App/Art/{heic}'], capture_output=True, check=True)
        total += os.path.getsize(f'{REPO}/App/Art/{heic}')
        art['files'][rel] = {'master': [w, h], 'scale': SCALE, 'file': heic}
        man['files'][rel] = {'class': 'outfits', 'px': [w, h]}
    print(g, len(files), 'layers')
with open(art_path, 'w') as f:
    json.dump(art, f, indent=1, sort_keys=True)
    f.write('\n')
with open(man_path, 'w') as f:
    json.dump(man, f, indent=1)
    f.write('\n')
print(f'{total / 1e6:.1f} MB of HEIC')
