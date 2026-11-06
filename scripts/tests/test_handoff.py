"""Exercise real Git staging without touching the working checkout or GitHub."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'handoff.sh'

class HandoffIsolation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'docs/handoff').mkdir(parents=True)
        shutil.copy2(SCRIPT, self.root / 'scripts/handoff.sh')
        (self.root / 'docs/handoff/STATUS.md').write_text('''<!-- STATE:BEGIN -->
owner: codex
heartbeat: 2026-01-01T00:00:00Z
<!-- STATE:END -->
<!-- newest first; scripts/handoff.sh prepends entries below this line -->
''' + 'old log\n' * 10000)
        self.git('init', '-q')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'user.name', 'Test')
        for name in ['unrelated', 'chosen file', 'unstaged']:
            (self.root / name).write_text('before')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        for name in ['unrelated', 'chosen file', 'unstaged']:
            (self.root / name).write_text('after')
        self.git('add', 'unrelated')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True).strip()

    def handoff(self, *args):
        env = {**os.environ, 'HANDOFF_PUSH':'0', 'HANDOFF_POST_ISSUE':'0',
               'HANDOFF_SYNC':'0', 'HANDOFF_READ_ISSUE':'0'}
        return subprocess.run(['bash', 'scripts/handoff.sh', *args], cwd=self.root,
                              env=env, capture_output=True, text=True)

    def test_status_no_sigpipe_or_mutation(self):
        before = self.git('status', '--porcelain')
        self.assertEqual(self.handoff('status').returncode, 0)
        self.assertEqual(self.git('status', '--porcelain'), before)

    def test_checkpoint_commits_only_explicit_paths_preserving_index(self):
        result = self.handoff('checkpoint', 'codex', 'done', 'next', '--paths', 'chosen file')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(self.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').splitlines()),
                         {'docs/handoff/STATUS.md', 'chosen file'})
        self.assertEqual(self.git('diff', '--cached', '--name-only'), 'unrelated')
        self.assertEqual(self.git('diff', '--name-only'), 'unstaged')

    def test_release_never_sweeps_work(self):
        result = self.handoff('release', 'codex', 'done', 'next')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git('show', '--format=', '--name-only', 'HEAD'), 'docs/handoff/STATUS.md')
        self.assertEqual(self.git('diff', '--cached', '--name-only'), 'unrelated')

    def test_heartbeat_does_not_commit(self):
        before = self.git('rev-parse', 'HEAD')
        self.assertEqual(self.handoff('heartbeat', 'codex').returncode, 0)
        self.assertEqual(self.git('rev-parse', 'HEAD'), before)
        self.assertNotEqual(self.handoff('heartbeat', 'claude').returncode, 0)

    def test_process_record_requires_owner_and_does_not_commit(self):
        before = self.git('rev-parse', 'HEAD')
        self.assertEqual(self.handoff('processes', 'codex', 'test job 123').returncode, 0)
        self.assertIn('active_processes: test job 123', self.handoff('status').stdout)
        self.assertEqual(self.git('rev-parse', 'HEAD'), before)
        self.assertNotEqual(self.handoff('processes', 'claude', 'none').returncode, 0)
