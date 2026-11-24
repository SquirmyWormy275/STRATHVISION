#!/usr/bin/env bash
# Uses an already-installed simulator on the isolated GitHub macOS runner.
set -euo pipefail
[[ "$(uname -s)" == Darwin && "${GITHUB_ACTIONS:-}" == true ]] || {
  echo 'Run this simulator check on the GitHub macOS runner.' >&2; exit 1;
}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
devices="$(mktemp "$RUNNER_TEMP/strathvision-simulators.XXXXXX")"
pubspec="$root/apps/strathvision/pubspec.yaml"
pubspec_backup="$(mktemp "$RUNNER_TEMP/strathvision-pubspec.XXXXXX")"
cp -- "$pubspec" "$pubspec_backup"
device=''
cleanup() {
  if [[ -n "$device" ]]; then
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
  fi
  cp -- "$pubspec_backup" "$pubspec"
  rm -f -- "$devices" "$pubspec_backup"
}
trap cleanup EXIT
# Keep licensed fixture data out of production assets. The unsigned release
# artifact is already built; this temporary declaration only enters the test
# app, where rootBundle copies the file into its own sandbox.
python - "$pubspec" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
anchor = "  assets:\n"
if text.count(anchor) != 1:
    raise SystemExit("Expected exactly one Flutter assets section")
path.write_text(text.replace(anchor, anchor + "    - integration_test/assets/cleave.webm\n", 1))
PY
xcrun simctl list devices available --json > "$devices"
device="$(python "$root/scripts/select_ios_simulator.py" "$devices")"
printf '[%s] Booting selected iPhone simulator %s\n' "$(date -u +%FT%TZ)" "$device"
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
cd "$root/apps/strathvision"
printf '[%s] Building and running native model and video analysis tests\n' "$(date -u +%FT%TZ)"
# The preceding release build already resolved the pinned dependencies. Verbose
# output preserves the active native-build command if the runner times out.
flutter test integration_test/native_runtime_test.dart -d "$device" --no-pub --verbose --reporter expanded
printf '[%s] Native model and video analysis tests passed\n' "$(date -u +%FT%TZ)"
