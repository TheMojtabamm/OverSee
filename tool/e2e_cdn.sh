#!/usr/bin/env bash
# End-to-end proof that the gate works BEHIND A CDN, with real Xray:
#
#   Xray client -> fake CDN edge (adds CF-Connecting-IP, source 127.0.0.2) -> gate -> Xray server -> origin
#
# Gate runs with  -cdn cloudflare -only-proxy  and a trusted list containing ONLY the edge.
# Checks:
#   1  owner through the CDN works                          (WebSocket upgrade + token header pass the CDN)
#   2  same owner connecting DIRECTLY to the gate is refused (origin can't be reached around the CDN)
#   3  a client with no token through the CDN is refused
#   4  two different "real clients" behind two edges are counted as 2 distinct IPs (not 1 edge IP)
#
#   XRAY=/path/to/xray tool/e2e_cdn.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XRAY="${XRAY:-xray}"
W="${W:-$(mktemp -d)}"; trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
UUID=11111111-2222-3333-4444-555555555555
KEY=e2e-cdn-key
CODE=0123456789abcdef0123456789abcdef
FP=3FA9-0C21-B7D4-9E10
ORIGIN_IP="$(hostname -I | awk '{print $1}')"
[ -n "$ORIGIN_IP" ] || { echo "no non-loopback IP available"; exit 2; }

echo "page-from-origin" > "$W/index.html"
(cd "$W" && python3 -m http.server 9099 --bind "$ORIGIN_IP" >/dev/null 2>&1) &

cat > "$W/server.json" <<EOF
{"log":{"loglevel":"warning"},
 "inbounds":[{"listen":"127.0.0.1","port":10000,"protocol":"vless",
   "settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},
   "streamSettings":{"network":"ws","wsSettings":{"path":"/ws"}}}],
 "outbounds":[{"protocol":"freedom","settings":{"finalRules":[{"action":"allow"}]}}]}
EOF
"$XRAY" run -c "$W/server.json" >"$W/server.log" 2>&1 &

(cd "$ROOT/server" && go build -o "$W/oversee" ./cmd/oversee)
(cd "$ROOT/tool/fakecdn" && go build -o "$W/fakecdn" .)
echo "$CODE $FP e2e" > "$W/allow.txt"
printf '%s\n' "$KEY" > "$W/keys.txt"
# the ONLY trusted edge addresses; a direct client comes from 127.0.0.1 and is not in here
printf '# fake CDN edges\n127.0.0.2/32\n127.0.0.3/32\n' > "$W/proxies.txt"
OVERSEE_DIR="$W" "$W/oversee" gate -plain 127.0.0.1:8081 -upstream 127.0.0.1:10000 \
  -allow "$W/allow.txt" -keys "$W/keys.txt" -cdn cloudflare -proxies "$W/proxies.txt" -only-proxy >"$W/gate.log" 2>&1 &

"$W/fakecdn" -listen 127.0.0.1:8091 -origin 127.0.0.1:8081 -src 127.0.0.2 -client-ip 198.51.100.77 >"$W/cdn1.log" 2>&1 &
"$W/fakecdn" -listen 127.0.0.1:8092 -origin 127.0.0.1:8081 -src 127.0.0.3 -client-ip 198.51.100.78 >"$W/cdn2.log" 2>&1 &

mk() { # name port with_token
  local link="vless://$UUID@127.0.0.1:$2?encryption=none&security=none&type=ws&path=%2Fws#e2e"
  local extra=(); [ "$3" = yes ] && extra=("$KEY" "$CODE" "$FP")
  (cd "$ROOT" && dart run tool/e2e_client_config.dart "$link" "${extra[@]}") | python3 -c '
import json,sys
c=json.load(sys.stdin)
c["inbounds"]=[{"tag":"socks","listen":"127.0.0.1","port":int(sys.argv[1]),"protocol":"socks","settings":{"udp":False}}]
c["routing"]["rules"]=[r for r in c["routing"]["rules"] if r.get("outboundTag")!="direct"]
c["dns"]={"servers":["localhost"]}
print(json.dumps(c))' "$4" > "$W/$1.json"
}
mk via_cdn_a   8091 yes 10801   # through edge 1 (real client .77)
mk via_cdn_b   8092 yes 10802   # through edge 2 (real client .78)
mk direct      8081 yes 10803   # straight at the gate, perfect token
mk no_token    8091 no  10804   # through the CDN but without the app token
for n in via_cdn_a via_cdn_b direct no_token; do "$XRAY" run -c "$W/$n.json" >"$W/$n.log" 2>&1 & done
sleep 5

fetch() { curl -sS -m 6 --socks5-hostname "127.0.0.1:$1" "http://$ORIGIN_IP:9099/index.html" 2>&1 || true; }
OK="page-from-origin"
A="$(fetch 10801)"; B="$(fetch 10802)"; D="$(fetch 10803)"; N="$(fetch 10804)"
echo "1 via CDN (client .77)   : ${A:0:50}"
echo "  via CDN (client .78)   : ${B:0:50}"
echo "2 direct to the gate     : ${D:0:50}"
echo "3 via CDN, no token      : ${N:0:50}"
[[ "$A" == *$OK* && "$B" == *$OK* ]] || { echo "FAIL: clients through the CDN could not connect"; tail -n 6 "$W/gate.log"; tail -n 4 "$W/cdn1.log"; exit 1; }
[[ "$D" != *$OK* ]] || { echo "FAIL: the origin was reachable around the CDN"; exit 1; }
[[ "$N" != *$OK* ]] || { echo "FAIL: client without token got through the CDN"; exit 1; }

sleep 6
python3 - "$W/stats.json" <<'PY'
import json,sys
raw=open(sys.argv[1]).read(); sn=json.loads(raw)
lk=sn["locks"][0]
assert lk["distinctIps"]==2, ("expected the 2 REAL clients, not 1 edge IP", sn)
assert sn["rejects"].get("not_via_cdn",0)>=1, sn
assert sn["rejects"].get("no_token",0)>=1, sn
for ip in ("198.51.100.77","198.51.100.78","127.0.0.2"): assert ip not in raw, "raw IP leaked to disk"
print("4 stats ok: distinct real clients =", lk["distinctIps"], "| refused:", sn["rejects"])
PY
echo "PASS"
