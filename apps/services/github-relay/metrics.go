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
	"fmt"
	"io"
	"sort"
	"strings"
	"sync"
)

// Metrics is a minimal Prometheus text-format registry: a handful of
// counters with one bounded label each. Hand-rolled so the relay stays on
// the standard library (no client_golang in the repo's Go modules).
type Metrics struct {
	mu       sync.Mutex
	counters map[string]map[string]float64 // name -> label value -> count
	help     map[string]string
	label    map[string]string
	gauges   map[string]func() float64
}

// Metric names. Labels are always from a fixed set, never user input.
const (
	mWebhookEvents    = "github_relay_webhook_events_total"
	mWebhookRejected  = "github_relay_webhook_rejected_total"
	mEventsSent       = "github_relay_events_sent_total"
	mReplays          = "github_relay_replays_total"
	mReplayedEvents   = "github_relay_replayed_events_total"
	mResyncs          = "github_relay_resyncs_total"
	mStreamsDropped   = "github_relay_streams_dropped_total"
	mExchangeFailures = "github_relay_auth_exchange_failures_total"
	mExchanges        = "github_relay_auth_exchanges_total"
	mGitHubErrors     = "github_relay_github_api_errors_total"
)

// NewMetrics declares every series up front so a zero shows as 0, not as a
// missing series (absent() alerts and rate() both need the series to exist).
func NewMetrics(subscribers func() float64) *Metrics {
	m := &Metrics{
		counters: map[string]map[string]float64{},
		help:     map[string]string{},
		label:    map[string]string{},
		gauges:   map[string]func() float64{},
	}
	kinds := make([]string, 0, len(supportedKinds)+2)
	for k := range supportedKinds {
		kinds = append(kinds, k)
	}
	kinds = append(kinds, "ping", "ignored")
	m.declare(mWebhookEvents, "Webhook deliveries accepted, by event kind.", "kind", kinds...)
	m.declare(mWebhookRejected, "Webhook deliveries rejected, by reason.", "reason", "missing_signature", "bad_signature", "bad_payload", "too_large")
	m.declare(mEventsSent, "Events written to SSE streams (live and replayed).", "", "")
	m.declare(mReplays, "Reconnects served from the ring buffer.", "", "")
	m.declare(mReplayedEvents, "Events sent as part of a replay.", "", "")
	m.declare(mResyncs, "Reconnects told to resync (Last-Event-ID older than the buffer).", "", "")
	m.declare(mStreamsDropped, "Streams closed because the client fell behind.", "", "")
	m.declare(mExchanges, "Successful OAuth code exchanges.", "", "")
	m.declare(mExchangeFailures, "Failed OAuth code exchanges, by reason.", "reason", "bad_request", "state_mismatch", "not_configured", "github_error", "github_rejected")
	m.declare(mGitHubErrors, "GitHub API calls that failed (network or 5xx), by call.", "call", "user", "repo", "exchange", "revoke")
	m.gauges["github_relay_subscribers"] = subscribers
	m.help["github_relay_subscribers"] = "Open SSE streams."
	return m
}

func (m *Metrics) declare(name, help, label string, values ...string) {
	m.help[name] = help
	m.label[name] = label
	m.counters[name] = map[string]float64{}
	for _, v := range values {
		m.counters[name][v] = 0
	}
}

// Inc adds one to name{label=value}; value is "" for unlabelled counters.
func (m *Metrics) Inc(name, value string) { m.Add(name, value, 1) }

// Add adds n to name{label=value}.
func (m *Metrics) Add(name, value string, n float64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	c, ok := m.counters[name]
	if !ok {
		return
	}
	c[value] += n
}

// Get returns a counter's value (tests).
func (m *Metrics) Get(name, value string) float64 {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.counters[name][value]
}

// Render writes the Prometheus text exposition format.
func (m *Metrics) Render(w io.Writer) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var b strings.Builder
	names := make([]string, 0, len(m.counters))
	for n := range m.counters {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		fmt.Fprintf(&b, "# HELP %s %s\n# TYPE %s counter\n", n, m.help[n], n)
		vals := make([]string, 0, len(m.counters[n]))
		for v := range m.counters[n] {
			vals = append(vals, v)
		}
		sort.Strings(vals)
		for _, v := range vals {
			if m.label[n] == "" {
				fmt.Fprintf(&b, "%s %g\n", n, m.counters[n][v])
			} else {
				fmt.Fprintf(&b, "%s{%s=%q} %g\n", n, m.label[n], v, m.counters[n][v])
			}
		}
	}
	for n, f := range m.gauges {
		fmt.Fprintf(&b, "# HELP %s %s\n# TYPE %s gauge\n%s %g\n", n, m.help[n], n, n, f())
	}
	_, _ = io.WriteString(w, b.String())
}
