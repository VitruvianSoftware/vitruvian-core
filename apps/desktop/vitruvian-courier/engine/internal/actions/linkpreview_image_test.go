// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/media"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

// previewActions is Actions over a real store and media store and no network.
func previewActions(t *testing.T) *Actions {
	t.Helper()
	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return New(nil, s, &media.Store{Dir: filepath.Join(dir, "media")})
}

func solidPNG(w, h int) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{R: 40, G: 120, B: 200, A: 255})
		}
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

// pageServer is one fixture site over TLS: its page is html (with %[1]s for the server's address), /og.png is a 16x12
// picture, /big.png is over 2 MiB, /not-a-picture is text.
type pageServer struct {
	url    string
	pages  atomic.Int32
	images atomic.Int32
}

func servePage(t *testing.T, a *Actions, html string) *pageServer {
	t.Helper()
	ps := &pageServer{}
	srv := httptest.NewTLSServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/og.png":
			ps.images.Add(1)
			rw.Header().Set("Content-Type", "image/png")
			_, _ = rw.Write(solidPNG(16, 12))
		case "/big.png":
			ps.images.Add(1)
			rw.Header().Set("Content-Type", "image/png")
			_, _ = rw.Write(append(solidPNG(16, 12), bytes.Repeat([]byte{0}, maxLinkPreviewImageBytes)...))
		case "/not-a-picture":
			ps.images.Add(1)
			rw.Header().Set("Content-Type", "image/png")
			_, _ = rw.Write([]byte("this is not a picture"))
		default:
			ps.pages.Add(1)
			rw.Header().Set("Content-Type", "text/html; charset=utf-8")
			_, _ = fmt.Fprintf(rw, html, ps.url)
		}
	}))
	t.Cleanup(srv.Close)
	ps.url = srv.URL
	a.SetLinkPreviewHTTPClient(srv.Client())
	return ps
}

func TestPreviewImageForURLReadsTheFixturePages(t *testing.T) {
	ctx := context.Background()
	head := func(meta string) string {
		return `<!doctype html><html><head><meta property="og:title" content="A story">` + meta + `</head><body>x</body></html>`
	}
	filler := strings.Repeat("<!-- padding -->", 20000) // 320 KB: past the 256 KiB read limit
	cases := []struct {
		name       string
		html       string
		found      bool
		wantImages int32
	}{
		{"absolute og:image", head(`<meta property="og:image" content="%[1]s/og.png">`), true, 1},
		{"relative og:image", head(`<meta property="og:image" content="/og.png">`), true, 1},
		{"name= instead of property=", head(`<meta name="og:image" content="%[1]s/og.png">`), true, 1},
		{"no og:image", head(``), false, 0},
		{"og:image over http is not fetched", head(`<meta property="og:image" content="http://127.0.0.1/og.png">`), false, 0},
		{"og:image that is not a picture", head(`<meta property="og:image" content="%[1]s/not-a-picture">`), false, 1},
		{"og:image over 2 MiB", head(`<meta property="og:image" content="%[1]s/big.png">`), false, 1},
		{"og:image past the 256 KiB page limit", `<html><head><meta property="og:title" content="A story">` + filler +
			`<meta property="og:image" content="%[1]s/og.png"></head></html>`, false, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			a := previewActions(t)
			ps := servePage(t, a, tc.html)
			got, err := a.PreviewImageForURL(ctx, ps.url+"/story")
			require.NoError(t, err)
			require.Equal(t, tc.wantImages, ps.images.Load(), "requests for the picture")
			if !tc.found {
				require.Empty(t, got.ImagePath)
				return
			}
			require.NotEmpty(t, got.ImagePath)
			require.FileExists(t, got.ImagePath)
			require.Equal(t, 16, got.ImageWidth)
			require.Equal(t, 12, got.ImageHeight)
			require.NotEmpty(t, got.BlurHash)
		})
	}
}

func TestPreviewImageIsFetchedOncePerAddress(t *testing.T) {
	ctx := context.Background()
	a := previewActions(t)
	ps := servePage(t, a, `<meta property="og:title" content="A story"><meta property="og:image" content="%[1]s/og.png">`)

	first, err := a.PreviewImageForURL(ctx, ps.url+"/story")
	require.NoError(t, err)
	require.NotEmpty(t, first.ImagePath)
	require.Equal(t, int32(1), ps.pages.Load())
	require.Equal(t, int32(1), ps.images.Load())

	// Scrolling past it again, with the fragment and the case of the host different: no request at all.
	for _, again := range []string{ps.url + "/story", ps.url + "/story#comments"} {
		got, err := a.PreviewImageForURL(ctx, again)
		require.NoError(t, err)
		require.Equal(t, first, got)
	}
	require.Equal(t, int32(1), ps.pages.Load(), "the page was asked for once")
	require.Equal(t, int32(1), ps.images.Load(), "the picture was asked for once")

	// Calls that arrive together share one look-up.
	b := previewActions(t)
	pb := servePage(t, b, `<meta property="og:title" content="A story"><meta property="og:image" content="%[1]s/og.png">`)
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			got, err := b.PreviewImageForURL(ctx, pb.url+"/story")
			require.NoError(t, err)
			require.NotEmpty(t, got.ImagePath)
		}()
	}
	wg.Wait()
	require.Equal(t, int32(1), pb.pages.Load(), "twelve callers, one page request")
}

func TestPreviewImageRemembersNoPictureForAWeekAndAFailureForAnHour(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 11, 21, 12, 0, 0, 0, time.UTC)
	previewImageNow = func() time.Time { return now }
	t.Cleanup(func() { previewImageNow = time.Now })

	// A page with no picture: believed for a week.
	a := previewActions(t)
	none := servePage(t, a, `<meta property="og:title" content="A story">`)
	got, err := a.PreviewImageForURL(ctx, none.url+"/story")
	require.NoError(t, err)
	require.Empty(t, got.ImagePath)
	now = now.Add(6 * 24 * time.Hour)
	_, err = a.PreviewImageForURL(ctx, none.url+"/story")
	require.NoError(t, err)
	require.Equal(t, int32(1), none.pages.Load(), "within the week it is not asked again")
	now = now.Add(2 * 24 * time.Hour)
	_, err = a.PreviewImageForURL(ctx, none.url+"/story")
	require.NoError(t, err)
	require.Equal(t, int32(2), none.pages.Load(), "after the week it is")

	// A page that did not answer (no Open Graph tags at all): another go after an hour, not before.
	b := previewActions(t)
	bare := servePage(t, b, `<p>just text</p>`)
	_, err = b.PreviewImageForURL(ctx, bare.url+"/story")
	require.NoError(t, err)
	now = now.Add(59 * time.Minute)
	_, err = b.PreviewImageForURL(ctx, bare.url+"/story")
	require.NoError(t, err)
	require.Equal(t, int32(1), bare.pages.Load(), "within the hour it is not asked again")
	now = now.Add(2 * time.Minute)
	_, err = b.PreviewImageForURL(ctx, bare.url+"/story")
	require.NoError(t, err)
	require.Equal(t, int32(2), bare.pages.Load(), "after the hour it is")
}

func TestPreviewImageIsFetchedAgainWhenItsFileWasCleanedUp(t *testing.T) {
	ctx := context.Background()
	a := previewActions(t)
	ps := servePage(t, a, `<meta property="og:title" content="A story"><meta property="og:image" content="%[1]s/og.png">`)
	first, err := a.PreviewImageForURL(ctx, ps.url+"/story")
	require.NoError(t, err)
	require.NoError(t, os.Remove(first.ImagePath))
	second, err := a.PreviewImageForURL(ctx, ps.url+"/story")
	require.NoError(t, err)
	require.FileExists(t, second.ImagePath)
	require.Equal(t, int32(2), ps.pages.Load())
}

func TestPreviewImageRefusesAddressesThatAreNotHTTPS(t *testing.T) {
	ctx := context.Background()
	a := previewActions(t)
	ps := servePage(t, a, `<meta property="og:title" content="A story">`)
	for _, bad := range []string{
		"", "   ", "http://example.com/story", "ftp://example.com/story", "file:///etc/passwd", "https://", "https:///story",
		"https://user:pass@example.com/story", "example.com/story", "https://example.com/" + strings.Repeat("a", 2100),
	} {
		_, err := a.PreviewImageForURL(ctx, bad)
		require.ErrorIs(t, err, ErrBadPreviewURL, "%q", bad)
	}
	require.Equal(t, int32(0), ps.pages.Load())
}

// The fetch is the link-preview fetcher's, guard and all: an address that resolves to a private or tailnet address is
// never connected to, and the refusal is remembered like any failed look-up.
func TestPreviewImageKeepsTheLinkPreviewAddressGuard(t *testing.T) {
	ctx := context.Background()
	var hits atomic.Int32
	target := httptest.NewTLSServer(http.HandlerFunc(func(rw http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		_, _ = rw.Write([]byte(`<meta property="og:title" content="Secret">`))
	}))
	defer target.Close()

	a := previewActions(t)
	for i, blocked := range []string{"127.0.0.1", "10.0.0.1", "100.64.0.1", "169.254.1.1", "fe80::1", "fc00::1"} {
		a.SetLinkPreviewResolver(func(_ context.Context, _ string) ([]net.IPAddr, error) {
			return []net.IPAddr{{IP: net.ParseIP(blocked)}}, nil
		})
		got, err := a.PreviewImageForURL(ctx, fmt.Sprintf("https://internal.example.com/story-%d", i))
		require.NoError(t, err)
		require.Empty(t, got.ImagePath, blocked)
	}
	require.Equal(t, int32(0), hits.Load())
}
