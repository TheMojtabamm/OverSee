#!/usr/bin/env bash
# Oversea gate manager installer.
#
#   curl -fsSL https://github.com/themojtabamm/OverSee/releases/download/server-latest/install.sh | sudo bash
#
# Run it again at any time to update to the newest server build.
#
# Options (env):  OVERSEE_VERSION=server-v1.2.3   pin a release (default: server-latest)
#                 OVERSEE_REPO=owner/repo           where releases live
#                 OVERSEE_BASE_URL=https://mirror/dir  download from a mirror instead
# Uninstall:      curl -fsSL …/install.sh | sudo bash -s -- --uninstall
set -euo pipefail

REPO="${OVERSEE_REPO:-themojtabamm/OverSee}"
VERSION="${OVERSEE_VERSION:-server-latest}"
BIN=/usr/local/bin/oversee
DIR=/etc/oversea
UNIT=/etc/systemd/system/oversee-gate.service

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root:  curl -fsSL … | sudo bash"
[ "$(uname -s)" = Linux ] || die "Linux only"

if [ "${1:-}" = "--uninstall" ]; then
  systemctl disable --now oversee-gate 2>/dev/null || true
  rm -f "$UNIT" "$BIN"; systemctl daemon-reload 2>/dev/null || true
  say "removed. Your data in $DIR was kept (delete it yourself if you want)."
  exit 0
fi

case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "unsupported CPU: $(uname -m)" ;;
esac

command -v curl >/dev/null || die "curl is required"
command -v sha256sum >/dev/null || die "sha256sum is required"

if [ -n "${OVERSEE_BASE_URL:-}" ]; then BASE="$OVERSEE_BASE_URL"   # testing / mirrors
else BASE="https://github.com/$REPO/releases/download/$VERSION"; fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
say "downloading oversee ($ARCH)"
curl -fsSL "$BASE/oversee-linux-$ARCH"        -o "$TMP/oversee"           || die "download failed (is the release public?)"
curl -fsSL "$BASE/oversee-linux-$ARCH.sha256" -o "$TMP/oversee.sha256"    || die "checksum download failed"
say "verifying checksum"
( cd "$TMP" && echo "$(cut -d' ' -f1 oversee.sha256)  oversee" | sha256sum -c - >/dev/null ) || die "checksum mismatch — refusing to install"

WAS_ACTIVE=0; systemctl is-active --quiet oversee-gate 2>/dev/null && WAS_ACTIVE=1
install -m 0755 "$TMP/oversee" "$BIN"
install -d -m 0750 "$DIR"
[ -f "$DIR/allow.txt" ] || printf '# <32-hex code> <creator fingerprint> [note]\n' > "$DIR/allow.txt"
chmod 0640 "$DIR/allow.txt"

if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then
  cat > "$UNIT" <<'UNITEOF'
[Unit]
Description=Oversea gate
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/oversee gate
Restart=on-failure
RestartSec=3
# binds :80/:443 without running as root
User=oversee
Group=oversee
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/etc/oversea
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNITEOF
  id oversee >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin oversee
  chown -R root:oversee "$DIR"; chmod 0770 "$DIR"; chmod 0660 "$DIR/allow.txt" 2>/dev/null || true
  [ -f "$DIR/keys.txt" ] && chmod 0660 "$DIR/keys.txt" || true
  systemctl daemon-reload
  say "service installed (not started yet)"
else
  say "systemd not found: run the gate yourself with  oversee gate"
fi

if [ "$WAS_ACTIVE" = 1 ]; then systemctl restart oversee-gate && say "gate restarted on the new version"; fi
say "installed $("$BIN" version)"
cat <<'MSG'

Next:
  1. run      sudo oversee        (opens the manager)
  2. Keys     add your app's GATE_KEY
  3. Setup    set your domain, point Xray's WebSocket inbound at 127.0.0.1:10000
  4. Locks    paste the line the app shows after "Lock + Server gate"
  5. Status   press  e  (enable at boot)  then  s  (start)

MSG
