// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/event"
)

// dripServer answers a page and a picture whose bodies never finish: the headers go out at once, then one byte every
// 20 ms, for as long as the client listens. dripPage and dripImage say which of the two do.
func dripServer(t *testing.T, a *Actions, dripPage, dripImage bool) string {
	t.Helper()
	var base string
	srv := httptest.NewTLSServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		drip := func(contentType, prefix string) {
			rw.Header().Set("Content-Type", contentType)
			rw.WriteHeader(http.StatusOK)
			_, _ = rw.Write([]byte(prefix))
			rw.(http.Flusher).Flush()
			for {
				select {
				case <-r.Context().Done():
					return
				case <-time.After(20 * time.Millisecond):
					if _, err := rw.Write([]byte(" ")); err != nil {
						return
					}
					rw.(http.Flusher).Flush()
				}
			}
		}
		if r.URL.Path == "/og.png" {
			if dripImage {
				drip("image/png", "\x89PNG")
				return
			}
			rw.Header().Set("Content-Type", "image/png")
			_, _ = rw.Write(solidPNG(16, 12))
			return
		}
		head := fmt.Sprintf(`<meta property="og:title" content="A story"><meta property="og:image" content="%s/og.png">`, base)
		if dripPage {
			drip("text/html", head[:20])
			return
		}
		rw.Header().Set("Content-Type", "text/html")
		_, _ = rw.Write([]byte(head))
	}))
	t.Cleanup(srv.Close)
	base = srv.URL
	a.SetLinkPreviewHTTPClient(srv.Client())
	return base
}

func shortDeadlines(t *testing.T) {
	t.Helper()
	oldPage, oldImage := linkPreviewTimeout, linkPreviewImageTimeout
	linkPreviewTimeout, linkPreviewImageTimeout = 300*time.Millisecond, 300*time.Millisecond
	t.Cleanup(func() { linkPreviewTimeout, linkPreviewImageTimeout = oldPage, oldImage })
}

// Every request path has a deadline that covers the body, not only the headers: a server that sends its headers and
// then drips the body one byte at a time cannot hold a look-up (or a message being sent) past it.
func TestLinkPreviewRequestsCannotBeHeldByASlowDrippedBody(t *testing.T) {
	shortDeadlines(t)
	const bound = 3 * time.Second
	for _, tc := range []struct {
		name                string
		dripPage, dripImage bool
	}{{"page body drips", true, false}, {"picture body drips", false, true}} {
		t.Run("card picture: "+tc.name, func(t *testing.T) {
			a := previewActions(t)
			base := dripServer(t, a, tc.dripPage, tc.dripImage)
			start := time.Now()
			got, err := a.PreviewImageForURL(context.Background(), base+"/story")
			require.NoError(t, err)
			require.Empty(t, got.ImagePath)
			require.Less(t, time.Since(start), bound, "returned by the deadline")
		})
		t.Run("outgoing preview: "+tc.name, func(t *testing.T) {
			a := previewActions(t)
			base := dripServer(t, a, tc.dripPage, tc.dripImage)
			off := false
			c := &event.MessageEventContent{Body: base + "/story"}
			start := time.Now()
			a.applyLinkPreviews(context.Background(), c, &off)
			require.Less(t, time.Since(start), bound, "returned by the deadline")
		})
	}
}
