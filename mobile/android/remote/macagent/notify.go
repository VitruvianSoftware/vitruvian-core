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
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
)

// The push half of v1.2.
//
// The rest of this agent answers questions the phone asks. This is the one
// direction that goes the other way, and it exists for a specific failure:
// Claude Code stops at a permission prompt and nobody notices for an hour,
// because the person is not looking at the Mac. A notification is the only
// thing that fixes that, and a phone cannot poll for it while asleep.
//
// ntfy rather than APNs because it needs no Apple developer account, no
// server-side push certificate and no per-app registration: a topic is a URL
// and the ntfy app subscribes to it. The trade is that anyone who learns the
// topic name can read it, which is why the topic is configuration and the
// token is a file.

// notifyDebounce is how long the same key stays quiet after firing. Thirty
// seconds is the difference between "Claude is waiting" and thirty copies of
// it while the sampler re-reads the same unchanged transcript.
const notifyDebounce = 30 * time.Second

// Notifier publishes to an ntfy topic. The zero value is a working
// no-op: nothing is configured, Publish returns quietly, and every caller can
// stay unconditional rather than nil-checking at five call sites.
type Notifier struct {
	url   string
	topic string
	// token is a bearer for ntfy's own auth. It is never logged, never
	// echoed in a response and never included in an error: a publish failure
	// says "401 from ntfy", not what was sent.
	token string

	client *http.Client

	mu   sync.Mutex
	sent map[string]time.Time
}

// NewNotifier builds one. An empty url or topic means "not configured", which
// is a state the agent reports at /healthz rather than an error it fails on:
// notifications are an addition, and an agent without them is still an agent.
func NewNotifier(url, topic, token string) *Notifier {
	return &Notifier{
		url:   strings.TrimRight(url, "/"),
		topic: strings.TrimSpace(topic),
		token: strings.TrimSpace(token),
		// A timeout of its own. http.DefaultClient has none, and an ntfy
		// that accepts the connection then stalls would hold a sampler
		// goroutine for as long as the TCP stack allows.
		client: &http.Client{Timeout: 10 * time.Second},
		sent:   map[string]time.Time{},
	}
}

// Configured says whether publishing can work at all.
func (n *Notifier) Configured() bool {
	return n != nil && n.url != "" && n.topic != ""
}

// Topic is what /healthz reports. Safe to expose -- it is not a credential,
// and a person debugging "why no notifications" needs to see which topic the
// agent is actually publishing to.
func (n *Notifier) Topic() string {
	if n == nil {
		return ""
	}
	return n.topic
}

// errNotifyNotConfigured is what POST /v1/notify/test answers with, and it
// names the flags rather than saying "unavailable": the fix is a restart with
// two arguments, and a phone that says so saves someone a log hunt.
var errNotifyNotConfigured = errors.New("notifications are not configured (--ntfy-url and --ntfy-topic)")

// Publish sends one notification, unless the same key fired within
// notifyDebounce. It returns whether it sent and why not.
//
// Debounce is per KEY, not global: "Claude is waiting" for one session must
// not suppress a PR going red in the same minute. The key is the caller's
// (`claude:<session>:permission`, `pr:<repo>#<n>:green`) and its shape is in
// the contract, because the phone's own notification grouping uses the same
// idea.
func (n *Notifier) Publish(ctx context.Context, key, title, body, priority, tags, click string) error {
	if !n.Configured() {
		return errNotifyNotConfigured
	}
	if !n.claim(key, time.Now()) {
		return nil
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, n.url+"/"+n.topic, strings.NewReader(body))
	if err != nil {
		return err
	}
	// The body is the message; everything else ntfy takes as a header. Set
	// only when non-empty: ntfy treats an empty Priority as a parse error
	// rather than as a default.
	req.Header.Set("Content-Type", "text/plain; charset=utf-8")
	if title != "" {
		req.Header.Set("Title", title)
	}
	if priority != "" {
		req.Header.Set("Priority", priority)
	}
	if tags != "" {
		req.Header.Set("Tags", tags)
	}
	if click != "" {
		// A vitruvian-remote://<screen> link. Tapping the notification opens
		// the phone on the screen the notification is about, which is the
		// whole difference between a useful push and an interruption.
		req.Header.Set("Click", click)
	}
	if n.token != "" {
		req.Header.Set("Authorization", "Bearer "+n.token)
	}
	resp, err := n.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	// Drained and bounded so the connection can be reused, and so an ntfy
	// answering with a megabyte of HTML cannot be quoted back into a log.
	slurp, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
	if resp.StatusCode >= 300 {
		return fmt.Errorf("ntfy: %s: %s", resp.Status, firstLine(string(slurp)))
	}
	return nil
}

// claim is the debounce, and it records the send BEFORE the HTTP call rather
// than after. A publish that takes nine seconds and fails must not let nine
// more attempts through behind it; being quiet for thirty seconds after a
// failure is the cheaper mistake.
func (n *Notifier) claim(key string, now time.Time) bool {
	n.mu.Lock()
	defer n.mu.Unlock()
	if last, ok := n.sent[key]; ok && now.Sub(last) < notifyDebounce {
		return false
	}
	n.sent[key] = now
	// Bounded: keys carry session ids and PR numbers, so the map would grow
	// without limit over the weeks a login item stays up. Anything older
	// than the debounce window can no longer suppress anything.
	for k, t := range n.sent {
		if now.Sub(t) > 10*notifyDebounce {
			delete(n.sent, k)
		}
	}
	return true
}

// notify is the fire-and-forget wrapper the sampler uses. A failed
// notification is logged and dropped: a sampler that stalled because ntfy
// was down would take the metrics with it, and the metrics are the point.
func (n *Notifier) notify(ctx context.Context, key, title, body, priority, tags, click string) {
	if !n.Configured() {
		return
	}
	if err := n.Publish(ctx, key, title, body, priority, tags, click); err != nil {
		log.Printf("notify %s: %v", key, err)
	}
}
