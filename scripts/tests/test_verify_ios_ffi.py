"""Runtime lookup must survive archive stripping, not merely linking."""
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'verify_ios_ffi.py'
spec = importlib.util.spec_from_file_location('verify_ios_ffi', SCRIPT)
ffi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ffi)
SYMBOL = '_OrtGetApiBase'


def uleb(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def trie(name=SYMBOL, flags=0, address=0x1234):
    edge = name.encode() + b'\0'
    child = 2 + len(edge) + 1
    assert child < 128
    payload = uleb(flags) + uleb(address)
    return b'\0\1' + edge + uleb(child) + uleb(len(payload)) + payload + b'\0'


def macho(exports=None, *, legacy=False, endian='<', cpu=0x100000c):
    exports = trie() if exports is None else exports
    command_size = 48 if legacy else 16
    header = struct.pack(endian + '8I', 0xfeedfacf, cpu, 0, 2, 1, command_size, 0, 0)
    if legacy:
        command = struct.pack(endian + '12I', 0x80000022, 48,
                              *([0] * 8), 32 + command_size, len(exports))
    else:
        command = struct.pack(endian + '4I', 0x80000033, 16,
                              32 + command_size, len(exports))
    return header + command + exports


def universal(slices, wide=False):
    header = struct.pack('>II', 0xcafebabf if wide else 0xcafebabe, len(slices))
    offset = len(header) + len(slices) * (32 if wide else 20)
    table = b''
    for cpu, data in slices:
        table += struct.pack('>IIQQII' if wide else '>IIIII',
                             cpu, 0, offset, len(data), 0, *([0] if wide else []))
        offset += len(data)
    return header + table + b''.join(data for _, data in slices)


class DynamicExportChecks(unittest.TestCase):
    def test_retained_callable_export_passes_both_load_command_formats(self):
        for legacy in (False, True):
            for endian in ('<', '>'):
                with self.subTest(legacy=legacy, endian=endian):
                    result = ffi.verify_macho(macho(legacy=legacy, endian=endian))
                    self.assertEqual(result[0]['required_exports'], {SYMBOL: '0x1234'})

    def test_archive_stripped_export_fails_even_with_unreachable_symbol_bytes(self):
        # Like the broken IPA: only __mh_execute_header is reachable; obsolete
        # trie nodes or static strings still mentioning ONNX prove nothing.
        stripped = trie('__mh_execute_header', address=0x100000000) + trie()
        self.assertIn(SYMBOL.encode(), stripped)
        with self.assertRaisesRegex(ValueError, 'lacks callable dynamic exports'):
            ffi.verify_macho(macho(stripped))

    def test_zero_address_thread_local_and_reexport_are_not_callable_entry(self):
        for flags, address in ((0, 0), (1, 0x1234), (2, 0x1234), (8, 1)):
            with self.subTest(flags=flags, address=address), self.assertRaises(ValueError):
                ffi.verify_macho(macho(trie(flags=flags, address=address)))

    def test_every_universal_slice_must_have_export(self):
        for wide in (False, True):
            slices = [(0x100000c, macho()), (0x1000007, macho(cpu=0x1000007))]
            self.assertEqual(len(ffi.verify_macho(universal(slices, wide))), 2)
            slices[1] = (0x1000007, macho(trie('_other'), cpu=0x1000007))
            with self.assertRaisesRegex(ValueError, 'x86_64 executable lacks'):
                ffi.verify_macho(universal(slices, wide))

    def test_truncated_headers_commands_and_tables_fail_closed(self):
        good = macho()
        for data in (b'', good[:20], good[:40], good[:-1], b'not executable'):
            with self.subTest(length=len(data)), self.assertRaises(ValueError):
                ffi.verify_macho(data)
        bad = bytearray(good)
        struct.pack_into('<I', bad, 40, 0)  # Export offset points into header.
        with self.assertRaisesRegex(ValueError, 'Out-of-range'):
            ffi.verify_macho(bytes(bad))

    def test_cycles_truncated_integers_and_missing_edges_fail_closed(self):
        for bad in (b'\0\1a\0\0', b'\x80', b'\0\1unterminated', b'\0\1\0\5'):
            with self.subTest(trie=bad), self.assertRaises(ValueError):
                ffi.exported_symbols(bad)

    def test_universal_table_cannot_lie_about_slice_architecture(self):
        with self.assertRaisesRegex(ValueError, 'architecture mismatch'):
            ffi.verify_macho(universal([(0x1000007, macho())]))

    def test_ipa_and_app_paths_use_declared_executable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app = root / 'Demo.app'
            app.mkdir()
            info = plistlib.dumps({'CFBundleExecutable': 'Engine'})
            (app / 'Info.plist').write_bytes(info)
            (app / 'Engine').write_bytes(macho())
            ipa = root / 'Demo.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr('Payload/Demo.app/Info.plist', info)
                archive.writestr('Payload/Demo.app/Engine', macho())
            for path in (app, ipa, app / 'Engine'):
                with self.subTest(path=path):
                    self.assertIn(SYMBOL, ffi.verify_path(path)['slices'][0]['required_exports'])

    def test_ipa_rejects_ambiguous_apps_and_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.ipa'
            for names, executable in ((['A', 'B'], 'Runner'), (['A'], '../Runner')):
                with zipfile.ZipFile(path, 'w') as archive:
                    for name in names:
                        archive.writestr(f'Payload/{name}.app/Info.plist',
                                         plistlib.dumps({'CFBundleExecutable': executable}))
                with self.assertRaises(ValueError):
                    ffi.verify_path(path)

    def test_cli_exits_nonzero_for_missing_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'Runner'
            for data, expected in ((macho(trie('_other')), 1), (macho(), 0)):
                path.write_bytes(data)
                result = subprocess.run([sys.executable, str(SCRIPT), str(path)],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, expected, result.stderr)
                if not expected:
                    self.assertEqual(json.loads(result.stdout)['slices'][0]['arch'], 'arm64')
                else:
                    self.assertIn(SYMBOL, result.stderr)


if __name__ == '__main__':
    unittest.main()
