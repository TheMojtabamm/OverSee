#!/usr/bin/env bash
# Runs inside an Android emulator (see .github/workflows/emulator-smoke.yml): installs the
# release APK, launches it and fails (printing the crash) if the process is not alive after
# a few seconds.
set -u
APK="${1:-build/app/outputs/flutter-apk/app-release.apk}"
PKG=com.oversea.oversea
mkdir -p build/smoke
adb install -r -t "$APK" || { echo "INSTALL FAILED"; exit 1; }
adb logcat -c
adb shell am start -W -n "$PKG/.MainActivity" || true
sleep 15
PID=$(adb shell pidof "$PKG" | tr -d '\r')
adb logcat -d > build/smoke/logcat.txt
adb exec-out screencap -p > build/smoke/screen.png || true
if [ -z "$PID" ]; then
  echo "=== APP IS NOT RUNNING (crashed or exited) ==="
  grep -nE "FATAL EXCEPTION|AndroidRuntime|Fatal signal|SIGSEGV|SIGABRT|backtrace:|UnsatisfiedLink|ClassNotFound|NoSuchMethod|Process $PKG.*died|ActivityManager.*$PKG" build/smoke/logcat.txt | head -60
  echo "--- crash context ---"
  grep -nE "FATAL EXCEPTION|Fatal signal" -A30 build/smoke/logcat.txt | head -120
  exit 1
fi
echo "app is running (pid $PID)"
grep -nE "FATAL|Fatal signal" build/smoke/logcat.txt | head -5 || true
exit 0
