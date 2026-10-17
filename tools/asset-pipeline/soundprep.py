"""Trim, clean and level the openly licensed cat recordings into the game's cat sounds."""
import subprocess, json, numpy as np
from scipy.io import wavfile
SR = 44100
sel = {x['file'].split('.')[0]: x for x in json.load(open('selected.json'))}
PLAN = [  # out name, source, start, end, extra ffmpeg filter
 ('cat_meow_short',    'c04', 4.60, 5.25, ''),
 ('cat_meow_long',     'c04', 7.88, 9.32, ''),
 ('cat_meow_question', 'c00', 0.00, 1.155, ''),
 ('cat_meow_hungry',   'c01', 0.03, 0.62, ''),
 ('cat_meow_pleading', 'c09', 0.25, 1.20, ''),
 ('cat_meow_soft',     'c07', 0.00, 1.15, ',highpass=f=300'),
 ('cat_chirp',         'c05', 19.52, 19.95, ',afftdn=nf=-30'),
 ('cat_trill',         'c05', 22.38, 23.02, ',afftdn=nf=-30'),
 ('cat_grumble',       'c01', 6.42, 6.90, ',lowpass=f=3000'),
 ('cat_hiss',          'c03', 0.92, 2.08, ''),
 ('cat_purr_loop',     'c12', 0.60, 9.60, ''),
]
man = {}
for name, src, s0, s1, extra in PLAN:
    f = sel[src]['file']
    flt = f'atrim={s0}:{s1},asetpts=PTS-STARTPTS,highpass=f=110{extra}'
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', f, '-af', flt, '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'], capture_output=True).stdout
    x = np.frombuffer(raw, np.float32).astype(np.float64)
    x -= x.mean()
    if name.endswith('_loop'):
        n = int(0.5 * SR); w = np.linspace(0, 1, n)
        x = np.concatenate([x[-n:] * (1 - w) + x[:n] * w, x[n:-n]])
    else:
        fi = int(0.008 * SR); fo = int(0.03 * SR)
        x[:fi] *= np.linspace(0, 1, fi); x[-fo:] *= np.linspace(1, 0, fo)
    x = x / (np.abs(x).max() + 1e-9) * 0.85
    wavfile.write(f'out/{name}.wav', SR, (x * 32767).astype(np.int16))
    s = sel[src]
    man[name] = {'seconds': round(len(x) / SR, 2), 'loop': name.endswith('_loop'), 'source': 'Wikimedia Commons recording',
                 'title': s['title'], 'url': 'https://commons.wikimedia.org/wiki/' + s['title'].replace(' ', '_'),
                 'author': s['artist'].strip(), 'license': s['license'], 'excerpt': f'{s0}-{s1} s'}
    print(name, man[name]['seconds'], s['license'])
json.dump(man, open('out/cat_sounds_credits.json', 'w'), indent=1)
