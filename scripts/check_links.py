#!/usr/bin/env python3
"""Check relative Markdown file targets in public documentation (not web URLs)."""
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parents[1]
files = list(root.glob('*.md')) + list((root / 'docs').rglob('*.md')) + [root / 'apps/strathvision/README.md']
errors = []
for path in files:
    # Fenced code contains illustrative links, not navigation.
    text = re.sub(r'```.*?```', '', path.read_text(), flags=re.S)
    for match in re.finditer(r'\]\(([^\s)]+)(?:\s+"[^"]*")?\)', text):
        target = match[1].strip('<>')
        if urlsplit(target).scheme or target.startswith(('#', '/')):
            continue
        relative = unquote(target.split('#', 1)[0])
        if relative and not (path.parent / relative).exists():
            errors.append(f'{path.relative_to(root)}: {target}')
if errors:
    raise SystemExit('Broken relative links:\n' + '\n'.join(errors))
print(f'Checked relative file links in {len(files)} Markdown documents. Web URLs and heading anchors are not checked.')
