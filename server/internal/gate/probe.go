package gate

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// ProbePath is the diagnostic URL prefix. It exists only while an operator runs
// `oversee cdn-test` (a random nonce valid for minutes); otherwise it is a plain 404 like
// everything else, so scanners learn nothing from it.
const ProbePath = "/__probe/"

// Probe answers "what did the request look like when it reached the gate?" so the operator
// can check that the CDN passes the token header and reports the real client IP.
type Probe struct {
	// File holds `<nonce> <unix expiry>`, written by `oversee cdn-test`.
	File string
}

func (pr *Probe) match(nonce string, now time.Time) bool {
	if pr == nil || pr.File == "" || len(nonce) < 16 {
		return false
	}
	b, err := os.ReadFile(pr.File)
	if err != nil {
		return false
	}
	f := strings.Fields(string(b))
	if len(f) != 2 {
		return false
	}
	exp, err := strconv.ParseInt(f[1], 10, 64)
	if err != nil || now.Unix() > exp {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(f[0]), []byte(nonce)) == 1
}

// ProbeReport is what the gate saw. It never contains the token itself, only its length
// and a hash, so the client can verify the header arrived unmodified.
type ProbeReport struct {
	OK            bool              `json:"ok"`
	HeaderPresent bool              `json:"headerPresent"`
	HeaderLen     int               `json:"headerLen"`
	HeaderSHA256  string            `json:"headerSha256"`
	ClientIP      string            `json:"clientIp"`
	ViaTrustedCDN bool              `json:"viaTrustedCdn"`
	Peer          string            `json:"peer"`
	CDNHeaders    map[string]string `json:"cdnHeaders"`
	Upgrade       string            `json:"upgrade"`
	Proto         string            `json:"proto"`
}

// HeaderDigest is the value both sides compute to compare the header.
func HeaderDigest(v string) string {
	h := sha256.Sum256([]byte(v))
	return hex.EncodeToString(h[:8])
}

func (pr *Probe) report(r *http.Request, ip string, via bool) ProbeReport {
	v := r.Header.Get(Header)
	peer := r.RemoteAddr
	rep := ProbeReport{
		OK: true, HeaderPresent: v != "", HeaderLen: len(v), ClientIP: ip, ViaTrustedCDN: via, Peer: peer,
		CDNHeaders: map[string]string{}, Upgrade: r.Header.Get("Upgrade"), Proto: r.Header.Get("X-Forwarded-Proto"),
	}
	if v != "" {
		rep.HeaderSHA256 = HeaderDigest(v)
	}
	for _, h := range []string{"CF-Connecting-IP", "Fastly-Client-IP", "X-Forwarded-For", "CF-Ray", "X-Forwarded-Proto"} {
		if x := r.Header.Get(h); x != "" {
			rep.CDNHeaders[h] = x
		}
	}
	return rep
}

func writeProbe(w http.ResponseWriter, rep ProbeReport) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	json.NewEncoder(w).Encode(rep)
}
