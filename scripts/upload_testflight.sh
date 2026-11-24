#!/usr/bin/env bash
# Run only on the GitHub-hosted Mac after all existing builds jobs pass.
set -euo pipefail
umask 077
export APP_STORE_CONNECT_DISABLE_JWT_CACHE=true

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/apps/strathvision"
python "$root/scripts/apple_beta.py" preflight
[[ "$(uname -s)" == Darwin ]] || { echo 'Signing requires a macOS runner.' >&2; exit 1; }
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_REF:-}" == refs/heads/implementation ]] || {
  echo 'Use the manual builds workflow on implementation.' >&2; exit 1;
}

signing_dir="$(mktemp -d "$RUNNER_TEMP/strathvision-signing.XXXXXX")"
signing_keychain="$signing_dir/beta.keychain-db"
installed_profiles=()
cleanup() {
  keychain use-login >/dev/null 2>&1 || true
  if [[ -f "$signing_keychain" ]]; then
    security delete-keychain "$signing_keychain" >/dev/null 2>&1 || true
  fi
  # macOS Bash 3.2 treats an empty array as unset under nounset.
  for profile in "${installed_profiles[@]:-}"; do
    if [[ -n "$profile" ]]; then
      rm -f -- "$profile"
    fi
  done
  rm -rf -- "$signing_dir"
}
trap cleanup EXIT

# Read-only account checks precede certificate/profile creation.
app-store-connect apps get "$APP_STORE_ID" --json > "$signing_dir/app.json"
python "$root/scripts/apple_beta.py" check-app "$signing_dir/app.json"
app-store-connect get-latest-testflight-build-number "$APP_STORE_ID" \
  --platform IOS --all-versions > "$signing_dir/latest-build.txt"
build_number="$(python "$root/scripts/apple_beta.py" next-build "$signing_dir/latest-build.txt")"

# One stable RSA key is reused across runs. Never revoke existing certificates.
export STRATHVISION_KEYCHAIN_PASSWORD
STRATHVISION_KEYCHAIN_PASSWORD="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
keychain initialize --path "$signing_keychain" --password @env:STRATHVISION_KEYCHAIN_PASSWORD
app-store-connect fetch-signing-files "$IOS_BUNDLE_ID" \
  --platform IOS --type IOS_APP_STORE --strict-match-identifier \
  --certificate-key @env:CERTIFICATE_PRIVATE_KEY \
  --certificates-dir "$signing_dir/certificates" \
  --profiles-dir "$signing_dir/profiles" --create
profile_library="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profile_library"
for profile in "$signing_dir/profiles/"*.mobileprovision; do
  installed="$profile_library/strathvision-$(basename "$profile")"
  [[ ! -e "$installed" ]] || { echo 'Refusing to overwrite an existing signing profile.' >&2; exit 1; }
  cp "$profile" "$installed"
  installed_profiles+=("$installed")
done
keychain add-certificates --path "$signing_keychain" \
  --certificate "$signing_dir/certificates/*.p12"
xcode-project use-profiles \
  --project "$app/ios/Runner.xcodeproj" \
  --profile "$signing_dir/profiles/*.mobileprovision" \
  --export-options-plist "$signing_dir/export-options.plist" \
  --custom-export-options '{"manageAppVersionAndBuildNumber":false}'
# Codemagic 0.71.0 emits the legacy name; Xcode uses app-store-connect.
python "$root/scripts/apple_beta.py" normalize-export "$signing_dir/export-options.plist"
python "$root/scripts/apple_beta.py" check-export "$signing_dir/export-options.plist"

cd "$app"
flutter pub get
flutter build ipa --release --build-number "$build_number" \
  --export-options-plist "$signing_dir/export-options.plist"
python "$root/scripts/verify_ios_ffi.py" \
  "$app/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app"
ipa="$(python "$root/scripts/apple_beta.py" manifest "$app/build/ios/ipa" "$build_number")"
python "$root/scripts/verify_ios_ffi.py" "$ipa" \
  > "$app/build/ios/ipa/ffi-exports.json"

# --testflight submits for external beta review; intentionally omit it here.
# Adding test notes waits for Apple to find the uploaded build without invitations.
app-store-connect publish --path "$ipa" --enable-package-validation \
  --max-find-build-wait 15 --locale en-US \
  --whats-new 'Test video import, two-clip sync, slow motion, frame stepping, notes and reopening saved reviews. Automated analysis is experimental; coaching accuracy and physical-device acceptance are not yet established.'
python "$root/scripts/apple_beta.py" uploaded "$app/build/ios/ipa/testflight-manifest.json"
printf 'Uploaded iOS beta build %s. Apple processing, device acceptance and external review are separate.\n' "$build_number" >> "$GITHUB_STEP_SUMMARY"
