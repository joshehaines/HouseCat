"""Queue helpers for the cat-builder generation run.
  python3 cq.py rec <tag>    < submit-response JSON     (records job ids; failed submissions stay pending)
  python3 cq.py wait         -> jobs list (index, job_id) of every cust job submitted but not downloaded
  python3 cq.py got          < jobs_wait JSON           (downloads completed, marks failed)
"""
import json, sys, os, subprocess
STATE = 'pipeline_state.json'


def load(): return json.load(open(STATE))
def save(s): json.dump(s, open(STATE, 'w'), indent=1)


def rec(tag):
    b = json.load(open(f'batch_cust_{tag}.json')); r = json.loads(sys.stdin.read())
    s = load(); n = 0
    for j in r['jobs']:
        name = b['names'][j['index']]
        if j.get('job_id'):
            s[name] = {'job_id': j['job_id'], 'status': 'pending', 'ref': 'surface'}; n += 1
    save(s); print('recorded', n, 'failed', len(r['jobs']) - n)


def wait():
    s = load()
    jobs = [{'index': i, 'job_id': v['job_id']} for i, (k, v) in
            enumerate(sorted((k, v) for k, v in s.items() if k.startswith('cust:')))
            if v.get('job_id') and v.get('status') in ('pending', 'in_progress', 'queued')]
    print(json.dumps(jobs[:12]), len(jobs))


def got():
    raw = sys.stdin.read().strip()
    if raw.startswith('{'): r = json.loads(raw)
    else:   # compact: one 'jobid HHMMSS' per line (completed), or 'jobid FAIL'
        r = {'jobs': []}
        for ln in raw.splitlines():
            jid, ts = ln.split()
            r['jobs'].append({'job_id': jid, 'status': 'failed'} if ts == 'FAIL' else
                             {'job_id': jid, 'status': 'completed', 'result_url':
                              f'https://d8j0ntlcm91z4.cloudfront.net/user_3Dcc1ZJflZl7r9iZWYh62HUtZO6/hf_20261017_{ts}_{jid}.png'})
    s = load()
    byjob = {v['job_id']: k for k, v in s.items() if k.startswith('cust:') and v.get('job_id')}
    os.makedirs('gen/cust', exist_ok=True)
    for j in r['jobs']:
        k = byjob.get(j['job_id'])
        if not k: continue
        if j['status'] == 'completed':
            out = f"gen/cust/{k.split(':', 1)[1]}.png"
            if not os.path.exists(out):
                subprocess.run(['curl', '-sS', '--retry', '4', '--retry-all-errors', '-o', out + '.part', j['result_url']], check=True); os.replace(out + '.part', out)
            s[k]['status'] = 'downloaded'; s[k]['url'] = j['result_url']
        elif j['status'] in ('failed', 'nsfw', 'cancelled'):
            s[k]['status'] = 'failed'; print('FAILED', k)
    save(s)
    left = sum(1 for k, v in s.items() if k.startswith('cust:') and v.get('status') == 'pending')
    print('in flight', left)


if __name__ == '__main__':
    {'rec': lambda: rec(sys.argv[2]), 'wait': wait, 'got': got}[sys.argv[1]]()
