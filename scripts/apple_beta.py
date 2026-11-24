#!/usr/bin/env python3
"""Validate Apple beta inputs and artifact identity without printing private keys."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import uuid
import zipfile


class BetaError(ValueError):
    pass


def require_environment(env):
    required = (
        'IOS_BUNDLE_ID', 'IOS_TEAM_ID', 'APP_STORE_ID',
        'APP_STORE_CONNECT_ISSUER_ID', 'APP_STORE_CONNECT_KEY_IDENTIFIER',
        'APP_STORE_CONNECT_PRIVATE_KEY', 'CERTIFICATE_PRIVATE_KEY',
    )
    missing = [name for name in required if not env.get(name, '').strip()]
    if missing:
        raise BetaError('Configure the testflight GitHub environment: ' + ', '.join(missing))
    for name in ('IOS_TEAM_ID', 'APP_STORE_CONNECT_KEY_IDENTIFIER'):
        if not re.fullmatch(r'[A-Z0-9]{10}', env[name]):
            raise BetaError(f'{name} must be a ten-character Apple identifier.')
    if not re.fullmatch(r'[1-9][0-9]*', env['APP_STORE_ID']):
        raise BetaError('APP_STORE_ID must be the numeric Apple ID from the app record.')
    if env['IOS_BUNDLE_ID'] != 'com.strathvision.strathvision':
        raise BetaError('The beta bundle ID must match the committed STRATHVISION app.')
    try:
        uuid.UUID(env['APP_STORE_CONNECT_ISSUER_ID'])
    except ValueError:
        raise BetaError('APP_STORE_CONNECT_ISSUER_ID must be an issuer UUID.') from None


def validate_private_keys(env):
    # The dependency is installed only in the Mac signing job. Unit tests need no API keys.
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec, rsa
    for name in ('APP_STORE_CONNECT_PRIVATE_KEY', 'CERTIFICATE_PRIVATE_KEY'):
        try:
            key = serialization.load_pem_private_key(env[name].encode(), password=None)
        except (ValueError, TypeError):
            raise BetaError(f'{name} must contain an unencrypted PEM private key.') from None
        if name == 'APP_STORE_CONNECT_PRIVATE_KEY':
            if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
                raise BetaError('The App Store Connect API key must be an Apple P-256 .p8 key.')
        elif not isinstance(key, rsa.RSAPrivateKey) or key.key_size != 2048:
            raise BetaError('CERTIFICATE_PRIVATE_KEY must be a persistent 2048-bit RSA key.')


def check_app(data, env):
    # Codemagic's --json prints an Apple Resource, not a JSON:API envelope.
    if str(data.get('id')) != env['APP_STORE_ID']:
        raise BetaError('Apple returned a different app record.')
    if data.get('attributes', {}).get('bundleId') != env['IOS_BUNDLE_ID']:
        raise BetaError('The App Store Connect app uses a different bundle ID.')


def build_parts(value):
    if not re.fullmatch(r'[1-9][0-9]{0,3}(?:\.[0-9]{1,2}){0,2}', value):
        raise BetaError('Apple build numbers must have one to three numeric components within 9999.99.99.')
    parts = [int(part) for part in value.split('.')]
    return tuple(parts + [0] * (3 - len(parts)))


def next_build_number(latest, run_number, run_attempt):
    if not re.fullmatch(r'[1-9][0-9]*', run_number) or not re.fullmatch(r'[1-9][0-9]?', run_attempt):
        raise BetaError('A positive GitHub run number and run attempt below 100 are required.')
    # Encode run/attempt as an Apple-compatible floor. Retries remain distinct even
    # while a previous upload has not appeared in Apple's listing yet.
    ordinal = int(run_number) * 100 + int(run_attempt)
    floor = (1 + ordinal // 10000, (ordinal // 100) % 100, ordinal % 100)
    latest = latest.strip()
    if latest:
        major, minor, patch = build_parts(latest)
        patch += 1
        if patch == 100:
            minor, patch = minor + 1, 0
        if minor == 100:
            major, minor = major + 1, 0
        floor = max(floor, (major, minor, patch))
    result = '.'.join(map(str, floor))
    build_parts(result)
    return result


def check_export(data, env):
    if data.get('teamID') != env['IOS_TEAM_ID']:
        raise BetaError('The fetched signing profile belongs to a different Apple team.')
    if data.get('method') != 'app-store-connect':
        raise BetaError('TestFlight requires an App Store Connect export profile.')
    if data.get('manageAppVersionAndBuildNumber') is not False:
        raise BetaError('The exporter must preserve the recorded build number.')
    if env['IOS_BUNDLE_ID'] not in data.get('provisioningProfiles', {}):
        raise BetaError('The export profile does not cover the STRATHVISION bundle ID.')


def normalize_export(data, env):
    # Codemagic 0.71.0 accepts only the legacy App Store export-method name.
    if data.get('method') not in ('app-store', 'app-store-connect'):
        raise BetaError('Only an App Store export profile can be normalized for TestFlight.')
    normalized = {**data, 'method': 'app-store-connect'}
    check_export(normalized, env)
    return normalized


def inspect_ipa(ipa, env, build_number):
    with zipfile.ZipFile(ipa) as archive:
        entries = [name for name in archive.namelist()
                   if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', name)]
        if len(entries) != 1:
            raise BetaError('Expected exactly one top-level iOS app in the IPA.')
        info = plistlib.loads(archive.read(entries[0]))
        expected = {'CFBundleIdentifier': env['IOS_BUNDLE_ID'], 'CFBundleVersion': build_number}
        if any(info.get(key) != value for key, value in expected.items()):
            raise BetaError('The IPA bundle ID or build number differs from the upload target.')
        version = info.get('CFBundleShortVersionString', '')
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', version):
            raise BetaError('The IPA is missing a valid marketing version.')
        sdk = re.fullmatch(r'iphoneos([0-9]+)(?:\.[0-9]+)*', info.get('DTSDKName', ''))
        if not sdk or int(sdk[1]) < 26:
            raise BetaError('App Store Connect requires the iOS 26 SDK or newer.')
        profile_name = entries[0].removesuffix('Info.plist') + 'embedded.mobileprovision'
        if profile_name not in archive.namelist():
            raise BetaError('The IPA has no embedded provisioning profile.')
        return info, archive.read(profile_name)


def check_profile(profile, env, now=None):
    now = now or datetime.now(timezone.utc)
    expires = profile.get('ExpirationDate')
    if not isinstance(expires, datetime) or expires.replace(tzinfo=timezone.utc) <= now:
        raise BetaError('The provisioning profile has expired or has no expiration date.')
    entitlements = profile.get('Entitlements', {})
    if profile.get('TeamIdentifier') != [env['IOS_TEAM_ID']]:
        raise BetaError('The IPA provisioning profile belongs to a different team.')
    # Legacy App ID prefixes can differ from the Team ID; bind to the profile's own prefix.
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    valid_ids = {f'{prefix}.{env["IOS_BUNDLE_ID"]}' for prefix in prefixes}
    if entitlements.get('application-identifier') not in valid_ids:
        raise BetaError('The IPA provisioning profile does not cover this app.')
    if entitlements.get('get-task-allow') is not False:
        raise BetaError('A development provisioning profile cannot be uploaded to TestFlight.')
    if 'ProvisionedDevices' in profile or profile.get('ProvisionsAllDevices'):
        raise BetaError('An ad hoc or enterprise profile cannot be uploaded to TestFlight.')


def write_manifest(directory, env, build_number):
    ipas = list(directory.glob('*.ipa'))
    if len(ipas) != 1:
        raise BetaError('Expected exactly one newly built IPA.')
    ipa = ipas[0].resolve()
    info, cms = inspect_ipa(ipa, env, build_number)
    decoded = subprocess.run(['security', 'cms', '-D'], input=cms, capture_output=True, check=False)
    if decoded.returncode:
        raise BetaError('Could not decode the IPA provisioning profile.')
    check_profile(plistlib.loads(decoded.stdout), env)
    with ipa.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    manifest = {
        'format': 'strathvision-testflight/1', 'status': 'verified-upload-candidate',
        'source_commit': env['GITHUB_SHA'],
        'run_url': f'https://github.com/{env["GITHUB_REPOSITORY"]}/actions/runs/{env["GITHUB_RUN_ID"]}',
        'app_store_id': env['APP_STORE_ID'], 'bundle_id': env['IOS_BUNDLE_ID'],
        'version': info['CFBundleShortVersionString'], 'build_number': build_number,
        'sdk': info['DTSDKName'], 'ipa': ipa.name, 'sha256': digest,
        'physical_device_acceptance': 'not verified by this build',
    }
    (directory / 'testflight-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return ipa


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['preflight', 'check-app', 'normalize-export', 'check-export', 'next-build', 'manifest', 'uploaded'])
    parser.add_argument('path', nargs='?', type=Path)
    parser.add_argument('build_number', nargs='?')
    args = parser.parse_args()
    if args.command != 'preflight' and args.path is None:
        parser.error('This command requires a path.')
    env = os.environ
    if args.command == 'preflight':
        require_environment(env)
        validate_private_keys(env)
        print('Apple signing inputs are present and structurally valid; account access is checked next.')
    elif args.command == 'check-app':
        check_app(json.loads(args.path.read_text()), env)
    elif args.command == 'normalize-export':
        normalized = normalize_export(plistlib.loads(args.path.read_bytes()), env)
        args.path.write_bytes(plistlib.dumps(normalized))
    elif args.command == 'check-export':
        check_export(plistlib.loads(args.path.read_bytes()), env)
    elif args.command == 'next-build':
        print(next_build_number(args.path.read_text(), env['GITHUB_RUN_NUMBER'], env['GITHUB_RUN_ATTEMPT']))
    elif args.command == 'manifest':
        if not args.build_number:
            parser.error('manifest requires a build number.')
        print(write_manifest(args.path, env, args.build_number))
    else:
        data = json.loads(args.path.read_text())
        if data.get('status') != 'verified-upload-candidate':
            raise BetaError('Only a verified candidate can be recorded as uploaded.')
        data['status'] = 'uploaded-test-notes-added'
        data['uploaded_at'] = datetime.now(timezone.utc).isoformat()
        args.path.write_text(json.dumps(data, indent=2) + '\n')


if __name__ == '__main__':
    try:
        main()
    except (BetaError, OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        # Errors must describe the operation, never echo supplied private-key data.
        print(f'Apple beta setup: {error}', file=sys.stderr)
        sys.exit(1)
