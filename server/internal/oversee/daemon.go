package oversee

import (
	"crypto/tls"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"golang.org/x/crypto/acme/autocert"

	"oversea/server/internal/gate"
)

// RunGate is `oversee gate`: the reverse proxy in front of Xray. Flags override
// gate.conf; GATE_KEYS (env) is appended to the keys file.
func RunGate(p Paths, args []string) error {
	st := p.LoadSettings()
	fs := flag.NewFlagSet("gate", flag.ContinueOnError)
	domain := fs.String("domain", st.Domain, "public domain; TLS on :443 via Let's Encrypt")
	upstream := fs.String("upstream", st.Upstream, "Xray inbound host:port (plain HTTP)")
	plain := fs.String("plain", st.Plain, "plain-HTTP listen address (testing, or TLS terminated elsewhere)")
	allow := fs.String("allow", p.Allow, "allow-list file")
	keys := fs.String("keys", p.Keys, "app keys file")
	certs := fs.String("certs", p.Certs, "certificate cache dir")
	if err := fs.Parse(args); err != nil {
		return err
	}

	var env [][]byte
	for _, k := range strings.Split(os.Getenv("GATE_KEYS"), ",") {
		if k = strings.TrimSpace(k); k != "" {
			env = append(env, []byte(k))
		}
	}
	kf, err := gate.LoadKeyFile(*keys, env)
	if err != nil {
		return fmt.Errorf("keys: %w", err)
	}
	if len(kf.Get()) == 0 {
		return fmt.Errorf("no app key configured: run `oversee` → Keys, or set GATE_KEYS")
	}
	if *domain == "" && *plain == "" {
		return fmt.Errorf("no domain configured: run `oversee` → Setup")
	}
	if _, err := os.Stat(*allow); os.IsNotExist(err) {
		_ = os.MkdirAll(p.Dir, 0o750)
		_ = os.WriteFile(*allow, []byte("# <32-hex code> <creator fingerprint> [note]\n"), 0o640)
	}
	al, err := gate.LoadAllowList(*allow)
	if err != nil {
		return fmt.Errorf("allow-list: %w", err)
	}
	kf.Watch(3*time.Second, func(e error) { log.Printf("keys not reloaded (keeping previous): %v", e) })
	al.Watch(3*time.Second, func(e error) { log.Printf("allow-list not reloaded (keeping previous): %v", e) })

	up, err := url.Parse("http://" + *upstream)
	if err != nil {
		return fmt.Errorf("bad upstream: %w", err)
	}
	h := gate.New(up, al.Get, kf.Get)
	log.Printf("gate: %d lock(s), %d app key(s), upstream %s", len(al.Get()), len(kf.Get()), *upstream)

	if *plain != "" {
		log.Printf("plain HTTP on %s", *plain)
		return (&http.Server{Addr: *plain, Handler: h, ReadHeaderTimeout: 10 * time.Second}).ListenAndServe()
	}
	m := &autocert.Manager{
		Prompt:     autocert.AcceptTOS,
		HostPolicy: autocert.HostWhitelist(*domain),
		Cache:      autocert.DirCache(*certs),
	}
	go func() { log.Print(http.ListenAndServe(":80", m.HTTPHandler(nil))) }() // ACME only
	srv := &http.Server{
		Addr:              ":443",
		Handler:           h,
		ReadHeaderTimeout: 10 * time.Second,
		TLSConfig: &tls.Config{
			GetCertificate: m.GetCertificate,
			MinVersion:     tls.VersionTLS12,
			NextProtos:     []string{"http/1.1", "acme-tls/1"},
		},
	}
	log.Printf("TLS on :443 for %s", *domain)
	return srv.ListenAndServeTLS("", "")
}
