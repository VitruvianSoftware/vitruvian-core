// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

// ErrBadPreviewURL means the address isn't one a preview picture is fetched for: not an https address with a host.
var ErrBadPreviewURL = errors.New("a preview picture is fetched only for an https address")

const (
	maxPreviewImageURLBytes = 2048
	// previewImageNoneLifetime is how long "the page was read and names no picture" is believed: a page seldom gains
	// one. Nothing else is believed this long.
	previewImageNoneLifetime = 7 * 24 * time.Hour
	// previewImageUnknownLifetime is how long a failed look-up is believed (the page or its picture did not answer, was
	// not 2xx, was refused, too big or not a picture), so a link in a chat that scrolls past again and again is not asked
	// for each time, and one that was only slow gets another go within the hour.
	previewImageUnknownLifetime = time.Hour
	previewImageKeyPrefix       = store.LinkPreviewImageKeyPrefix
)

// previewImageRowsKept is how many remembered addresses are kept; a test lowers it.
var previewImageRowsKept = store.LinkPreviewImageRowsKept

// previewImageNow is the clock the cache's lifetimes are read by; a test sets it.
var previewImageNow = time.Now

// PreviewImage is the picture a page names as its own (og:image), saved on this Mac. The zero value says the page has
// none.
type PreviewImage struct {
	// ImagePath is the saved file; empty when the page has no picture (or none could be had).
	ImagePath   string
	ImageWidth  int
	ImageHeight int
	BlurHash    string
}

// previewImageRecord is what is remembered of one address, in the store's settings.
type previewImageRecord struct {
	// State is "found", "none" (the page answered and names no usable picture) or "unknown" (it did not answer).
	State   string `json:"state"`
	URI     string `json:"uri,omitempty"`
	Width   int    `json:"w,omitempty"`
	Height  int    `json:"h,omitempty"`
	Blur    string `json:"blur,omitempty"`
	AtMilli int64  `json:"at"`
}

// previewImageFlights lets callers of one address that arrive together share one look-up.
type previewImageFlights struct {
	mu    sync.Mutex
	calls map[string]*previewImageCall
}

type previewImageCall struct {
	done chan struct{}
	res  PreviewImage
	err  error
}

var previewImageFlight = &previewImageFlights{calls: map[string]*previewImageCall{}}

// PreviewImageForURL is the picture of the page at rawURL, for a link card whose chat network sent no picture. It
// fetches the page the way a link preview of a message I send is fetched (fetchLinkPreview: https only, the private
// address guard, the 256 KiB page and 2 MiB picture limits, the timeout and redirect cap), saves the picture in the
// media store and remembers the answer per address, so a page is asked for once: a found picture for good (until its
// file is cleaned up), "no picture" for a week and a failed look-up for an hour. It never fetches when the answer is
// remembered. The app asks only while "Show link previews" is on.
func (a *Actions) PreviewImageForURL(ctx context.Context, rawURL string) (PreviewImage, error) {
	canonical, err := canonicalPreviewURL(rawURL)
	if err != nil {
		return PreviewImage{}, err
	}
	sum := sha256.Sum256([]byte(canonical))
	key := previewImageKeyPrefix + hex.EncodeToString(sum[:])
	if res, ok := a.rememberedPreviewImage(ctx, key); ok {
		return res, nil
	}

	flightKey := fmt.Sprintf("%p|%s", a, key)
	previewImageFlight.mu.Lock()
	if call, running := previewImageFlight.calls[flightKey]; running {
		previewImageFlight.mu.Unlock()
		select {
		case <-call.done:
			return call.res, call.err
		case <-ctx.Done():
			return PreviewImage{}, ctx.Err()
		}
	}
	call := &previewImageCall{done: make(chan struct{})}
	previewImageFlight.calls[flightKey] = call
	previewImageFlight.mu.Unlock()

	call.res, call.err = a.fetchPreviewImage(ctx, canonical, key)
	previewImageFlight.mu.Lock()
	delete(previewImageFlight.calls, flightKey)
	previewImageFlight.mu.Unlock()
	close(call.done)
	return call.res, call.err
}

func (a *Actions) fetchPreviewImage(ctx context.Context, canonical, key string) (PreviewImage, error) {
	if a.m == nil || a.s == nil {
		return PreviewImage{}, nil
	}
	// A look-up that finished while this one waited for its turn.
	if res, ok := a.rememberedPreviewImage(ctx, key); ok {
		return res, nil
	}
	// What is remembered: "found" for a saved picture; "none" only when the page was read and names no picture; and
	// "unknown" for everything else (the page did not answer, or its picture was refused, did not answer, was not 2xx,
	// was too big or was not a picture), which is believed for an hour only.
	rec := previewImageRecord{State: "unknown", AtMilli: previewImageNow().UnixMilli()}
	var res PreviewImage
	if lp, outcome := a.fetchLinkPreviewDetail(ctx, canonical, true); lp != nil {
		switch uri := string(lp.ImageURL); {
		case uri != "" && a.previewImagePath(uri) != "":
			rec = previewImageRecord{
				State: "found", URI: uri, Width: int(lp.ImageWidth), Height: int(lp.ImageHeight),
				Blur: lp.ImageBlurhash, AtMilli: rec.AtMilli,
			}
			res = PreviewImage{ImagePath: a.previewImagePath(uri), ImageWidth: rec.Width, ImageHeight: rec.Height, BlurHash: rec.Blur}
		case !outcome.Named:
			rec.State = "none"
		}
	}
	// Remembered even when the caller has gone (ctx): the page was fetched, so it is not fetched again.
	bg := context.WithoutCancel(ctx)
	if raw, err := json.Marshal(rec); err == nil {
		_ = a.s.SetSetting(bg, key, string(raw))
		a.prunePreviewImages(bg, rec.AtMilli)
	}
	return res, nil
}

// prunePreviewImages drops the remembered pictures that are over their lifetime, and all but the newest
// store.LinkPreviewImageRowsKept, so the table does not grow with every link ever seen. It runs after each write.
func (a *Actions) prunePreviewImages(ctx context.Context, nowMilli int64) {
	_, _ = a.s.PruneLinkPreviewImages(ctx, nowMilli-previewImageNoneLifetime.Milliseconds(),
		nowMilli-previewImageUnknownLifetime.Milliseconds(), previewImageRowsKept)
}

// rememberedPreviewImage is the remembered answer for key, and whether there is a current one.
func (a *Actions) rememberedPreviewImage(ctx context.Context, key string) (PreviewImage, bool) {
	if a.s == nil {
		return PreviewImage{}, false
	}
	raw, ok, err := a.s.Setting(ctx, key)
	if err != nil || !ok {
		return PreviewImage{}, false
	}
	var rec previewImageRecord
	if json.Unmarshal([]byte(raw), &rec) != nil {
		return PreviewImage{}, false
	}
	age := previewImageNow().Sub(time.UnixMilli(rec.AtMilli))
	switch rec.State {
	case "found":
		// The file may have been cleaned up (Storage) since: then it is fetched again.
		if path := a.previewImagePath(rec.URI); path != "" && previewFileExists(path) {
			return PreviewImage{ImagePath: path, ImageWidth: rec.Width, ImageHeight: rec.Height, BlurHash: rec.Blur}, true
		}
	case "none":
		return PreviewImage{}, age < previewImageNoneLifetime
	case "unknown":
		return PreviewImage{}, age < previewImageUnknownLifetime
	}
	return PreviewImage{}, false
}

// previewImagePath is where the media store keeps the picture at uri; empty when it holds none.
func (a *Actions) previewImagePath(uri string) string {
	if a.m == nil {
		return ""
	}
	hash, ok := ids.ParseContentURI(id.ContentURIString(uri))
	if !ok {
		return ""
	}
	path, err := a.m.Path(hash)
	if err != nil {
		return ""
	}
	return path
}

func previewFileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// canonicalPreviewURL is rawURL as the cache keys it: an https address with a host and no sign-in or fragment.
func canonicalPreviewURL(rawURL string) (string, error) {
	rawURL = strings.TrimSpace(rawURL)
	if rawURL == "" || len(rawURL) > maxPreviewImageURLBytes {
		return "", ErrBadPreviewURL
	}
	u, err := url.Parse(rawURL)
	if err != nil || !strings.EqualFold(u.Scheme, "https") || u.Hostname() == "" || u.User != nil {
		return "", ErrBadPreviewURL
	}
	u.Scheme = "https"
	u.Host = strings.ToLower(u.Host)
	u.Fragment = ""
	return u.String(), nil
}
