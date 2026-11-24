"""Runtime naming changes must not prevent the actual iOS simulator test."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'select_ios_simulator.py'
spec = importlib.util.spec_from_file_location('select_ios_simulator', SCRIPT)
simulator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(simulator)
PREFIX = 'com.apple.CoreSimulator.SimRuntime.'


def phone(udid, **changes):
    return {'name': 'iPhone 18 Pro', 'udid': udid,
            'isAvailable': True, 'state': 'Shutdown', **changes}


class SimulatorSelectionTests(unittest.TestCase):
    def test_standard_runtimes_use_numeric_version_order(self):
        self.assertEqual(simulator.select_iphone({
            PREFIX + 'iOS-27-2': [phone('older')],
            PREFIX + 'iOS-26-9': [phone('oldest')],
            PREFIX + 'iOS-27-10': [phone('newest')],
        }), 'newest')

    def test_device_specific_suffix_is_not_part_of_version(self):
        for suffix in ('iPhone19-1', 'iPhone19,1', 'iPhone19'):
            with self.subTest(suffix=suffix):
                self.assertEqual(simulator.select_iphone({
                    PREFIX + 'iOS-27-1-' + suffix: [phone('older')],
                    PREFIX + 'iOS-27-2-' + suffix: [phone('newest')],
                    PREFIX + 'iOS-27-0': [phone('oldest')],
                }), 'newest')

    def test_unavailable_booted_and_non_iphone_devices_are_skipped(self):
        self.assertEqual(simulator.select_iphone({
            PREFIX + 'iOS-27-3': [phone('unavailable', isAvailable=False),
                                  phone('booted', state='Booted'),
                                  phone('tablet', name='iPad Pro'),
                                  phone('', name='iPhone without ID')],
            PREFIX + 'iOS-27-2': [phone('usable')],
        }), 'usable')

    def test_non_ios_and_malformed_runtime_names_are_skipped(self):
        runtimes = {PREFIX + 'iOS-27-2': [phone('usable')]}
        for runtime in ('tvOS-99-1', 'watchOS-99-1', 'iOS-', 'iOS-abc',
                        'iOS-99--1', 'iOS-99-1bad', 'iOS-99-1-'):
            runtimes[PREFIX + runtime] = [phone('invalid')]
        self.assertEqual(simulator.select_iphone(runtimes), 'usable')

    def test_no_valid_candidates_fails_explicitly(self):
        for runtimes in ({}, {PREFIX + 'iOS-27-2': []},
                         {PREFIX + 'iOS-27-2': [phone('busy', state='Booted')]}):
            with self.subTest(runtimes=runtimes), self.assertRaisesRegex(
                    ValueError, 'No installed, available shutdown iPhone'):
                simulator.select_iphone(runtimes)

    def test_cli_outputs_only_selected_id_and_fails_without_candidates(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'devices.json'
            for devices, expected in (
                    ({PREFIX + 'iOS-27-2-iPhone19-1': [phone('selected-id')]}, 0),
                    ({}, 1)):
                path.write_text(json.dumps({'devices': devices}))
                result = subprocess.run([sys.executable, str(SCRIPT), str(path)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertEqual(result.stdout, 'selected-id\n' if expected == 0 else '')
                if expected:
                    self.assertIn('No installed, available shutdown iPhone', result.stderr)


if __name__ == '__main__':
    unittest.main()
