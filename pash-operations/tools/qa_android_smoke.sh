#!/usr/bin/env bash
# Run the entire smoke inside ONE shell. The emulator runner executes each
# inline script line separately, so unexported shell variables otherwise vanish.
set -euo pipefail
ROOT="pash-operations/app/mobile"
APK="$ROOT/android/app/build/outputs/apk/release/app-release.apk"
PACKAGE="zw.co.doublegeetech.pashauto.operations"
mkdir -p "$ROOT/smoke"
test -s "$APK"
adb install -r "$APK"
adb logcat -c
adb shell am start -n "$PACKAGE/.MainActivity"
sleep 20
adb shell screencap -p /sdcard/pash-smoke.png || true
adb pull /sdcard/pash-smoke.png "$ROOT/smoke/launch.png" || true
adb logcat -d -v threadtime > "$ROOT/smoke/logcat.txt"
if ! adb shell pidof "$PACKAGE" > "$ROOT/smoke/pid.txt"; then
  echo "PASH app process not alive after cold start"
  grep -E -A 24 'FATAL EXCEPTION|AndroidRuntime|ReactNativeJS|ReactNative' "$ROOT/smoke/logcat.txt" | tail -n 130 || true
  exit 1
fi
# Other system app crashes are ignored; only our process is relevant.
if grep -A 12 'FATAL EXCEPTION' "$ROOT/smoke/logcat.txt" | grep -q "Process: $PACKAGE"; then
  echo "PASH app crashed in Android runtime"
  grep -E -A 24 'FATAL EXCEPTION|Process: '"$PACKAGE" "$ROOT/smoke/logcat.txt" | tail -n 130 || true
  exit 1
fi
echo "PASH Operations process remained alive for 20 seconds after cold launch"
