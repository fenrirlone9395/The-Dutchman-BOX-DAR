#!/usr/bin/env python3
"""Check public prose/data for machine-local paths and raw device identifiers."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
names = subprocess.check_output(
    ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root
).decode().split('\0')
rules = {
    'machine-local home path': re.compile(r'/Users/[^\s/]+|/home/[^\s/]+|[A-Za-z]:\\Users\\[^\\\s]+'),
    'temporary attachment path': re.compile(r'/(?:private/)?var/folders/|/tmp/[^\s`]+'),
    'raw UUID': re.compile(r'\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b', re.I),
    'raw device UID': re.compile(r'\b(?:uid|deviceUID)\s*=\s*(?![<\s])[^\s,;]+', re.I),
}
failures = []
count = 0
for name in sorted(set(names)):
    path = root / name
    if not name or path.suffix.lower() not in {'.md', '.txt', '.csv', '.json'} or not path.is_file():
        continue
    count += 1
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        for label, pattern in rules.items():
            if pattern.search(line):
                # Do not echo potentially private content into logs.
                failures.append(f'{name}:{line_number}: {label}')
if failures:
    print('\n'.join(failures))
    sys.exit(1)
print(f'PASS: {count} public text/data files; no machine-local paths or raw device identifiers')
