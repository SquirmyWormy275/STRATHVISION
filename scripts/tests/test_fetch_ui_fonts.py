"""Cloud runners must authenticate font requests and retain pinned-content checks."""
import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'fetch_ui_fonts.py'
spec = importlib.util.spec_from_file_location('fetch_ui_fonts', SCRIPT)
fonts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fonts)


class FontDownloads(unittest.TestCase):
    def response(self, data):
        return io.BytesIO(json.dumps({'encoding': 'base64',
                                     'content': base64.b64encode(data).decode()}).encode())

    def test_ci_authentication_avoids_shared_anonymous_api_quota(self):
        data = b'fixture-font'
        with patch.dict(os.environ, {'GH_TOKEN': 'fixture-job-token'}, clear=True), \
                patch.object(fonts, 'urlopen', return_value=self.response(data)) as fetch:
            self.assertEqual(fonts.fetch('google/fonts', fonts.blob_sha(data)), data)
        request = fetch.call_args.args[0]
        self.assertEqual(request.get_header('Authorization'), 'Bearer fixture-job-token')
        self.assertTrue(request.full_url.startswith('https://api.github.com/repos/google/fonts/git/blobs/'))

    def test_local_download_works_without_a_token_and_still_rejects_changed_content(self):
        data = b'fixture-font'
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(fonts, 'urlopen', return_value=self.response(data)) as fetch:
            self.assertEqual(fonts.fetch('google/fonts', fonts.blob_sha(data)), data)
        self.assertIsNone(fetch.call_args.args[0].get_header('Authorization'))
        with patch.dict(os.environ, {'GH_TOKEN': 'fixture-job-token'}, clear=True), \
                patch.object(fonts, 'urlopen', side_effect=lambda *a, **k: self.response(b'changed')), \
                patch.object(fonts.time, 'sleep'):
            with self.assertRaisesRegex(ValueError, 'pinned Git blob'):
                fonts.fetch('google/fonts', fonts.blob_sha(data))
