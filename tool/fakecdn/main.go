// fakecdn is a stand-in for Cloudflare/Fastly in the end-to-end test: it terminates the
// client's connection (here plain HTTP), then forwards to the origin from a fixed SOURCE
// address, adding the provider's client-IP header, exactly like a real CDN edge does.
//
//	cd tool/fakecdn && go run . -listen 127.0.0.1:8091 -origin 127.0.0.1:8081 -src 127.0.0.2 \
//	    -client-ip 198.51.100.77 -header CF-Connecting-IP
package main

import (
	"context"
	"flag"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
)

func main() {
	listen := flag.String("listen", "127.0.0.1:8091", "address clients connect to")
	origin := flag.String("origin", "127.0.0.1:8081", "the gate")
	src := flag.String("src", "127.0.0.2", "source IP the edge uses towards the origin")
	clientIP := flag.String("client-ip", "198.51.100.77", "the 'real client' this edge reports")
	header := flag.String("header", "CF-Connecting-IP", "header carrying the client IP")
	strip := flag.String("strip", "", "request header this edge DROPS (simulates a CDN rule that removes unknown headers)")
	flag.Parse()

	u, _ := url.Parse("http://" + *origin)
	dialer := &net.Dialer{LocalAddr: &net.TCPAddr{IP: net.ParseIP(*src)}}
	p := &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(u)
			r.Out.Header.Del(*header) // a real CDN overwrites whatever the client sent
			r.Out.Header.Set(*header, *clientIP)
			if *strip != "" {
				r.Out.Header.Del(*strip)
			}
		},
		FlushInterval: -1,
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, n, a string) (net.Conn, error) { return dialer.DialContext(ctx, n, a) },
		},
	}
	log.Printf("fake CDN %s -> %s (src %s, reports client %s via %s)", *listen, *origin, *src, *clientIP, *header)
	log.Fatal(http.ListenAndServe(*listen, p))
}
