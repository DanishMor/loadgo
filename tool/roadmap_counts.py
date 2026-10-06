#!/usr/bin/env python3
"""Recount docs/ROADMAP_STATUS.md and rewrite its Summary table.

Usage: python3 tool/roadmap_counts.py [--check]
A row is `| CODE | item | Status | where |`; the module is the `## ` heading above.
"""
import re, sys, collections

path = 'docs/ROADMAP_STATUS.md'
text = open(path, encoding='utf-8').read()
lines = text.split('\n')
STATUSES = ['Done', 'Partial', 'Todo-free', 'Paid-or-Later', 'Unsure']
mods = collections.OrderedDict()
cur = None
for l in lines:
    h = re.match(r'^## (\S+) ', l)
    if h:
        cur = h.group(1)
        continue
    if l.startswith('## Competitor'):
        cur = None
    r = re.match(r'^\| ([A-Z]+\d+|P0-\d+) \| .*? \| (Done|Partial|Todo-free|Paid-or-Later|Unsure) \|', l)
    if r and cur:
        mods.setdefault(cur, collections.Counter())[r.group(2)] += 1

names = {}
for l in lines:
    m = re.match(r'^\| (\S+) (.+?) \| (\d+) \|', l)
    if m and m.group(3).isdigit():
        names[m.group(1)] = m.group(2)

out = ['| Module | Items | ' + ' | '.join(STATUSES[:5]) + ' |', '|---|---|---|---|---|---|---|']
tot = collections.Counter()
for k, c in mods.items():
    n = sum(c.values())
    tot.update(c)
    out.append('| %s %s | %d | %s |' % (k, names.get(k, ''), n, ' | '.join(str(c[s]) for s in STATUSES)))
out.append('| **Total** | **%d** | %s |' % (sum(tot.values()), ' | '.join('**%d**' % tot[s] for s in STATUSES)))
if '--check' in sys.argv:
    print('\n'.join(out)); sys.exit(0)
a = next(i for i, l in enumerate(lines) if l.startswith('| Module |'))
b = next(i for i, l in enumerate(lines) if l.startswith('| **Total**'))
lines[a:b + 1] = out
open(path, 'w', encoding='utf-8').write('\n'.join(lines))
print('\n'.join(out[-1:]))
