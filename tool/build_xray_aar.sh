#!/usr/bin/env bash
# Builds libv2ray.aar (Xray-core for Android) from a pinned AndroidLibXrayLite
# version, from source, via gomobile. No prebuilt binary is downloaded.
#
#   ANDROID_HOME=... ANDROID_NDK_HOME=... tool/build_xray_aar.sh [targets]
#   targets default: android/arm64,android/arm,android/amd64
#
# Output: android/app/libs/libv2ray.aar   (git-ignored; CI builds it each time)
set -euo pipefail

# Pin. Bump deliberately; go.sum of the module + Go's checksum DB verify contents.
VERSION="v0.0.0-20261022013006-76a6e2172210"
TARGETS="${1:-android/arm64,android/arm,android/amd64}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/android/app/libs"
mkdir -p "$OUT"

WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK" 2>/dev/null || true; rm -rf "$WORK"' EXIT

cd "$WORK"
cat > go.mod <<EOF
module fetch
go 1.24
EOF
go mod download "github.com/2dust/AndroidLibXrayLite@$VERSION"
SRC="$(go list -m -f '{{.Dir}}' "github.com/2dust/AndroidLibXrayLite@$VERSION")"

mkdir build && cp -r "$SRC"/. build/ && chmod -R u+w build && cd build

# --- Plain (no-TLS) VLESS / Trojan -------------------------------------------------------
# Recent Xray-core refuses to even load a vless/trojan outbound without TLS (or VLESS
# encryption) to a public address ("... is prohibited unless the server address is a private IP
# or domain"). Plain `vless://...security=none&type=ws` links are common (and are what many
# panels hand out), and other clients run them, so the app must too. The guard is removed here
# and the app shows an explicit "Not encrypted" warning on such configs instead.
XRAY_MOD="github.com/xtls/xray-core"
XRAY_SRC="$(go list -m -f '{{.Dir}}' "$XRAY_MOD")"
rm -rf "$WORK/xray-core-patched"
cp -r "$XRAY_SRC" "$WORK/xray-core-patched" && chmod -R u+w "$WORK/xray-core-patched"
FUNC='func validateOutboundTransportSecurity(rawConfig interface{}, senderSettings *proxyman.SenderConfig) error {'
grep -qF "$FUNC" "$WORK/xray-core-patched/infra/conf/xray.go" \
  || { echo "xray-core changed: validateOutboundTransportSecurity not found; update the patch in tool/build_xray_aar.sh"; exit 1; }
python3 - "$WORK/xray-core-patched/infra/conf/xray.go" "$FUNC" <<'PY'
import sys
p, func = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace(func, func + "\n\treturn nil // Oversea: plain vless/trojan allowed (the app warns the user)\n", 1)
open(p, "w").write(s)
PY
go mod edit -replace "$XRAY_MOD=$WORK/xray-core-patched"

# Prove the patch works: a public-domain, no-TLS VLESS/WS config must load.
cat > zz_oversea_plain_test.go <<'GO'
package libv2ray

import (
	"strings"
	"testing"

	coreserial "github.com/xtls/xray-core/infra/conf/serial"
)

func TestPlainVlessLoads(t *testing.T) {
	cfg := `{"outbounds":[{"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":"example.com","port":1001,
	  "users":[{"id":"b7dd9763-7399-4e5f-bcf3-8dc2a17b72d5","encryption":"none"}]}]},
	  "streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/x","host":"example.com"}}}]}`
	if _, err := coreserial.LoadJSONConfig(strings.NewReader(cfg)); err != nil {
		t.Fatalf("plain vless/ws still rejected: %v", err)
	}
}
GO
go test -count=1 -run TestPlainVlessLoads . || { echo "patched core still rejects plain VLESS"; exit 1; }
rm -f zz_oversea_plain_test.go
[ -n "${OVERSEA_PATCH_ONLY:-}" ] && { echo "patch verified"; exit 0; }

go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
export PATH="$(go env GOPATH)/bin:$PATH"
gomobile init

gomobile bind -v -trimpath -androidapi 24 -target="$TARGETS" \
  -ldflags="-s -w -buildid= -checklinkname=0" -o "$OUT/libv2ray.aar" .

ls -la "$OUT/libv2ray.aar"
