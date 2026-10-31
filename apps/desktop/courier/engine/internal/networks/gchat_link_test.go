// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

//go:build darwin

package networks

import (
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/gchat"
)

func TestGChatLinksGChatFFI(t *testing.T) {
	require.NoError(t, gchat.LinkCheck())
}

func TestProductionLibraryRejectsLoopbackAndNeverAttachesCookies(t *testing.T) {
	var hits atomic.Int32
	var receivedCookie atomic.Value
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		receivedCookie.Store(r.Header.Get("Cookie"))
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	_, err := gchat.ValidateSession(gchat.SessionConfig{
		CookieMap: map[string]string{
			"COMPASS": "dynamite-ui=synthetic",
			"OSID":    "synthetic_osid",
			"SID":     "synthetic_sid",
			"HSID":    "synthetic_hsid",
			"SSID":    "synthetic_ssid",
		},
		BaseURL: srv.URL,
	})
	require.Error(t, err, "production library must reject loopback")
	require.Contains(t, err.Error(), "blocked by network guard")
	require.Zero(t, hits.Load(), "production library must never connect or send cookies to loopback")
	require.Nil(t, receivedCookie.Load(), "production library must never attach cookies to loopback")
}
