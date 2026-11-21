// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"fmt"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/actions"
)

// servePreviewPage serves one article page over TLS for linkPreview.image to fetch (the production fetcher is pointed
// at it, its address guard left as it is for every other address), with an og:image when withImage, and returns the
// page's address.
func servePreviewPage(t *testing.T, a *actions.Actions, withImage bool) string {
	t.Helper()
	var base string
	srv := httptest.NewTLSServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/og.png" {
			rw.Header().Set("Content-Type", "image/png")
			img := image.NewRGBA(image.Rect(0, 0, 24, 12))
			for y := 0; y < 12; y++ {
				for x := 0; x < 24; x++ {
					img.Set(x, y, color.RGBA{R: 200, G: 60, B: 40, A: 255})
				}
			}
			_ = png.Encode(rw, img)
			return
		}
		rw.Header().Set("Content-Type", "text/html; charset=utf-8")
		pic := ""
		if withImage {
			pic = fmt.Sprintf(`<meta property="og:image" content="%s/og.png">`, base)
		}
		_, _ = fmt.Fprintf(rw, `<!doctype html><html><head>
			<meta property="og:title" content="A story">
			<meta property="og:site_name" content="Example News">
			%s
		</head><body>Hello</body></html>`, pic)
	}))
	t.Cleanup(srv.Close)
	base = srv.URL
	a.SetLinkPreviewHTTPClient(srv.Client())
	return srv.URL + "/story"
}
