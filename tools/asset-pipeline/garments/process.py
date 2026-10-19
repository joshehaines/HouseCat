"""Downloads a garment's finished edits, cuts out every layer, and makes one check-sheet for the garment.
python process.py <garment> '<jobs json from jobs_wait>' [--better] [--tint=<tint>]
(a job's index is the garment's place in requests.GARMENTS * 10 + the body's in BODIES, plus 100 for a redo)
--tint: the sheet the edit was made on, when not the garment's usual one (a redo on another tint)
--better: a second try at some bodies; a pose or view is replaced only where the new one covers more of the cat."""
import json, os, subprocess, sys
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, 'work')  # sheets, edits, layers and check-sheets (not in git)
sys.path.insert(0, HERE)
from requests import BODIES, GARMENTS  # noqa: E402
import extract  # noqa: E402

g = sys.argv[1]
jobs = json.loads(sys.argv[2])
jobs = jobs['jobs'] if isinstance(jobs, dict) else jobs
tint = next((a[7:] for a in sys.argv if a.startswith('--tint=')), GARMENTS[g][0])
os.makedirs(f'{WORK}/out', exist_ok=True)
done = json.load(open(f'{WORK}/jobs.json')) if os.path.exists(f'{WORK}/jobs.json') else {}
for j in jobs:
    if j.get('status') != 'completed':
        print('not done', j); continue
    body = BODIES[j['index'] % 10]
    path = f'{WORK}/out/{g}_{body}.png'
    subprocess.run(['curl', '-sS', '-o', path, j['result_url']], check=True)
    done[f'{g}:{body}'] = {'job_id': j['job_id'], 'url': j['result_url']}
    if '--better' in sys.argv:
        path_new = path.replace('.png', '_retry.png')
        os.replace(path, path_new)
        r = extract.extract_better(body, tint, g, path_new)
    else:
        r = extract.extract(body, tint, g, path)
    print(body, r)
    extract.preview(body, g, f'{WORK}/out/preview_{g}_{body}.png')
json.dump(done, open(f'{WORK}/jobs.json', 'w'), indent=1)
rows = [Image.open(f'{WORK}/out/preview_{g}_{b}.png') for b in BODIES if os.path.exists(f'{WORK}/out/preview_{g}_{b}.png')]
if rows:
    w = max(r.width for r in rows)
    sheet = Image.new('RGB', (w, sum(r.height for r in rows)), (40, 40, 40))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height
    sheet.resize((sheet.width // 2, sheet.height // 2)).save(f'{WORK}/out/check_{g}.png')
