#!/usr/bin/env bash
# Fails if any of the given secrets appears as a plain string in the APK's native
# libraries or Dart snapshot. Secrets are read from the environment (never printed).
#
#   LOCK_P1=… LOCK_P2=… LOCK_P3=… LOCK_P4=… GATE_KEY=… tool/verify_apk_secrets.sh app-release.apk
set -euo pipefail
APK="${1:?usage: verify_apk_secrets.sh <apk>}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
unzip -q -o "$APK" 'lib/*' -d "$W" 2>/dev/null || { echo "no native libs in $APK"; exit 2; }

: > "$W/patterns"
for v in LOCK_P1 LOCK_P2 LOCK_P3 LOCK_P4 GATE_KEY; do
  val="${!v:-}"
  [ -n "$val" ] && printf '%s\n' "$val" >> "$W/patterns"
done
[ -s "$W/patterns" ] || { echo "no secrets in the environment; nothing to check"; exit 2; }

bad=0; checked=0
for lib in "$W"/lib/*/*.so; do
  checked=$((checked+1))
  # Not `strings | grep -q`: with pipefail, grep exiting early SIGPIPEs strings and the
  # pipeline reports failure even when the secret WAS found (a silent false negative).
  strings -a "$lib" > "$W/strings.txt"
  if grep -qF -f "$W/patterns" "$W/strings.txt"; then
    echo "LEAK: a secret appears as plain text in ${lib#"$W"/}"; bad=1
  fi
done
[ "$checked" -gt 0 ] || { echo "no .so files found"; exit 2; }
[ "$bad" = 0 ] && echo "ok: none of $(wc -l < "$W/patterns") secret(s) found in $checked native lib(s)"
exit "$bad"
