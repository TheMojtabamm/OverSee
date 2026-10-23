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

go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
export PATH="$(go env GOPATH)/bin:$PATH"
gomobile init

gomobile bind -v -trimpath -androidapi 24 -target="$TARGETS" \
  -ldflags="-s -w -buildid= -checklinkname=0" -o "$OUT/libv2ray.aar" .

ls -la "$OUT/libv2ray.aar"
