"""Release identity and signing failures must stop before an Apple upload."""
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'apple_beta.py'
spec = importlib.util.spec_from_file_location('apple_beta', SCRIPT)
beta = importlib.util.module_from_spec(spec)
spec.loader.exec_module(beta)

ENV = {
    'IOS_BUNDLE_ID': 'com.strathvision.strathvision',
    'IOS_TEAM_ID': 'ABCDEFGHIJ', 'APP_STORE_ID': '1234567890',
    'APP_STORE_CONNECT_ISSUER_ID': '00000000-0000-4000-8000-000000000001',
    'APP_STORE_CONNECT_KEY_IDENTIFIER': '123456789A',
    'APP_STORE_CONNECT_PRIVATE_KEY': 'private-api-fixture-never-print',
    'CERTIFICATE_PRIVATE_KEY': 'private-certificate-fixture-never-print',
}


class AppleBetaChecks(unittest.TestCase):
    def test_missing_account_inputs_are_named_without_revealing_keys(self):
        env = {**ENV, 'IOS_TEAM_ID': ''}
        result = subprocess.run([sys.executable, str(SCRIPT), 'preflight'],
                                env={**os.environ, **env}, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('IOS_TEAM_ID', result.stderr)
        self.assertNotIn(ENV['APP_STORE_CONNECT_PRIVATE_KEY'], result.stderr + result.stdout)
        self.assertNotIn(ENV['CERTIFICATE_PRIVATE_KEY'], result.stderr + result.stdout)

    def test_invalid_identifiers_fail_without_echoing_the_value(self):
        beta.require_environment(ENV)
        for name in ('IOS_TEAM_ID', 'APP_STORE_ID', 'APP_STORE_CONNECT_ISSUER_ID',
                     'IOS_BUNDLE_ID', 'APP_STORE_CONNECT_KEY_IDENTIFIER'):
            with self.subTest(name=name), self.assertRaises(beta.BetaError) as caught:
                beta.require_environment({**ENV, name: 'sensitive-invalid-value'})
            self.assertNotIn('sensitive-invalid-value', str(caught.exception))

    def test_app_record_must_match_both_id_and_bundle(self):
        record = {'id': ENV['APP_STORE_ID'], 'attributes': {'bundleId': ENV['IOS_BUNDLE_ID']}}
        beta.check_app(record, ENV)
        for wrong in ({**record, 'id': '987654321'},
                      {**record, 'attributes': {'bundleId': 'another.app'}}):
            with self.assertRaises(beta.BetaError):
                beta.check_app(wrong, ENV)

    def test_retry_build_numbers_do_not_depend_on_apple_indexing_speed(self):
        first = beta.next_build_number('', '78', '1')
        retry = beta.next_build_number('', '78', '2')
        self.assertGreater(beta.build_parts(retry), beta.build_parts(first))
        self.assertGreater(beta.build_parts(beta.next_build_number(retry, '79', '1')),
                           beta.build_parts(retry))

    def test_build_number_advances_past_manual_uploads_and_rolls_components(self):
        self.assertEqual(beta.next_build_number('98.99.99\n', '1', '1'), '99.0.0')
        self.assertEqual(beta.next_build_number('100', '1', '1'), '100.0.1')
        for latest in ('an API error', '0', '1.100', '9999.99.99'):
            with self.subTest(latest=latest), self.assertRaises(beta.BetaError):
                beta.next_build_number(latest, '1', '1')

    def test_invalid_workflow_run_metadata_is_rejected(self):
        for run, attempt in [('0', '1'), ('1', '100'), ('1; command', '1'), ('99999999', '1')]:
            with self.subTest(run=run, attempt=attempt), self.assertRaises(beta.BetaError):
                beta.next_build_number('', run, attempt)

    def test_export_rejects_foreign_team_wrong_method_and_version_rewriting(self):
        good = {'teamID': ENV['IOS_TEAM_ID'], 'method': 'app-store-connect',
                'manageAppVersionAndBuildNumber': False,
                'provisioningProfiles': {ENV['IOS_BUNDLE_ID']: 'fixture-profile'}}
        beta.check_export(good, ENV)
        for change in ({'teamID': 'OTHERTEAM1'}, {'method': 'ad-hoc'},
                       {'manageAppVersionAndBuildNumber': True}, {'provisioningProfiles': {}}):
            with self.subTest(change=change), self.assertRaises(beta.BetaError):
                beta.check_export({**good, **change}, ENV)

    def profile(self):
        return {'TeamIdentifier': [ENV['IOS_TEAM_ID']],
                'ApplicationIdentifierPrefix': ['OLDPREFIX1'],
                'ExpirationDate': datetime.now(timezone.utc) + timedelta(days=30),
                'Entitlements': {'application-identifier': 'OLDPREFIX1.' + ENV['IOS_BUNDLE_ID'],
                                 'get-task-allow': False}}

    def test_profile_accepts_legacy_prefix_but_rejects_non_store_signing(self):
        good = self.profile()
        beta.check_profile(good, ENV)
        for change in ({'TeamIdentifier': ['OTHERTEAM1']},
                       {'ExpirationDate': datetime.now(timezone.utc) - timedelta(days=1)},
                       {'ProvisionedDevices': ['fixture-phone']}, {'ProvisionsAllDevices': True},
                       {'Entitlements': {**good['Entitlements'], 'get-task-allow': True}},
                       {'Entitlements': {**good['Entitlements'], 'application-identifier': 'OLDPREFIX1.*'}}):
            with self.subTest(change=change), self.assertRaises(beta.BetaError):
                beta.check_profile({**good, **change}, ENV)

    def make_ipa(self, path, change=None, profile=True, extra_app=False):
        info = {'CFBundleIdentifier': ENV['IOS_BUNDLE_ID'], 'CFBundleVersion': '1.78.1',
                'CFBundleShortVersionString': '1.0.0', 'DTSDKName': 'iphoneos26.2'}
        info.update(change or {})
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps(info))
            if profile:
                archive.writestr('Payload/Runner.app/embedded.mobileprovision', b'fixture-cms')
            if extra_app:
                archive.writestr('Payload/Other.app/Info.plist', plistlib.dumps(info))

    def test_ipa_identity_sdk_and_profile_are_checked_before_upload(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'beta.ipa'
            self.make_ipa(path)
            info, cms = beta.inspect_ipa(path, ENV, '1.78.1')
            self.assertEqual(info['CFBundleShortVersionString'], '1.0.0')
            self.assertEqual(cms, b'fixture-cms')
            cases = [({'CFBundleIdentifier': 'foreign.app'}, True, False),
                     ({'CFBundleVersion': '1.78.2'}, True, False),
                     ({'DTSDKName': 'iphoneos18.5'}, True, False),
                     ({}, False, False), ({}, True, True)]
            for change, profile, extra in cases:
                self.make_ipa(path, change, profile, extra)
                with self.subTest(change=change, profile=profile, extra=extra), self.assertRaises(beta.BetaError):
                    beta.inspect_ipa(path, ENV, '1.78.1')

    def test_uploaded_record_cannot_be_promoted_twice(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'testflight-manifest.json'
            path.write_text(json.dumps({'status': 'verified-upload-candidate', 'sha256': 'fixture'}))
            result = subprocess.run([sys.executable, str(SCRIPT), 'uploaded', str(path)], capture_output=True)
            self.assertEqual(result.returncode, 0)
            record = json.loads(path.read_text())
            self.assertEqual(record['status'], 'uploaded-test-notes-added')
            self.assertEqual(record['sha256'], 'fixture')
            result = subprocess.run([sys.executable, str(SCRIPT), 'uploaded', str(path)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
