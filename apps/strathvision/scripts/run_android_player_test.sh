#!/usr/bin/env bash
# Runs an integration test (default real_player_test.dart) on a connected Android device or
# emulator, pushing the test clips (FILES, from integration_test/assets) once the app
# has created its files dir.
set -euo pipefail
cd "$(dirname "$0")/.."
ADB="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb"
DEVICE="${1:-}"
[[ -n "$DEVICE" ]] || DEVICE=$($ADB devices | awk 'NR>1 && $2=="device"{print $1; exit}')
TEST="${2:-integration_test/real_player_test.dart}"
[[ -n "$DEVICE" ]] || { echo "no Android device connected" >&2; exit 1; }
LOG=$(mktemp)
flutter test "$TEST" -d "$DEVICE" \
  --dart-define=CLIP_DIR=android 2>&1 | tee "$LOG" &
PID=$!
until grep -q 'CLIPS_DIR ' "$LOG"; do
  kill -0 $PID 2>/dev/null || { wait $PID; exit $?; }
  sleep 1
done
DIR=$(grep -o 'CLIPS_DIR [^ ]*' "$LOG" | head -1 | cut -d' ' -f2)
FILES="${FILES:-clip30.mp4 clip25.mp4 coach_package.zip}"
for f in $FILES; do
  "$ADB" -s "$DEVICE" push "integration_test/assets/$f" "$DIR/" >/dev/null
done
wait $PID
