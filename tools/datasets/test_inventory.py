import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tools.datasets import inventory as inv


MEDIA = {'format': {'duration': '2.5', 'format_name': 'mov'}, 'streams': [
    {'codec_type': 'video', 'codec_name': 'h264', 'width': 1920, 'height': 1080,
     'avg_frame_rate': '30000/1001', 'r_frame_rate': '30/1', 'pix_fmt': 'yuv420p10le',
     'color_transfer': 'arib-std-b67', 'side_data_list': [{'rotation': -90}]},
    {'codec_type': 'audio', 'codec_name': 'aac', 'channels': 2, 'sample_rate': '48000'}]}


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'originals'
        self.root.mkdir()

    def source(self, name='one.mp4', content=b'original'):
        path = self.root / name
        path.write_bytes(content)
        return path

    def test_intermediates_and_archives(self):
        for name in ['clip.f401.mp4', 'clip.f140-19.m4a', 'clip.temp.mp4', 'clip.mp4.part', 'x.crdownload']:
            self.assertEqual(inv.disposition(Path(name)), 'download_intermediate')
        self.assertEqual(inv.disposition(Path('clip.MOV')), 'video')
        self.assertEqual(inv.disposition(Path('note.wav')), 'audio')
        self.assertEqual(inv.disposition(Path('source.zip')), 'archive')

    def test_metadata_rotation_hdr_audio_rational_unknown(self):
        data = inv.metadata(MEDIA)
        video = data['streams'][0]
        self.assertEqual((video['display_width'], video['display_height']), (1080, 1920))
        self.assertAlmostEqual(video['fps'], 29.97002997)
        self.assertEqual(video['color_transfer'], 'arib-std-b67')
        self.assertEqual(data['streams'][1]['channels'], 2)
        for value in ['N/A', '0/0', 'nan', 'inf', None]:
            self.assertIsNone(inv.number(value))
        malformed = copy.deepcopy(MEDIA)
        malformed['streams'][0]['width'] = 0
        with self.assertRaises(ValueError):
            inv.metadata(malformed)

    def test_outputs_cannot_touch_originals_or_existing_run(self):
        for output in [self.root, self.root/'child']:
            with self.assertRaises(ValueError):
                inv.reserve_output(self.root, output)
        link = self.base/'link'
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            inv.reserve_output(self.root, link/'child')
        inv.reserve_output(self.root, self.base/'run')
        with self.assertRaises(FileExistsError):
            inv.reserve_output(self.root, self.base/'run')

    def test_symlink_and_special_file_never_read(self):
        path = self.source()
        (self.root/'alias.mp4').symlink_to(path)
        (self.root/'folder').symlink_to(self.base, target_is_directory=True)
        os.mkfifo(self.root/'fifo.mp4')
        rows, errors = inv.snapshot(self.root)
        self.assertFalse(errors)
        self.assertEqual(sum(r['state'] == 'excluded' for r in rows), 3)
        for name in ['alias.mp4', 'folder/originals/one.mp4', 'fifo.mp4', '../outside']:
            with self.assertRaises((OSError, ValueError)):
                with inv.open_source(self.root, name):
                    self.fail('Unsafe source opened')

    def test_change_before_during_and_after_probe(self):
        path = self.source()
        row = inv.snapshot(self.root)[0][0]
        path.write_bytes(b'new bytes')
        with patch.object(inv, 'probe') as probe:
            self.assertEqual(inv.inspect(self.root, row)['state'], 'changed')
            probe.assert_not_called()
        row = inv.snapshot(self.root)[0][0]
        def change(stream):
            path.write_bytes(b'even newer')
            return inv.metadata(MEDIA)
        with patch.object(inv, 'probe', side_effect=change):
            self.assertEqual(inv.inspect(self.root, row)['state'], 'changed')
        verified = {**row, 'state': 'verified', 'sha256': 'old', 'media': {}}
        final = inv.finalize([verified], inv.snapshot(self.root)[0])[0]
        self.assertEqual(final['state'], 'changed')
        self.assertNotIn('sha256', final)

    def test_removed_and_later_arrivals(self):
        path = self.source()
        before = inv.snapshot(self.root)[0]
        path.unlink()
        self.source('later.mp4')
        result = inv.finalize(before, inv.snapshot(self.root)[0])
        self.assertEqual({r['state'] for r in result}, {'changed', 'arrived_after_snapshot'})

    def test_error_isolation_dedup_and_preservation(self):
        a = self.source()
        self.source('copy.MOV')
        self.source('broken.mp4', b'bad')
        self.source('archive.zip')
        before = {p.name: (p.read_bytes(), inv.signature(p.stat())) for p in self.root.iterdir()}
        def probe(stream):
            stream.seek(0)
            if stream.read() == b'bad':
                raise subprocess.TimeoutExpired('ffprobe', 60)
            return inv.metadata(MEDIA)
        with patch.object(inv, 'probe', side_effect=probe), patch.object(inv, 'mount_identity', return_value={'uuid': 'test'}):
            document = inv.run(self.root, self.base/'run')
        self.assertFalse(document['complete'])
        self.assertEqual(document['summary']['duplicate_files'], 1)
        self.assertEqual(document['summary']['unique_sources'], 1)
        self.assertEqual(len(document['sources'][0]['aliases']), 2)
        self.assertEqual(document['summary']['states']['error'], 1)
        self.assertEqual(before, {p.name: (p.read_bytes(), inv.signature(p.stat())) for p in self.root.iterdir()})
        self.assertTrue((self.base/'run/inventory.json').exists())

    def test_wrong_mount_fails_before_output(self):
        result = subprocess.CompletedProcess([], 0, json.dumps({'filesystems': [{'uuid': None}]}), '')
        with patch.object(subprocess, 'run', return_value=result):
            with self.assertRaisesRegex(ValueError, 'expected mounted'):
                inv.run(self.root, self.base/'run', 'expected')
        self.assertFalse((self.base/'run').exists())

    def test_scan_errors_are_recorded(self):
        with patch.object(os, 'scandir', side_effect=PermissionError('denied')):
            rows, errors = inv.snapshot(self.root)
        self.assertEqual(rows, [])
        self.assertEqual(errors[0]['error'], 'PermissionError')

    def test_one_stat_failure_does_not_hide_other_files(self):
        self.source('bad.mp4')
        self.source('good.mp4')
        original = os.stat
        def failing(path, *args, **kwargs):
            if path == 'bad.mp4':
                raise PermissionError('fixture denial')
            return original(path, *args, **kwargs)
        with patch.object(os, 'stat', side_effect=failing):
            rows, errors = inv.snapshot(self.root)
        self.assertEqual([r['state'] for r in rows], ['error', 'pending'])
        self.assertFalse(errors)

    def test_directory_replaced_with_symlink_is_not_traversed(self):
        folder = self.root/'folder'
        folder.mkdir()
        outside = self.base/'outside'
        outside.mkdir()
        (outside/'private.mp4').write_bytes(b'outside')
        original = os.open
        def replaced(path, *args, **kwargs):
            if path == 'folder':
                folder.rmdir()
                folder.symlink_to(outside, target_is_directory=True)
            return original(path, *args, **kwargs)
        with patch.object(os, 'open', side_effect=replaced):
            rows, _ = inv.snapshot(self.root)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['state'], 'error')

    def test_mount_change_keeps_progress_without_completed_manifest(self):
        self.source()
        with patch.object(inv, 'probe', return_value=inv.metadata(MEDIA)), \
                patch.object(inv, 'mount_identity', side_effect=[{'uuid': 'a'}, {'uuid': 'b'}]):
            with self.assertRaisesRegex(ValueError, 'Mount changed'):
                inv.run(self.root, self.base/'interrupted')
        self.assertTrue((self.base/'interrupted/progress.jsonl').exists())
        self.assertFalse((self.base/'interrupted/inventory.json').exists())

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'ffmpeg required')
    def test_real_media_end_to_end(self):
        path = self.root/'actual clip.mp4'
        subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=64x48:r=24',
                        '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '0.5', '-c:v', 'mpeg4',
                        '-c:a', 'aac', str(path)], check=True)
        before = inv.sha256(path), inv.signature(path.stat())
        document = inv.run(self.root, self.base/'real-run')
        self.assertTrue(document['complete'])
        self.assertEqual(document['summary']['unique_videos'], 1)
        self.assertEqual(len(document['sources'][0]['media']['streams']), 2)
        self.assertEqual(before, (inv.sha256(path), inv.signature(path.stat())))


if __name__ == '__main__':
    unittest.main()
