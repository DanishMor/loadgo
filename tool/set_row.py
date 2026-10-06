#!/usr/bin/env python3
"""Set status and 'where' text of rows in docs/ROADMAP_STATUS.md.
Usage: python3 tool/set_row.py CODE STATUS "where text" [CODE STATUS "text" ...]"""
import re, sys
p = 'docs/ROADMAP_STATUS.md'
lines = open(p, encoding='utf-8').read().split('\n')
a = sys.argv[1:]
for i in range(0, len(a), 3):
    code, status, where = a[i:i + 3]
    assert status in ('Done', 'Partial', 'Todo-free', 'Paid-or-Later', 'Unsure'), status
    for n, l in enumerate(lines):
        m = re.match(r'^\| %s \| (.*) \| (Done|Partial|Todo-free|Paid-or-Later|Unsure) \| .* \|$' % re.escape(code), l)
        if m:
            lines[n] = '| %s | %s | %s | %s |' % (code, m.group(1), status, where)
            break
    else:
        sys.exit('row not found: ' + code)
open(p, 'w', encoding='utf-8').write('\n'.join(lines))
