import json, sys
from PIL import Image
from extract import align_ref, REF_GREY
state = json.load(open('pipeline_state.json'))
ref = REF_GREY if isinstance(REF_GREY, Image.Image) else Image.open(REF_GREY).convert('RGB')
room = sys.argv[1]
out = {}
for k, v in state.items():
    if not k.startswith(room + ':') or 'pos' not in v: continue
    item = k.split(':')[1]
    gen = Image.open(f'gen/{room}/{item}.png').convert('RGB')
    _, (sx, sy, dx, dy) = align_ref(gen, ref, with_transform=True)
    x, y = v['pos']; w, h = v['size']
    rx, ry = (x - dx) / sx, (y - dy) / sy
    out[item] = {'x': round(rx), 'y': round(ry), 'w': round(w / sx), 'h': round(h / sy), 'bottom': round(ry + h / sy), 'cx': round(rx + w / sx / 2), 's': round((sx + sy) / 2, 3)}
    print(item, out[item])
json.dump(out, open(f'demo_pos_{room}.json', 'w'), indent=1)
