// Command oversee manages the Oversea gate on your server.
//
//	oversee                 interactive manager (TUI)
//	oversee gate            run the gate (this is what the systemd service runs)
//	oversee list            list allowed locks
//	oversee add "<line>"    allow a lock (the line the app shows after locking)
//	oversee revoke <id>     revoke a lock (id or code, ≥4 chars)
//	oversee keys            list app keys (masked)
//	oversee key add <key>   make <key> the current app key
//	oversee status          service state + counts
//	oversee fixperms        make the gate service able to read its files (run by the service itself)
//	oversee version
package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"oversea/server/internal/oversee"
	"oversea/server/internal/tui"
)

// Set at build time: -ldflags "-X main.version=..."
var version = "dev"

func main() {
	p := oversee.DefaultPaths()
	args := os.Args[1:]
	if len(args) == 0 {
		if err := tui.Run(p); err != nil {
			fatal(err)
		}
		return
	}
	switch args[0] {
	case "gate":
		if err := oversee.RunGate(p, args[1:]); err != nil {
			fatal(err)
		}
	case "list", "ls":
		locks, err := p.Locks()
		check(err)
		if len(locks) == 0 {
			fmt.Println("no locks")
		}
		for _, l := range locks {
			fmt.Printf("%s  %s  %s\n", l.CodeID, l.CreatorFp, l.Note)
		}
	case "add":
		need(args, 2, `oversee add "<code> <fingerprint> [note]"`)
		l, err := p.AddLock(strings.Join(args[1:], " "))
		check(err)
		fmt.Printf("added %s (%s) — live within a few seconds\n", l.CodeID, l.CreatorFp)
	case "revoke", "rm":
		need(args, 2, "oversee revoke <lock id or code>")
		l, err := p.RevokeLock(args[1])
		check(err)
		fmt.Printf("revoked %s (%s) — every copy stops working within a few seconds\n", l.CodeID, l.Note)
	case "keys":
		keys, err := p.ListKeys()
		check(err)
		if len(keys) == 0 {
			fmt.Println("no app keys (the gate refuses everyone until you add one)")
		}
		for i, k := range keys {
			tag := "previous"
			if i == 0 {
				tag = "current"
			}
			fmt.Printf("%s  %s\n", oversee.MaskKey(k), tag)
		}
	case "key":
		need(args, 3, "oversee key add <key>")
		if args[1] != "add" {
			fatal(fmt.Errorf("unknown: key %s", args[1]))
		}
		check(p.AddKey(args[2]))
		fmt.Println("key added as current")
	case "status":
		st := oversee.Status()
		locks, _ := p.Locks()
		keys, _ := p.ListKeys()
		s := p.LoadSettings()
		fmt.Printf("service: %s (boot: %s)\ndomain:  %s\nupstream: %s\nlocks:   %d\napp keys: %d\n",
			st.Active, st.Enabled, dash(s.Domain), s.Upstream, len(locks), len(keys))
	case "doctor":
		findings := p.Doctor(oversee.RealDoctorEnv())
		for _, f := range findings {
			mark := map[oversee.Level]string{oversee.OK: "✓", oversee.Warn: "⚠", oversee.Fail: "✗"}[f.Level]
			fmt.Printf("%s %s\n", mark, f.Title)
			if f.Level != oversee.OK {
				fmt.Printf("    %s\n", f.Detail)
				if f.Fix != "" {
					fmt.Printf("    fix: %s\n", f.Fix)
				}
			}
		}
		if oversee.Worst(findings) == oversee.Fail {
			os.Exit(1)
		}
	case "cdn-test":
		url := ""
		for i := 1; i+1 < len(args); i++ {
			if args[i] == "--url" {
				url = args[i+1]
			}
		}
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()
		findings, err := p.CDNTest(ctx, url, nil)
		check(err)
		for _, f := range findings {
			mark := map[oversee.Level]string{oversee.OK: "✓", oversee.Warn: "⚠", oversee.Fail: "✗"}[f.Level]
			fmt.Printf("%s %s\n", mark, f.Title)
			if f.Level != oversee.OK {
				fmt.Printf("    %s\n", f.Detail)
				if f.Fix != "" {
					fmt.Printf("    fix: %s\n", f.Fix)
				}
			} else if f.Detail != "" {
				fmt.Printf("    %s\n", f.Detail)
			}
		}
		if oversee.Worst(findings) == oversee.Fail {
			os.Exit(1)
		}
	case "set":
		need(args, 3, "oversee set <domain|upstream|plain|leak-ips|cdn|only-proxy|cert|key> <value>")
		check(p.SetSetting(args[1], args[2]))
		fmt.Printf("%s saved — restart the gate to apply (sudo systemctl restart oversee-gate)\n", args[1])
	case "proxies":
		sub := "show"
		if len(args) > 1 {
			sub = args[1]
		}
		switch sub {
		case "update":
			prov := p.LoadSettings().CDN
			if len(args) > 2 {
				prov = args[2]
			}
			if prov != "cloudflare" && prov != "fastly" {
				fatal(fmt.Errorf("pick a CDN: oversee proxies update cloudflare|fastly (or set it in Setup)"))
			}
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer cancel()
			n, err := p.UpdateProxies(ctx, prov, nil)
			check(err)
			fmt.Printf("%s: %d ranges written to %s (the running gate picks them up within seconds)\n", prov, n, p.Proxies)
		case "show":
			i := p.ProxyInfo()
			s := p.LoadSettings()
			if i.Age < 0 {
				fmt.Printf("cdn: %s  | no proxies.txt yet\n", dash(s.CDN))
			} else {
				fmt.Printf("cdn: %s  | %d ranges | updated %s ago | only-proxy: %v\n", dash(s.CDN), i.Count, i.Age.Round(time.Minute), s.OnlyProxy)
			}
		default:
			fatal(fmt.Errorf("unknown: proxies %s", sub))
		}
	case "fixperms":
		n, err := oversee.FixPerms(p.Dir)
		check(err)
		fmt.Printf("fixed %d files in %s\n", n, p.Dir)
	case "version", "-v", "--version":
		fmt.Println("oversee", version)
	case "help", "-h", "--help":
		fmt.Print(strings.TrimLeft(helpText, "\n"))
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n\n%s", args[0], helpText)
		os.Exit(2)
	}
}

const helpText = `
oversee — manage the Oversea gate

  oversee                 interactive manager (TUI)
  oversee gate            run the gate (the systemd service does this)
  oversee list            list allowed locks
  oversee add "<line>"    allow a lock (the line the app shows after locking)
  oversee revoke <id>     revoke a lock (id or code, at least 4 characters)
  oversee keys            list app keys (masked)
  oversee key add <key>   make <key> the current app key
  oversee cdn-test        check the token header and real client IP survive your CDN
  oversee doctor          audit the setup (is Xray reachable around the gate?)
  oversee set <name> <v>  change a setting (domain, upstream, cdn, only-proxy, cert, key, …)
  oversee proxies update  refresh the CDN's IP ranges (cloudflare|fastly)
  oversee proxies         show the CDN mode and range count
  oversee status          service state and counts
  oversee version
`

func need(a []string, n int, usage string) {
	if len(a) < n {
		fmt.Fprintln(os.Stderr, "usage:", usage)
		os.Exit(2)
	}
}

func check(err error) {
	if err != nil {
		fatal(err)
	}
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "oversee:", err)
	os.Exit(1)
}

func dash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}
