#!/usr/bin/env python3
"""Summarize LCOV executable lines; exclude generated Dart and test files."""
from pathlib import Path
import sys

print('| Suite | Hit lines | Executable lines | Coverage |')
print('|---|---:|---:|---:|')
for name in sys.argv[1:]:
    covered = total = 0
    include = False
    for line in Path(name).read_text().splitlines():
        if line.startswith('SF:'):
            source = line[3:]
            include = not source.endswith('.g.dart') and '/test/' not in source
        elif include and line.startswith('DA:'):
            count = int(line.split(',')[1])
            total += 1
            covered += count > 0
    if not total:
        raise SystemExit(f'No executable source lines in {name}')
    print(f'| {name.split("/coverage/")[0]} | {covered} | {total} | {covered/total:.1%} |')
print('\nLine coverage is a baseline, not evidence of device compatibility or coaching accuracy. Generated Dart is excluded. Native and Python results are reported separately.')
