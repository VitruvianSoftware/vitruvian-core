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

package cmd

import (
	"net/http"
	"os"
	"time"

	"github.com/getsentry/sentry-go"
)

const defaultSentryDSN = "https://f5f0bc21a4b8f3f1c63fb5f684e070ca@sentry-ingest.ipv1337.dev/18"

func resolveSentryDSN() string {
	if dsn := os.Getenv("SENTRY_DSN"); dsn != "" {
		return dsn
	}
	return defaultSentryDSN
}

// initSentry initializes Sentry error tracking in fail-open, non-blocking mode.
// Initialization errors are intentionally ignored so CLI execution never fails
// or prints noisy output when Sentry is misconfigured or unreachable.
func initSentry(dsn string) {
	if dsn == "" {
		dsn = resolveSentryDSN()
	}
	_ = sentry.Init(sentry.ClientOptions{
		Dsn:     dsn,
		Release: version,
		HTTPClient: &http.Client{
			Timeout: 1 * time.Second,
		},
	})
}
