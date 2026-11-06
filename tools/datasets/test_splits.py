import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tools.datasets import inventory as inv, splits


def fixture(count=3):
    rows = []
    for index in range(count):
        sha = hashlib.sha256(str(index).encode()).hexdigest()
        rows.append({'path': f'{index}.mp4', 'state': 'verified', 'disposition': 'video',
                     'sha256': sha, 'signature': {'size': 10},
                     'media': {'duration_s': 1, 'streams': [{'codec_type': 'video'}]}})
    inventory = {'format': inv.FORMAT, 'complete': True, 'files': rows,
                 'sources': inv.sources_from(rows)}
    ids = [r['sha256'] for r in inventory['sources']]
    provenance = {'format': 'footage-provenance/1', 'sources': {
        sha: {'reviewed': True, 'reviewer': 'fixture reviewer', 'evidence': 'synthetic session log',
              'recording_ids': [f'recording-{i}'], 'session_ids': [f'session-{i}'],
              'parent_sha256': [], 'exposure': 'unseen', 'requested_split': split}
        for i, (sha, split) in enumerate(zip(ids, ['train', 'validation', 'test']))}}
    return inventory, provenance, ids


class SplitTests(unittest.TestCase):
    def setUp(self):
        self.inventory, self.provenance, self.ids = fixture()

    def test_distinct_reviewed_sessions_and_determinism(self):
        a = splits.build(self.inventory, self.provenance)
        b = splits.build(self.inventory, self.provenance)
        self.assertEqual(a, b)
        self.assertEqual(a['summary'], {'quarantine': 0, 'test': 1, 'train': 1, 'validation': 1})

    def test_unknown_never_automatically_trains(self):
        plan = splits.build(self.inventory, {'format': 'footage-provenance/1', 'sources': {}})
        self.assertEqual(plan['summary']['quarantine'], 3)

    def test_partial_inventory_and_invalid_review_refused(self):
        self.inventory['complete'] = False
        with self.assertRaisesRegex(ValueError, 'complete'):
            splits.build(self.inventory, self.provenance)
        self.inventory['complete'] = True
        self.provenance['sources'][self.ids[0]]['session_ids'] = []
        with self.assertRaisesRegex(ValueError, 'recording/session'):
            splits.build(self.inventory, self.provenance)

    def test_exact_alias_does_not_add_source(self):
        row = copy.deepcopy(self.inventory['files'][0])
        row['path'] = 'renamed.mp4'
        self.inventory['files'].append(row)
        self.inventory['sources'] = inv.sources_from(self.inventory['files'])
        plan = splits.build(self.inventory, self.provenance)
        self.assertEqual(sum(plan['summary'].values()), 3)

    def test_sources_cannot_disagree_with_files(self):
        self.inventory['sources'].pop()
        with self.assertRaisesRegex(ValueError, 'disagree'):
            splits.build(self.inventory, self.provenance)

    def test_session_recording_and_upload_conflicts(self):
        for field in ['session_ids', 'recording_ids', 'upload_hints']:
            inventory, provenance, ids = fixture()
            if field == 'upload_hints':
                # Both aliases carry the same downloader upload hint, despite different bytes.
                inventory['files'][0]['path'] = 'abcdefghijk - original.mp4'
                inventory['files'][1]['path'] = 'abcdefghijk - reencoded.mp4'
                inventory['sources'] = inv.sources_from(inventory['files'])
            else:
                provenance['sources'][ids[0]][field] = ['shared']
                provenance['sources'][ids[1]][field] = ['shared']
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'crosses splits'):
                splits.build(inventory, provenance)

    def test_parent_transitivity(self):
        reviews = self.provenance['sources']
        reviews[self.ids[1]]['parent_sha256'] = [self.ids[0]]
        reviews[self.ids[2]]['parent_sha256'] = [self.ids[1]]
        with self.assertRaisesRegex(ValueError, 'crosses splits'):
            splits.build(self.inventory, self.provenance)
        for review in reviews.values():
            review['requested_split'] = 'train'
        plan = splits.build(self.inventory, self.provenance)
        self.assertEqual(len(plan['groups']), 1)
        self.assertEqual(plan['summary']['train'], 3)

    def test_unknown_member_quarantines_entire_connected_group(self):
        a, b = self.ids[:2]
        self.provenance['sources'][b]['parent_sha256'] = [a]
        self.provenance['sources'][a]['reviewed'] = False
        plan = splits.build(self.inventory, self.provenance)
        self.assertEqual(plan['summary']['quarantine'], 2)

    def test_missing_parent_quarantines(self):
        self.provenance['sources'][self.ids[0]]['parent_sha256'] = ['f'*64]
        plan = splits.build(self.inventory, self.provenance)
        self.assertEqual(plan['summary']['quarantine'], 1)

    def test_fresh_test_rejects_unknown_and_opened(self):
        for exposure in ['unknown', 'opened']:
            self.provenance['sources'][self.ids[2]]['exposure'] = exposure
            with self.subTest(exposure=exposure), self.assertRaisesRegex(ValueError, 'Fresh test'):
                splits.build(self.inventory, self.provenance)

    def test_prior_partition_cannot_move(self):
        prior = splits.build(self.inventory, self.provenance)
        self.provenance['sources'][self.ids[0]]['requested_split'] = 'validation'
        with self.assertRaisesRegex(ValueError, 'reassign'):
            splits.build(self.inventory, self.provenance, [prior])

    def test_prior_group_identities_survive_different_payloads(self):
        prior = splits.build(self.inventory, self.provenance)
        # A new payload inherits an old recording relationship without a shared SHA.
        inventory, provenance, ids = fixture(1)
        new_sha = 'e'*64
        inventory['files'][0]['sha256'] = new_sha
        inventory['sources'] = inv.sources_from(inventory['files'])
        review = next(iter(provenance['sources'].values()))
        review['recording_ids'] = self.provenance['sources'][self.ids[0]]['recording_ids']
        review['requested_split'] = 'test'
        provenance['sources'] = {new_sha: review}
        with self.assertRaisesRegex(ValueError, 'reassign'):
            splits.build(inventory, provenance, [prior])

    def test_prior_opened_cannot_be_cleared(self):
        self.provenance['sources'][self.ids[0]]['exposure'] = 'opened'
        prior = splits.build(self.inventory, self.provenance)
        self.provenance['sources'][self.ids[0]]['exposure'] = 'unseen'
        with self.assertRaisesRegex(ValueError, 'Previously opened'):
            splits.build(self.inventory, self.provenance, [prior])

    def test_new_link_between_frozen_splits_refused(self):
        prior = splits.build(self.inventory, self.provenance)
        a, b = self.ids[:2]
        self.provenance['sources'][b]['parent_sha256'] = [a]
        self.provenance['sources'][b]['requested_split'] = 'train'
        with self.assertRaisesRegex(ValueError, 'frozen partitions overlap'):
            splits.build(self.inventory, self.provenance, [prior])

    def test_unknown_sources_malformed_ids_and_duplicates_refused(self):
        self.provenance['sources']['invented'] = {}
        with self.assertRaisesRegex(ValueError, 'Unknown provenance'):
            splits.build(self.inventory, self.provenance)

        del self.provenance['sources']['invented']
        self.provenance['sources'][self.ids[0]]['parent_sha256'] = ['short']
        with self.assertRaisesRegex(ValueError, 'full SHA'):
            splits.build(self.inventory, self.provenance)

    def test_cli_rejects_modified_plan_and_changed_bound_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.inventory['root'] = str(root/'originals')
            (root/'originals').mkdir()
            inventory_path, provenance_path = root/'inventory.json', root/'provenance.json'
            inventory_path.write_text(json.dumps(self.inventory))
            provenance_path.write_text(json.dumps(self.provenance))
            arguments = ['--inventory', str(inventory_path), '--provenance', str(provenance_path)]
            command = [sys.executable, str(Path(splits.__file__))]
            output = root/'study'
            result = subprocess.run(command + ['plan', *arguments, '--output', str(output)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            validate = command + ['validate', *arguments, '--plan', str(output/'split.json')]
            self.assertEqual(subprocess.run(validate, capture_output=True).returncode, 0)
            original = (output/'split.json').read_text()
            document = json.loads(original)
            document['groups'][0]['split'] = 'test'
            (output/'split.json').write_text(json.dumps(document))
            self.assertEqual(subprocess.run(validate, capture_output=True).returncode, 2)
            (output/'split.json').write_text(original)
            provenance_path.write_text(json.dumps(self.provenance, indent=2))
            self.assertEqual(subprocess.run(validate, capture_output=True).returncode, 2)

    def test_bound_input_change_and_plan_tampering(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inventory_path, provenance_path = root/'inventory.json', root/'provenance.json'
            inventory_path.write_text(json.dumps(self.inventory))
            provenance_path.write_text(json.dumps(self.provenance))
            plan, _ = splits.bound_plan(inventory_path, provenance_path, [])
            provenance_path.write_text(json.dumps(self.provenance, indent=2))
            changed, _ = splits.bound_plan(inventory_path, provenance_path, [])
            self.assertNotEqual(plan['inputs'], changed['inputs'])
            corrupted = copy.deepcopy(changed)
            corrupted['groups'][0]['split'] = 'test'
            self.assertNotEqual(corrupted, changed)
            provenance_path.write_text('{"sources": {}, "sources": {}}')
            with self.assertRaisesRegex(ValueError, 'Duplicate JSON'):
                splits.bound_plan(inventory_path, provenance_path, [])


if __name__ == '__main__':
    unittest.main()
