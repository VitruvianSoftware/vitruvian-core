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

// Command macagent is the Mac half of Vitruvian Remote: a small read-only
// daemon that serves the machine's vital signs over HTTP so the phone can
// show real numbers instead of MockHost.
//
// Read-only is the design, not a limitation of this version. Bluetooth HID
// already gives the phone control of the Mac with nothing installed; what it
// cannot do is ask a question. This answers questions. It runs no commands
// on a client's behalf, binds only to loopback and the Tailscale interface,
// and needs no root. Kill it and the app falls back to simulated data.
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
	"strings"
	"syscall"
	"time"
)

const version = "0.1.0"

// defaultPort is arbitrary and unregistered. Chosen to not collide with
// anything devx or the homelab already listens on.
const defaultPort = "7411"

func main() {
	var (
		listen    = flag.String("listen", "127.0.0.1:"+defaultPort, "address to listen on")
		tailscale = flag.Bool("tailscale", true, "also listen on this machine's Tailscale IPv4, if it has one")
		interval  = flag.Duration("interval", 2*time.Second, "how often to refresh the fast readings")
	)
	flag.Parse()
	log.SetPrefix("[vitruvian-remote-agent] ")
	log.SetFlags(log.Ltime)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	sampler := NewSampler(*interval)
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
		Handler:           newMux(sampler),
		ReadHeaderTimeout: 5 * time.Second,
	}
	errs := make(chan error, len(addrs))
	for _, a := range addrs {
		ln, err := net.Listen("tcp", a)
		if err != nil {
			log.Fatalf("listen %s: %v", a, err)
		}
		log.Printf("serving read-only metrics on http://%s (v%s)", a, version)
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

// usage is printed by -h; kept next to main so the flags and the text cannot
// drift apart unnoticed.
func init() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "vitruvian-remote-agent v%s -- read-only metrics for Vitruvian Remote\n\n", version)
		fmt.Fprintf(os.Stderr, "Serves GET /v1/metrics, GET /v1/host and GET /healthz. Runs no commands for clients.\n\n")
		flag.PrintDefaults()
		fmt.Fprintln(os.Stderr, strings.TrimSpace(`
Install as a login item with:  bazel run //mobile/android/remote/macagent:install
`))
	}
}
