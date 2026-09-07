// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Command macagent is the Mac half of Vitruvian Remote: a small daemon that
// serves the machine's vital signs over HTTP so the phone can show real
// numbers instead of MockHost, and -- once a person has paired a phone from
// this Mac's keyboard -- runs commands on its behalf.
//
// v1.0 was read-only and said so everywhere. v1.1 is not, and the honest
// summary is this: reading needs nothing but reachability on the tailnet,
// because everything it returns is what Activity Monitor already shows.
// Acting needs a 64-hex-character token that only pairing issues, and
// pairing needs someone typing a six-digit code into a terminal on this
// machine. Anyone holding that token can run commands as this user. That is
// the feature, and it is why the token is 0600 and why every act call is
// logged. It still needs no root, still binds only to loopback and the
// Tailscale interface, and killing it still drops the app back to simulated
// data.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const version = "1.1.0"

// defaultPort is arbitrary and unregistered. Chosen to not collide with
// anything devx or the homelab already listens on.
const defaultPort = "7411"

func main() {
	extendPath()
	log.SetPrefix("[vitruvian-remote-agent] ")
	log.SetFlags(log.Ltime)

	// Subcommands are dispatched BEFORE flag.Parse, because they are not the
	// server and share none of its flags. `pair 482917` with the server's
	// flag set would reject the code as a positional argument.
	if len(os.Args) > 1 && !strings.HasPrefix(os.Args[1], "-") {
		if err := subcommand(os.Args[1], os.Args[2:]); err != nil {
			log.Fatal(err)
		}
		return
	}

	var (
		listen    = flag.String("listen", "127.0.0.1:"+defaultPort, "address to listen on")
		tailscale = flag.Bool("tailscale", true, "also listen on this machine's Tailscale IPv4, if it has one")
		interval  = flag.Duration("interval", 2*time.Second, "how often to refresh the fast readings")
		configDir = flag.String("config-dir", "", "where the token and pairing live (default ~/.config/vitruvian-remote-agent)")
		kubeCfg   = flag.String("kubeconfig", "", "kubeconfig FILE for /v1/k8s (the lab cluster's is not ~/.kube/config); empty means kubectl's default")
		kubeCtx   = flag.String("kube-context", "", "kubeconfig context for /v1/k8s; empty means not configured")
		promURL   = flag.String("prometheus-url", "", "Prometheus base URL for /v1/promql; empty means not configured")
		promTok   = flag.String("prometheus-token-file", "", "file holding a bearer token sent on /v1/promql upstream requests (Grafana's datasource proxy needs one); never logged")
	)
	flag.Parse()

	store := NewStore(*configDir)
	if _, err := store.EnsureToken(); err != nil {
		log.Fatalf("token: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	sampler := NewSampler(*interval, expandHome(*kubeCfg), *kubeCtx)
	go sampler.Run(ctx)

	addrs := []string{*listen}
	if *tailscale {
		if ip, ok := tailscaleIPv4(); ok {
			_, port, _ := net.SplitHostPort(*listen)
			addrs = append(addrs, net.JoinHostPort(ip, port))
		} else {
			log.Printf("no Tailscale IPv4 found; listening on %s only", *listen)
		}
	}

	srv := &http.Server{
		Handler:           newMux(sampler, store, *promURL, readTokenFile(expandHome(*promTok))),
		ReadHeaderTimeout: 5 * time.Second,
	}
	errs := make(chan error, len(addrs))
	for _, a := range addrs {
		ln, err := net.Listen("tcp", a)
		if err != nil {
			log.Fatalf("listen %s: %v", a, err)
		}
		log.Printf("serving on http://%s (v%s); act endpoints need a paired token", a, version)
		go func() { errs <- srv.Serve(ln) }()
	}

	select {
	case <-ctx.Done():
		log.Print("shutting down")
	case err := <-errs:
		if !errors.Is(err, http.ErrServerClosed) {
			log.Printf("serve: %v", err)
		}
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
}

// tailscaleIPv4 finds this machine's address in 100.64.0.0/10 -- the CGNAT
// range Tailscale assigns from -- by looking at the interfaces directly.
// That avoids depending on the tailscale CLI being on PATH, and it is the
// same address the phone will dial. Nothing else on a normal Mac uses that
// range, so a hit is unambiguous.
func tailscaleIPv4() (string, bool) {
	_, cgnat, _ := net.ParseCIDR("100.64.0.0/10")
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", false
	}
	for _, ifc := range ifaces {
		addrs, err := ifc.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			ipn, ok := a.(*net.IPNet)
			if !ok {
				continue
			}
			ip4 := ipn.IP.To4()
			if ip4 != nil && cgnat.Contains(ip4) {
				return ip4.String(), true
			}
		}
	}
	return "", false
}

// subcommand runs the non-server verbs. Both touch only the config
// directory: neither needs the agent stopped, and a running server picks up
// what they write on its next request because it re-reads those files every
// time rather than caching them at start.
func subcommand(name string, args []string) error {
	fs := flag.NewFlagSet(name, flag.ExitOnError)
	configDir := fs.String("config-dir", "", "where the token and pairing live (default ~/.config/vitruvian-remote-agent)")

	switch name {
	case "pair":
		if err := fs.Parse(args); err != nil {
			return err
		}
		if fs.NArg() != 1 {
			return errors.New("usage: vitruvian-remote-agent pair <the six-digit code the phone is showing>")
		}
		store := NewStore(*configDir)
		if _, err := store.EnsureToken(); err != nil {
			return err
		}
		if err := store.WritePairing(fs.Arg(0)); err != nil {
			return err
		}
		fmt.Printf("pairing open for %s: the phone showing %s may now claim a token.\n", pairTTL, fs.Arg(0))
		fmt.Println("Nothing else to do -- a running agent picks this up without a restart.")
		return nil

	case "token":
		rotate := fs.Bool("rotate", false, "issue a new token, which un-pairs every phone")
		if err := fs.Parse(args); err != nil {
			return err
		}
		store := NewStore(*configDir)
		if *rotate {
			tok, err := store.RotateToken()
			if err != nil {
				return err
			}
			fmt.Println(tok)
			fmt.Fprintln(os.Stderr, "every previously paired phone must pair again.")
			return nil
		}
		tok, err := store.EnsureToken()
		if err != nil {
			return err
		}
		fmt.Println(tok)
		return nil

	default:
		return fmt.Errorf("unknown command %q (want pair or token)", name)
	}
}

// usage is printed by -h; kept next to main so the flags and the text cannot
// drift apart unnoticed.
func init() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "vitruvian-remote-agent v%s -- the Mac half of Vitruvian Remote\n\n", version)
		fmt.Fprint(os.Stderr, strings.TrimSpace(`
Reading (metrics, host, processes, vms, containers, k8s, audio, sessions,
promql, healthz) needs no auth. Acting (exec, clipboard, audio, power) needs
a bearer token, which only pairing issues.

Commands:
  pair <code>      open a five-minute window for the phone showing <code>
  token [--rotate] print the token, or issue a new one and un-pair everything

Flags:
`)+"\n")
		flag.PrintDefaults()
		fmt.Fprintln(os.Stderr, strings.TrimSpace(`
Install as a login item with:  bazel run //mobile/android/remote/macagent:install
Pair a phone with:            bazel run //mobile/android/remote/macagent:pair -- 482917
`))
	}
}

// expandHome turns a leading ~ into $HOME. launchd passes ProgramArguments
// through no shell, so a path the user typed as ~/.kube/cluster.yaml arrives
// here literally and would silently not exist.
func expandHome(p string) string {
	if p == "~" || strings.HasPrefix(p, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return home + p[1:]
		}
	}
	return p
}

// readTokenFile reads a bearer token once at start. Empty path means none.
// The value is never logged; a missing or unreadable file is fatal rather
// than a silent downgrade to unauthenticated, which would only show up later
// as a 401 the phone could not explain.
func readTokenFile(p string) string {
	if p == "" {
		return ""
	}
	b, err := os.ReadFile(p)
	if err != nil {
		log.Fatalf("prometheus-token-file: %v", err)
	}
	return strings.TrimSpace(string(b))
}

// extendPath adds the places user-installed tools live. launchd starts a
// LaunchAgent with PATH=/usr/bin:/bin:/usr/sbin:/sbin, so kubectl, limactl
// and docker -- all Homebrew on a normal Mac -- were "not installed" under
// launchd while the very same binary found them from a terminal. Prepended,
// not appended, so a Homebrew tool shadows a stale /usr/bin one the way it
// does in the user's own shell.
func extendPath() {
	home, _ := os.UserHomeDir()
	extra := []string{"/opt/homebrew/bin", "/usr/local/bin", filepath.Join(home, ".local", "bin"), filepath.Join(home, "bin")}
	cur := os.Getenv("PATH")
	have := map[string]bool{}
	for _, p := range strings.Split(cur, ":") {
		have[p] = true
	}
	var add []string
	for _, p := range extra {
		if p != "" && !have[p] {
			if fi, err := os.Stat(p); err == nil && fi.IsDir() {
				add = append(add, p)
			}
		}
	}
	if len(add) > 0 {
		_ = os.Setenv("PATH", strings.Join(append(add, cur), ":"))
	}
}
