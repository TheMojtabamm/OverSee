package oversee

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/acme/autocert"

	"oversea/server/internal/gate"
)

// RunGate is `oversee gate`: the reverse proxy in front of Xray. Flags override
// gate.conf; GATE_KEYS (env) is appended to the keys file.
func RunGate(p Paths, args []string) error {
	st := p.LoadSettings()
	fs := flag.NewFlagSet("gate", flag.ContinueOnError)
	domain := fs.String("domain", st.Domain, "public domain; TLS on :443 via Let's Encrypt (not for CDN-hidden origins: use -cert/-key)")
	upstream := fs.String("upstream", st.Upstream, "Xray inbound host:port (plain HTTP)")
	plain := fs.String("plain", st.Plain, "plain-HTTP listen address (testing, or TLS terminated by the CDN: e.g. :8080)")
	allow := fs.String("allow", p.Allow, "allow-list file")
	keys := fs.String("keys", p.Keys, "app keys file")
	certs := fs.String("certs", p.Certs, "certificate cache dir")
	cdn := fs.String("cdn", st.CDN, "none, cloudflare, fastly or generic: trust the CDN's client-IP header")
	proxies := fs.String("proxies", p.Proxies, "CDN IP ranges file (oversee proxies update)")
	onlyProxy := fs.Bool("only-proxy", st.OnlyProxy, "refuse connections that did not come through the CDN")
	cert := fs.String("cert", st.Cert, "TLS certificate file (e.g. Cloudflare Origin CA)")
	keyFile := fs.String("key", st.Key, "TLS private key file")
	tokenDays := fs.Int("token-days", st.TokenDays, "accept tokens from ±N days (default 1): longer lets a tunnel up for days reconnect")
	if err := fs.Parse(args); err != nil {
		return err
	}
	prov, err := gate.ParseProvider(*cdn)
	if err != nil {
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
	if *domain == "" && *plain == "" && *cert == "" {
		return fmt.Errorf("no domain configured: run `oversee` → Setup")
	}
	if (*cert == "") != (*keyFile == "") {
		return fmt.Errorf("-cert and -key must be given together")
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

	// CDN fronting: who may speak for a client, and (optionally) refuse everyone else.
	var tp *gate.TrustedProxies
	if prov != gate.ProviderNone {
		tp, err = gate.LoadTrustedProxies(*proxies)
		if err != nil {
			return fmt.Errorf("proxies: %w", err)
		}
		if tp.Len() == 0 && (prov == gate.ProviderCloudflare || prov == gate.ProviderFastly) {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			n, ferr := p.UpdateProxies(ctx, string(prov), nil)
			cancel()
			if ferr != nil {
				return fmt.Errorf("no %s IP ranges yet and the download failed (%v): run `oversee proxies update` or create %s", prov, ferr, *proxies)
			}
			log.Printf("downloaded %d %s ranges", n, prov)
			if tp, err = gate.LoadTrustedProxies(*proxies); err != nil {
				return err
			}
		}
		if *onlyProxy && tp.Len() == 0 {
			return fmt.Errorf("-only-proxy with an empty trusted list would refuse everyone")
		}
		tp.Watch(3*time.Second, func(e error) { log.Printf("proxies not reloaded (keeping previous): %v", e) })
		if prov == gate.ProviderCloudflare || prov == gate.ProviderFastly {
			go refreshProxiesDaily(p, string(prov))
		}
		log.Printf("CDN mode %s: %d trusted range(s), only-proxy=%v", prov, tp.Len(), *onlyProxy)
	} else if *onlyProxy {
		return fmt.Errorf("-only-proxy needs -cdn")
	}

	up, err := url.Parse("http://" + *upstream)
	if err != nil {
		return fmt.Errorf("bad upstream: %w", err)
	}
	// Probe resistance + leak signal: 20 bad tokens a minute from one (real) client IP
	// blocks it for 10 minutes; per-lock distinct-IP counts go to stats.json for the TUI.
	stats := gate.NewStats()
	stats.WriteLoop(p.Stats, 5*time.Second)
	h := gate.NewWithOptions(up, al.Get, kf.Get, gate.Options{
		Limiter:   gate.NewLimiter(20, time.Minute, 10*time.Minute),
		Stats:     stats,
		Proxies:   tp,
		Provider:  prov,
		OnlyProxy: *onlyProxy,
		Probe:     &gate.Probe{File: p.Probe},
		SkewDays:  clampDays(*tokenDays),
	})
	log.Printf("gate: %d lock(s), %d app key(s), upstream %s", len(al.Get()), len(kf.Get()), *upstream)

	if *plain != "" {
		log.Printf("plain HTTP on %s", *plain)
		return (&http.Server{Addr: *plain, Handler: h, ReadHeaderTimeout: 10 * time.Second}).ListenAndServe()
	}

	tlsConf := &tls.Config{MinVersion: tls.VersionTLS12, NextProtos: []string{"http/1.1"}}
	if *cert != "" {
		cr := &certReloader{cert: *cert, key: *keyFile}
		if _, err := cr.get(nil); err != nil {
			return fmt.Errorf("certificate: %w", err)
		}
		tlsConf.GetCertificate = cr.get
		log.Printf("TLS on :443 from %s", *cert)
	} else {
		m := &autocert.Manager{
			Prompt:     autocert.AcceptTOS,
			HostPolicy: autocert.HostWhitelist(*domain),
			Cache:      autocert.DirCache(*certs),
		}
		go func() { log.Print(http.ListenAndServe(":80", m.HTTPHandler(nil))) }() // ACME only
		tlsConf.GetCertificate = m.GetCertificate
		tlsConf.NextProtos = []string{"http/1.1", "acme-tls/1"}
		log.Printf("TLS on :443 for %s (Let's Encrypt)", *domain)
	}
	srv := &http.Server{Addr: ":443", Handler: h, ReadHeaderTimeout: 10 * time.Second, TLSConfig: tlsConf}
	return srv.ListenAndServeTLS("", "")
}

// refreshProxiesDaily keeps the CDN's ranges current. A failed or short download never
// replaces the working list.
func refreshProxiesDaily(p Paths, provider string) {
	for range time.Tick(24 * time.Hour) {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		n, err := p.UpdateProxies(ctx, provider, nil)
		cancel()
		if err != nil {
			log.Printf("%s range refresh failed (keeping previous): %v", provider, err)
			continue
		}
		log.Printf("refreshed %d %s ranges", n, provider)
	}
}

// certReloader serves a certificate from disk and picks up renewals without a restart.
type certReloader struct {
	cert, key string
	mu        sync.Mutex
	mod       time.Time
	cur       *tls.Certificate
}

func (c *certReloader) get(*tls.ClientHelloInfo) (*tls.Certificate, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	st, err := os.Stat(c.cert)
	if err != nil {
		if c.cur != nil {
			return c.cur, nil // keep serving the last good certificate
		}
		return nil, err
	}
	if c.cur == nil || !st.ModTime().Equal(c.mod) {
		pair, err := tls.LoadX509KeyPair(c.cert, c.key)
		if err != nil {
			if c.cur != nil {
				log.Printf("certificate reload failed (keeping previous): %v", err)
				return c.cur, nil
			}
			return nil, err
		}
		c.cur, c.mod = &pair, st.ModTime()
	}
	return c.cur, nil
}

func clampDays(n int) int {
	switch {
	case n < 1:
		return 1
	case n > 7:
		return 7
	}
	return n
}
