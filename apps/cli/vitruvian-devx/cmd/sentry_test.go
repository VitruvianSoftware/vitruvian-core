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
	"errors"
	"fmt"
	"net"
	"testing"
	"time"

	"github.com/getsentry/sentry-go"
)

func TestResolveSentryDSN(t *testing.T) {
	t.Setenv("SENTRY_DSN", "")
	if got := resolveSentryDSN(); got != defaultSentryDSN {
		t.Fatalf("resolveSentryDSN() with empty env = %q, want %q", got, defaultSentryDSN)
	}

	custom := "http://abc@127.0.0.1:9999/18"
	t.Setenv("SENTRY_DSN", custom)
	if got := resolveSentryDSN(); got != custom {
		t.Fatalf("resolveSentryDSN() with env = %q, want %q", got, custom)
	}
}

func TestSentryFailOpenUnreachablePort(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen ephemeral port: %v", err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	_ = ln.Close()

	dsn := fmt.Sprintf("http://abc@127.0.0.1:%d/18", port)

	start := time.Now()
	initSentry(dsn)
	sentry.CaptureException(errors.New("unreachable sentry test error"))
	sentry.Flush(500 * time.Millisecond)
	elapsed := time.Since(start)

	if elapsed >= 2*time.Second {
		t.Fatalf("sentry init + capture + flush took %v, want < 2s", elapsed)
	}
}

func TestSentryInitInvalidDSNNoPanic(t *testing.T) {
	// Must fail open without panicking or returning an error.
	initSentry("://invalid-dsn")
	sentry.CaptureException(errors.New("after invalid dsn"))
	sentry.Flush(50 * time.Millisecond)
}
