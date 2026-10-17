"""Pipeline bookkeeping: record job ids for a batch, then fetch results and extract sprites."""
import json, sys, os, subprocess
STATE = 'pipeline_state.json'
def load():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}
def save(s): json.dump(s, open(STATE, 'w'), indent=1)

def record(batchfile, jobs_json):
    b = json.load(open(batchfile)); jobs = json.loads(jobs_json)['jobs']
    s = load()
    for j in jobs:
        i = j['index'] - b['requests'][0]['index']
        name = b['names'][i]
        ref = b.get('ref')
        s[name] = {'job_id': j.get('job_id'), 'status': j['status'],
                   'ref': 'grey' if ref == 'd8ab3b05-db3b-4ef7-b3c5-5a0cf5d17e07' else ('cream' if ref in (None, '36f386b7-ba74-47bb-9a65-09c5afa31525') else ref)}
    save(s); print('recorded', len(jobs))

def fetch(wait_json, extract_sprites=True):
    from extract import extract, extract_grey
    s = load(); jobs = json.loads(wait_json)['jobs']
    byjob = {v['job_id']: k for k, v in s.items() if v.get('job_id')}
    for j in jobs:
        if j['status'] != 'completed': continue
        name = byjob.get(j['job_id'])
        if not name: print('unknown job', j['job_id']); continue
        room, item = name.split(':')
        os.makedirs(f'gen/{room}', exist_ok=True); os.makedirs(f'sprites/{room}', exist_ok=True)
        raw = f'gen/{room}/{item}.png'
        if not os.path.exists(raw):
            subprocess.run(['curl', '-sS', '-o', raw, j['result_url']], check=True)
        s[name]['url'] = j['result_url']; s[name]['status'] = 'downloaded'
        if extract_sprites and s[name].get('ref') not in ('grey', 'cream'):
            print(name, 'downloaded (raw)'); continue
        if extract_sprites:
            out = f'sprites/{room}/furn_{room}_{item}.png'
            try:
                r = extract_grey(raw, out) if s[name].get('ref') == 'grey' else extract(raw, out, strip_skirting=False)
                if r:
                    s[name]['sprite'] = out; s[name]['size'] = list(map(int, r[0])); s[name]['pos'] = list(map(int, r[1]))
                    s[name]['coverage'] = float(r[2]); s[name]['status'] = 'extracted'
                else:
                    s[name]['status'] = 'extract_failed'
            except Exception as e:
                s[name]['status'] = 'extract_error: ' + str(e)[:80]
        print(name, s[name]['status'], s[name].get('size'), s[name].get('coverage'))
    save(s)

def fetch_compact(text, extract_sprites=True):
    jobs=[]
    for line in text.strip().splitlines():
        jid, ts = line.split()
        jobs.append({'job_id': jid, 'status': 'completed', 'result_url': f'https://d8j0ntlcm91z4.cloudfront.net/user_3Dcc1ZJflZl7r9iZWYh62HUtZO6/hf_20261017_{ts}_{jid}.png'})
    fetch(json.dumps({'jobs': jobs}), extract_sprites)

if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'record': record(sys.argv[2], sys.stdin.read())
    elif cmd == 'fetchc': fetch_compact(sys.stdin.read(), extract_sprites=(len(sys.argv) < 3 or sys.argv[2] != 'noextract'))
    elif cmd == 'fetch': fetch(sys.stdin.read(), extract_sprites=(len(sys.argv) < 3 or sys.argv[2] != 'noextract'))

def waitlist(batchfile):
    s = load(); b = json.load(open(batchfile))
    return json.dumps([{"index": i, "job_id": s[n]['job_id']} for i, n in enumerate(b['names']) if s.get(n, {}).get('job_id')])
if __name__ == '__main__' and sys.argv[1] == 'waitlist': print(waitlist(sys.argv[2]))
