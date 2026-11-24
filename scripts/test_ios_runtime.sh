#!/usr/bin/env bash
# Uses an already-installed simulator on the isolated GitHub macOS runner.
set -euo pipefail
[[ "$(uname -s)" == Darwin && "${GITHUB_ACTIONS:-}" == true ]] || {
  echo 'Run this simulator check on the GitHub macOS runner.' >&2; exit 1;
}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
devices="$(mktemp "$RUNNER_TEMP/strathvision-simulators.XXXXXX")"
device=''
cleanup() {
  if [[ -n "$device" ]]; then
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
  fi
  rm -f -- "$devices"
}
trap cleanup EXIT
xcrun simctl list devices available --json > "$devices"
device="$(python "$root/scripts/select_ios_simulator.py" "$devices")"
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
cd "$root/apps/strathvision"
flutter test integration_test/native_runtime_test.dart -d "$device" --reporter expanded
