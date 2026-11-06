"""Freeze and validate reviewed, transitive source/session splits without reading pixels."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import sys

try:
    from .inventory import FORMAT, reserve_output, sha256, sources_from, write_json
except ImportError:
    from inventory import FORMAT, reserve_output, sha256, sources_from, write_json

SPLITS = {'train', 'validation', 'test', 'quarantine'}
SHA = re.compile(r'[0-9a-f]{64}')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def content_id(value):
    require(isinstance(value, str) and SHA.fullmatch(value), 'Expected full SHA-256 content ID')
    return value


def strings(value, field):
    require(isinstance(value, list) and all(isinstance(v, str) and v.strip() for v in value),
            f'{field} must be a list of nonempty strings')
    require(len(value) == len(set(value)), f'Duplicate {field}')
    return value


class Groups:
    def __init__(self):
        self.parent = {}

    def find(self, item):
        self.parent.setdefault(item, item)
        if self.parent[item] != item:
            self.parent[item] = self.find(self.parent[item])
        return self.parent[item]

    def join(self, tokens):
        for token in tokens:
            self.parent[self.find(token)] = self.find(tokens[0])


def build(inventory, provenance, priors=()):
    require(inventory.get('format') == FORMAT and inventory.get('complete') is True,
            'A complete footage-inventory/1 is required')
    sources = inventory.get('sources', [])
    require(sources == sources_from(inventory['files']), 'Sources disagree with verified inventory rows')
    by_id = {content_id(s['sha256']): s for s in sources}
    require(len(by_id) == len(sources), 'Duplicate source ID')
    require(provenance.get('format') == 'footage-provenance/1', 'Expected footage-provenance/1')
    reviews = provenance.get('sources')
    require(isinstance(reviews, dict) and set(reviews) <= set(by_id), 'Unknown provenance source ID')
    graph = Groups()
    requested, blockers, exposures = {}, {}, {}
    for sha, source in by_id.items():
        row = reviews.get(sha, {})
        require(isinstance(row, dict), 'Provenance source must be an object')
        reviewed = row.get('reviewed', False)
        require(type(reviewed) is bool, 'reviewed must be boolean')
        split = row.get('requested_split', 'quarantine')
        exposure = row.get('exposure', 'unknown')
        require(split in SPLITS, 'Unknown split')
        require(exposure in {'unknown', 'unseen', 'opened'}, 'Unknown exposure')
        recordings = strings(row.get('recording_ids', []), 'recording_ids')
        sessions = strings(row.get('session_ids', []), 'session_ids')
        parents = strings(row.get('parent_sha256', []), 'parent_sha256')
        for parent in parents:
            content_id(parent)
            require(parent != sha, 'A source cannot be its own parent')
        if reviewed:
            require(recordings and sessions and isinstance(row.get('reviewer'), str) and row['reviewer'].strip()
                    and isinstance(row.get('evidence'), str) and row['evidence'].strip(),
                    'Reviewed sources require recording/session IDs, reviewer and evidence')
        requested[sha] = split
        exposures[sha] = exposure
        blockers[sha] = [] if reviewed else ['unreviewed_provenance']
        # Unresolved derivative relationships cannot establish an independent source.
        if any(parent not in by_id for parent in parents):
            blockers[sha].append('parent_missing_from_inventory')
        tokens = ['sha256:' + sha] + ['sha256:' + p for p in parents]
        tokens += ['recording:' + s for s in recordings] + ['session:' + s for s in sessions]
        tokens += ['upload:' + s for s in strings(source.get('upload_hints', []), 'upload_hints')]
        graph.join(tokens)

    # Frozen groups carry all their identities, even if an old alias/source disappeared.
    frozen = []
    prior_opened = set()
    for prior in priors:
        require(prior.get('format') == 'footage-split/1', 'Expected footage-split/1 prior plan')
        seen = set()
        groups = prior.get('groups')
        require(isinstance(groups, list), 'Prior plan requires groups')
        for group in groups:
            tokens = strings(group['identities'], 'prior identities')
            members = strings(group['sources'], 'prior sources')
            split = group['split']
            require(tokens and members and split in SPLITS, 'Invalid prior group')
            for sha in members:
                content_id(sha)
                require(sha not in seen and 'sha256:' + sha in tokens, 'Invalid prior membership')
                seen.add(sha)
            graph.join(tokens)
            if split != 'quarantine':
                frozen.append((tokens[0], split))
        require(set(prior['exposure']) == seen, 'Prior exposure must cover all prior sources')
        for sha, exposure in prior['exposure'].items():
            require(exposure in {'unknown', 'opened', 'unseen'}, 'Invalid prior exposure')
            if exposure == 'opened':
                prior_opened.add(sha)
    for sha in prior_opened & set(by_id):
        require(exposures[sha] != 'unseen', 'Previously opened source cannot become unseen')
        exposures[sha] = 'opened'

    components = {}
    for sha in by_id:
        components.setdefault(graph.find('sha256:' + sha), []).append(sha)
    groups = []
    for root, members in sorted(components.items(), key=lambda pair: min(pair[1])):
        members.sort()
        identities = sorted(t for t in graph.parent if graph.find(t) == root)
        reasons = sorted({reason for sha in members for reason in blockers[sha]})
        choices = {requested[s] for s in members}
        # Any quarantine request or unresolved member contains the whole component.
        if reasons or 'quarantine' in choices:
            chosen = 'quarantine'
            if 'quarantine' in choices:
                reasons = sorted(set(reasons) | {'requested_quarantine'})
        else:
            require(len(choices) == 1, 'Connected recording/session/parent/upload group crosses splits')
            chosen = next(iter(choices))
        old_choices = {split for token, split in frozen if graph.find(token) == root}
        require(len(old_choices) <= 1, 'Previously frozen partitions overlap through new provenance')
        require(not old_choices or chosen in old_choices, 'Cannot reassign a previously frozen group')
        if chosen == 'test':
            require(all(exposures[s] == 'unseen' for s in members)
                    and not any('sha256:' + s in identities for s in prior_opened),
                    'Fresh test group contains opened or unknown-exposure sources')
        groups.append({'group_id': hashlib.sha256('\n'.join(identities).encode()).hexdigest(),
                       'identities': identities, 'sources': members, 'split': chosen, 'blockers': reasons})
    return {'format': 'footage-split/1', 'groups': groups, 'exposure': exposures,
            'summary': {split: sum(len(g['sources']) for g in groups if g['split'] == split)
                        for split in sorted(SPLITS)},
            'limitations': ['SHA-256 proves byte identity, not independent scenes or athletes.',
                            'Reviewed provenance and exposure are attestations, not automatically verified facts.',
                            'This plan neither reads test pixels nor authorizes fitting or test evaluation.']}


def read_json(path):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, f'Duplicate JSON key: {key}')
            result[key] = value
        return result
    return json.loads(Path(path).read_text(), object_pairs_hook=pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Nonfinite JSON value')))


def bound_plan(inventory_path, provenance_path, prior_paths):
    # Read bytes once so the hashes and parsed data cannot describe different versions.
    paths = [inventory_path, provenance_path, *prior_paths]
    documents, hashes = [], []
    for path in paths:
        raw = Path(path).read_bytes()
        hashes.append(hashlib.sha256(raw).hexdigest())
        # Reject duplicate keys consistently, including for inputs read from bytes.
        def unique(items):
            result = {}
            for key, value in items:
                require(key not in result, f'Duplicate JSON key: {key}')
                result[key] = value
            return result
        documents.append(json.loads(raw, object_pairs_hook=unique))
    result = build(documents[0], documents[1], documents[2:])
    result['inputs'] = {'inventory_sha256': hashes[0], 'provenance_sha256': hashes[1],
                        'prior_plan_sha256': hashes[2:]}
    result['tool_sha256'] = sha256(Path(__file__))
    return result, documents[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['plan', 'validate'])
    parser.add_argument('--inventory', required=True, type=Path)
    parser.add_argument('--provenance', required=True, type=Path)
    parser.add_argument('--prior-plan', action='append', default=[], type=Path)
    parser.add_argument('--output', type=Path, help='New directory for plan')
    parser.add_argument('--plan', type=Path, help='Existing plan to validate')
    args = parser.parse_args()
    try:
        result, inventory = bound_plan(args.inventory, args.provenance, args.prior_plan)
        if args.action == 'plan':
            require(args.output is not None, 'plan requires --output')
            _, output = reserve_output(Path(inventory['root']), args.output)
            write_json(output / 'split.json', result)
        else:
            require(args.plan is not None, 'validate requires --plan')
            require(read_json(args.plan) == result, 'Plan does not match its bound inputs and current safeguards')
        print(json.dumps(result['summary'], sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
        print(f'Split refused: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
