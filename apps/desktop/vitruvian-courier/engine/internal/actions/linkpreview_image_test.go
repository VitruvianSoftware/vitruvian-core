// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"hash/crc32"
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
	"maunium.net/go/mautrix/event"

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
		case "/missing.png":
			ps.images.Add(1)
			http.NotFound(rw, r)
		case "/error.png":
			ps.images.Add(1)
			http.Error(rw, "broken", http.StatusInternalServerError)
		case "/bomb.png":
			// 20000 x 20000 pixels claimed by a header of a few dozen bytes.
			ps.images.Add(1)
			rw.Header().Set("Content-Type", "image/png")
			ihdr := binary.BigEndian.AppendUint32(nil, 20000)
			ihdr = binary.BigEndian.AppendUint32(ihdr, 20000)
			ihdr = append(ihdr, 8, 0, 0, 0, 0)
			_, _ = rw.Write(append(append([]byte("\x89PNG\r\n\x1a\n"), testPNGChunk("IHDR", ihdr)...), testPNGChunk("IEND", nil)...))
		case "/slow.png":
			ps.images.Add(1)
			select {
			case <-r.Context().Done():
			case <-time.After(2 * time.Second):
			}
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

func testPNGChunk(kind string, data []byte) []byte {
	out := binary.BigEndian.AppendUint32(nil, uint32(len(data)))
	out = append(out, kind...)
	out = append(out, data...)
	return binary.BigEndian.AppendUint32(out, crc32.ChecksumIEEE(append([]byte(kind), data...)))
}

// Only "the page was read and names no picture" is believed for a week. A picture that did not come (it was not found,
// the server broke, it was too big, was not a picture, claimed an absurd size, or was too slow) is believed for an hour,
// as is a page that did not answer.
func TestPreviewImageFailuresAreRememberedForAnHourNotAWeek(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 11, 21, 12, 0, 0, 0, time.UTC)
	previewImageNow = func() time.Time { return now }
	oldTimeout := linkPreviewImageTimeout
	linkPreviewImageTimeout = 150 * time.Millisecond
	t.Cleanup(func() { previewImageNow = time.Now; linkPreviewImageTimeout = oldTimeout })

	for _, path := range []string{"/missing.png", "/error.png", "/big.png", "/not-a-picture", "/bomb.png", "/slow.png"} {
		t.Run(path, func(t *testing.T) {
			now = time.Date(2026, 11, 21, 12, 0, 0, 0, time.UTC)
			a := previewActions(t)
			ps := servePage(t, a, `<meta property="og:title" content="A story"><meta property="og:image" content="`+path+`">`)
			got, err := a.PreviewImageForURL(ctx, ps.url+"/story")
			require.NoError(t, err)
			require.Empty(t, got.ImagePath)
			require.Equal(t, int32(1), ps.pages.Load())
			now = now.Add(59 * time.Minute)
			_, _ = a.PreviewImageForURL(ctx, ps.url+"/story")
			require.Equal(t, int32(1), ps.pages.Load(), "within the hour it is not asked again")
			now = now.Add(2 * time.Minute)
			_, _ = a.PreviewImageForURL(ctx, ps.url+"/story")
			require.Equal(t, int32(2), ps.pages.Load(), "after the hour it is: a failed picture is not 'no picture for a week'")
		})
	}

	// The one kept for a week: the page was read and names no picture.
	now = time.Date(2026, 11, 21, 12, 0, 0, 0, time.UTC)
	a := previewActions(t)
	ps := servePage(t, a, `<meta property="og:title" content="A story">`)
	_, _ = a.PreviewImageForURL(ctx, ps.url+"/story")
	now = now.Add(6 * 24 * time.Hour)
	_, _ = a.PreviewImageForURL(ctx, ps.url+"/story")
	require.Equal(t, int32(1), ps.pages.Load())
}

// The picture has its own time: a page that took most of its own does not leave the picture none.
func TestPreviewImageHasItsOwnTimeApartFromThePages(t *testing.T) {
	ctx := context.Background()
	oldPage, oldImage := linkPreviewTimeout, linkPreviewImageTimeout
	linkPreviewTimeout, linkPreviewImageTimeout = 500*time.Millisecond, 2*time.Second
	t.Cleanup(func() { linkPreviewTimeout, linkPreviewImageTimeout = oldPage, oldImage })

	a := previewActions(t)
	var base string
	srv := httptest.NewTLSServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		time.Sleep(350 * time.Millisecond) // the page and the picture each take 350 ms: 700 ms in all, over the page's 500 ms
		if r.URL.Path == "/og.png" {
			rw.Header().Set("Content-Type", "image/png")
			_, _ = rw.Write(solidPNG(16, 12))
			return
		}
		rw.Header().Set("Content-Type", "text/html")
		_, _ = fmt.Fprintf(rw, `<meta property="og:title" content="A story"><meta property="og:image" content="%s/og.png">`, base)
	}))
	defer srv.Close()
	base = srv.URL
	a.SetLinkPreviewHTTPClient(srv.Client())
	got, err := a.PreviewImageForURL(ctx, srv.URL+"/story")
	require.NoError(t, err)
	require.NotEmpty(t, got.ImagePath, "the picture got its own time")
}

// The rows kept per address are capped and the expired ones go on each write.
func TestPreviewImageRowsArePrunedOnWrite(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 11, 21, 12, 0, 0, 0, time.UTC)
	previewImageNow = func() time.Time { return now }
	previewImageRowsKept = 3
	t.Cleanup(func() { previewImageNow = time.Now; previewImageRowsKept = store.LinkPreviewImageRowsKept })

	a := previewActions(t)
	var urls []string
	// remembered is how many of the addresses seen so far still have a row.
	remembered := func() int {
		n := 0
		for _, u := range urls {
			canonical, err := canonicalPreviewURL(u)
			require.NoError(t, err)
			sum := sha256.Sum256([]byte(canonical))
			if _, ok, err := a.s.Setting(ctx, previewImageKeyPrefix+hex.EncodeToString(sum[:])); err == nil && ok {
				n++
			}
		}
		return n
	}
	// Five pages with no picture, a minute apart: the cap keeps the newest three.
	for i := 0; i < 5; i++ {
		ps := servePage(t, a, `<meta property="og:title" content="A story">`)
		urls = append(urls, ps.url+"/story")
		_, err := a.PreviewImageForURL(ctx, ps.url+"/story")
		require.NoError(t, err)
		now = now.Add(time.Minute)
	}
	require.Equal(t, 3, remembered(), "only the newest three are kept")

	// A week and a day later one more write drops the expired ones with it.
	now = now.Add(8 * 24 * time.Hour)
	ps := servePage(t, a, `<meta property="og:title" content="A story">`)
	urls = append(urls, ps.url+"/story")
	_, err := a.PreviewImageForURL(ctx, ps.url+"/story")
	require.NoError(t, err)
	require.Equal(t, 1, remembered(), "the expired rows went with the write")
}

// Every fetch closes what it kept idle: ten fetches leave no connection open at the site (a client that keeps
// connections alive, as a test's does, would leave ten), and the production client keeps none to begin with.
func TestLinkPreviewFetchesLeaveNoIdleConnections(t *testing.T) {
	ctx := context.Background()
	var mu sync.Mutex
	open := map[net.Conn]http.ConnState{}
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		rw.Header().Set("Content-Type", "text/html")
		_, _ = rw.Write([]byte(`<meta property="og:title" content="A story">`))
	}))
	srv.Config.ConnState = func(c net.Conn, state http.ConnState) {
		mu.Lock()
		defer mu.Unlock()
		if state == http.StateClosed || state == http.StateHijacked {
			delete(open, c)
			return
		}
		open[c] = state
	}
	srv.StartTLS()
	defer srv.Close()

	a := previewActions(t)
	a.SetLinkPreviewHTTPClient(srv.Client())
	for i := 0; i < 10; i++ {
		require.NotNil(t, a.fetchLinkPreview(ctx, fmt.Sprintf("%s/story-%d", srv.URL, i)))
	}
	require.Eventually(t, func() bool {
		mu.Lock()
		defer mu.Unlock()
		return len(open) == 0
	}, 3*time.Second, 20*time.Millisecond, "no connection is left open at the site")

	// The production client keeps nothing alive, so a client made for each fetch leaves nothing behind.
	b := previewActions(t)
	transport, ok := b.getLinkPreviewClient().Transport.(*http.Transport)
	require.True(t, ok)
	require.True(t, transport.DisableKeepAlives)
}

// A link I send waits for its page and picture together for 3 seconds at most, as before: the picture's separate 5
// seconds belong to a received link card only.
func TestOutgoingLinkPreviewKeepsTheSingleThreeSecondBudget(t *testing.T) {
	ctx := context.Background()
	a := previewActions(t)
	base := dripServer(t, a, false, true) // the page answers at once; the picture never finishes
	enabled := false
	content := &event.MessageEventContent{Body: "Read " + base + "/story"}
	start := time.Now()
	a.applyLinkPreviews(ctx, content, &enabled)
	elapsed := time.Since(start)
	require.Less(t, elapsed, 3600*time.Millisecond, "a slow picture does not hold a send up past the 3 seconds")
	require.GreaterOrEqual(t, elapsed, 2*time.Second, "it did wait for it")
	require.Len(t, content.BeeperLinkPreviews, 1, "the page's preview still goes, without the picture")
	require.Empty(t, string(content.BeeperLinkPreviews[0].ImageURL))
}
