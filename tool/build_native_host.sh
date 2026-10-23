#!/usr/bin/env bash
# Builds the native core as a host shared library for tests, with the same dev secrets
# the Dart tests use (LOCK_P1..P4 = aaaa…/bbbb…/cccc…/dddd…, gate key "gate-dev-key").
# Optional: MASKED=1 builds it the way CI does (hex(secret XOR mask)).
#
#   tool/build_native_host.sh /tmp/libovs_host.so
#   OVS_NATIVE_LIB=/tmp/libovs_host.so flutter test \
#     --dart-define=LOCK_P1=aaaaaaaaaaaaaaaa --dart-define=LOCK_P2=bbbbbbbbbbbbbbbb \
#     --dart-define=LOCK_P3=cccccccccccccccc --dart-define=LOCK_P4=dddddddddddddddd \
#     --dart-define=GATE_KEY=gate-dev-key
set -euo pipefail
OUT="${1:-/tmp/libovs_host.so}"
SRC="$(cd "$(dirname "$0")/.." && pwd)/android/app/src/main/cpp"
P1=aaaaaaaaaaaaaaaa; P2=bbbbbbbbbbbbbbbb; P3=cccccccccccccccc; P4=dddddddddddddddd; GATE=gate-dev-key; MASK=""
if [ "${MASKED:-0}" = 1 ]; then
  eval "$(cd "$(dirname "$0")/.." && LOCK_P1=$P1 LOCK_P2=$P2 LOCK_P3=$P3 LOCK_P4=$P4 GATE_KEY=$GATE \
    dart run tool/mask_secrets.dart | sed 's/^/export /')"
  P1=$LOCK_P1_M; P2=$LOCK_P2_M; P3=$LOCK_P3_M; P4=$LOCK_P4_M; GATE=$GATE_KEY_M; MASK=$LOCK_MASK
fi
g++ -std=c++17 -O2 -shared -fPIC -fvisibility=hidden \
  -DOVS_P1="\"$P1\"" -DOVS_P2="\"$P2\"" -DOVS_P3="\"$P3\"" -DOVS_P4="\"$P4\"" \
  -DOVS_GATE="\"$GATE\"" -DOVS_MASK="\"$MASK\"" \
  "$SRC"/sha256.cpp "$SRC"/ovs_core.cpp "$SRC"/ovs_ffi.cpp -o "$OUT"
echo "built $OUT"
