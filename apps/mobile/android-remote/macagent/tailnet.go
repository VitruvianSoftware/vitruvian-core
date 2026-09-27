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

package main

import (
	"context"
	"log"
	"net"
	"sync"
	"time"
)

// tailnetWatcher keeps the agent listening on this Mac's Tailscale address,
// whenever there is one.
//
// It used to be looked up once, at start. A LaunchAgent starts at login,
// often before Tailscale has brought its interface up, and the agent then
// logged "no Tailscale IPv4 found" and served loopback only until someone
// restarted it: the phone, the /pair page and every pairing QR code pointed
// at an address nothing was listening on (seen 2026-09-27 after a reboot).
// Now the address is re-checked every few seconds, and the listener follows
// it -- opened when it appears, moved when it changes, closed when it goes.
type tailnetWatcher struct {
	port   string
	lookup func() (string, bool)
	listen func(addr string) (net.Listener, error)
	serve  func(net.Listener)

	mu      sync.Mutex
	ip      string
	ln      net.Listener
	lastErr string
}

// tick reconciles once: the listener should be on the current address, or
// absent when there is none. Safe to call repeatedly.
func (w *tailnetWatcher) tick() {
	w.mu.Lock()
	defer w.mu.Unlock()
	ip, ok := w.lookup()
	if !ok {
		ip = ""
	}
	if ip == w.ip && (ip == "" || w.ln != nil) {
		return
	}
	if w.ln != nil {
		log.Printf("Tailscale address changed from %s; closing that listener", w.ip)
		_ = w.ln.Close()
		w.ln = nil
	}
	w.ip = ip
	if ip == "" {
		return
	}
	addr := net.JoinHostPort(ip, w.port)
	ln, err := w.listen(addr)
	if err != nil {
		// Just after the interface appears the address can be briefly
		// unbindable; the next tick tries again. Log each distinct error once.
		if msg := err.Error(); msg != w.lastErr {
			log.Printf("listen %s: %v (retrying)", addr, err)
			w.lastErr = msg
		}
		w.ip = "" // not listening yet, so the next tick retries
		return
	}
	w.lastErr = ""
	w.ln = ln
	log.Printf("serving on http://%s (v%s); act endpoints need a paired token", addr, version)
	go w.serve(ln)
}

// current is the address being served, or "" when there is none.
func (w *tailnetWatcher) current() string {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.ln == nil {
		return ""
	}
	return w.ip
}

func (w *tailnetWatcher) run(ctx context.Context, every time.Duration) {
	w.tick()
	if w.current() == "" {
		log.Printf("no Tailscale IPv4 yet; watching for one every %s", every)
	}
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			w.tick()
		}
	}
}
