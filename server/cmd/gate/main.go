// Command gate fronts an Xray WebSocket/HTTPUpgrade inbound and admits only
// connections carrying a valid Oversea client token. See internal/gate.
//
//	GATE_KEYS=<key>[,<previous key>] gate -domain vpn.example.com -upstream 127.0.0.1:10000
//
// Xray listens on 127.0.0.1:10000 with security "none"; this process owns :443
// and the TLS certificate (Let's Encrypt, automatic). Clients use TLS to the domain.
package main

import (
	"crypto/tls"
	"flag"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"golang.org/x/crypto/acme/autocert"

	"oversea/server/internal/gate"
)

func main() {
	domain := flag.String("domain", "", "public domain; enables TLS on :443 with automatic Let's Encrypt certificates")
	upstream := flag.String("upstream", "127.0.0.1:10000", "Xray inbound host:port (plain HTTP)")
	plain := flag.String("plain", "", "listen address for plain HTTP, for testing or when TLS is terminated elsewhere (e.g. :8080)")
	cacheDir := flag.String("certs", "certs", "directory for the certificate cache")
	flag.Parse()

	var keys [][]byte
	for _, k := range strings.Split(os.Getenv("GATE_KEYS"), ",") {
		if k = strings.TrimSpace(k); k != "" {
			keys = append(keys, []byte(k))
		}
	}
	if len(keys) == 0 {
		log.Fatal("GATE_KEYS is empty: set it to the key(s) your Oversea build was made with")
	}
	if *domain == "" && *plain == "" {
		log.Fatal("give -domain (TLS) or -plain (HTTP)")
	}

	up, err := url.Parse("http://" + *upstream)
	if err != nil {
		log.Fatalf("bad -upstream: %v", err)
	}
	h := gate.New(up, keys)

	if *plain != "" {
		log.Printf("plain HTTP gate on %s -> %s", *plain, *upstream)
		log.Fatal((&http.Server{Addr: *plain, Handler: h, ReadHeaderTimeout: 10 * time.Second}).ListenAndServe())
	}

	m := &autocert.Manager{
		Prompt:     autocert.AcceptTOS,
		HostPolicy: autocert.HostWhitelist(*domain),
		Cache:      autocert.DirCache(*cacheDir),
	}
	// :80 only answers ACME challenges; everything else is dropped.
	go func() { log.Print(http.ListenAndServe(":80", m.HTTPHandler(nil))) }()

	srv := &http.Server{
		Addr:              ":443",
		Handler:           h,
		ReadHeaderTimeout: 10 * time.Second,
		TLSConfig:         &tls.Config{GetCertificate: m.GetCertificate, MinVersion: tls.VersionTLS12, NextProtos: []string{"http/1.1", "acme-tls/1"}},
	}
	log.Printf("TLS gate for %s on :443 -> %s", *domain, *upstream)
	log.Fatal(srv.ListenAndServeTLS("", ""))
}
