package oversee

import "fmt"

// XrayInbound returns an Xray inbound the gate can sit in front of: a VLESS
// WebSocket inbound on loopback with no TLS (the gate terminates TLS).
func XrayInbound(port int, path, uuid string) string {
	return fmt.Sprintf(`{
  "inbounds": [{
    "listen": "127.0.0.1",
    "port": %d,
    "protocol": "vless",
    "settings": { "clients": [{ "id": "%s" }], "decryption": "none" },
    "streamSettings": { "network": "ws", "wsSettings": { "path": "%s" } }
  }]
}`, port, uuid, path)
}

// ClientLink is the vless:// link that goes with XrayInbound, to paste into the app.
func ClientLink(domain, path, uuid, name string) string {
	if domain == "" {
		domain = "YOUR.DOMAIN"
	}
	return fmt.Sprintf("vless://%s@%s:443?encryption=none&security=tls&sni=%s&type=ws&path=%s#%s",
		uuid, domain, domain, urlEscape(path), name)
}

func urlEscape(p string) string {
	out := ""
	for _, r := range p {
		if r == '/' {
			out += "%2F"
		} else {
			out += string(r)
		}
	}
	return out
}

// NewUUID makes a random v4 UUID.
func NewUUID() string {
	h := RandomHex(16)
	b := []byte(h)
	b[12] = '4'
	b[16] = "89ab"[int(b[16]%4)]
	return fmt.Sprintf("%s-%s-%s-%s-%s", b[0:8], b[8:12], b[12:16], b[16:20], b[20:32])
}
