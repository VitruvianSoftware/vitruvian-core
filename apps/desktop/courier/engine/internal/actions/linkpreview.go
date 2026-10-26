// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"errors"
	"html"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"regexp"
	"strings"
	"time"

	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
)

const (
	linkPreviewTimeout       = 3 * time.Second
	maxLinkPreviewHTMLBytes  = 256 * 1024
	maxLinkPreviewImageBytes = 2 * 1024 * 1024
)

var (
	urlInBodyRE = regexp.MustCompile(`https?://[^\s<>"]+`)
	metaTagRE   = regexp.MustCompile(`(?is)<meta\b[^>]*>`)
	attrPropRE  = regexp.MustCompile(`(?is)\b(?:property|name)\s*=\s*["']([^"']+)["']`)
	attrContRE  = regexp.MustCompile(`(?is)\bcontent\s*=\s*["']([^"']*)["']`)
)

// SetLinkPreviewHTTPClient overrides the HTTP client used when DisableLinkPreview is explicitly false.
// Tests use this to point at an in-process httptest.Server without relaxing the production private-IP guard.
func (a *Actions) SetLinkPreviewHTTPClient(c *http.Client) {
	a.mu.Lock()
	a.linkClient = c
	a.mu.Unlock()
}

// SetLinkPreviewResolver overrides the DNS lookup function used by the production link-preview HTTP transport.
func (a *Actions) SetLinkPreviewResolver(fn func(ctx context.Context, host string) ([]net.IPAddr, error)) {
	a.mu.Lock()
	a.linkResolver = fn
	a.mu.Unlock()
}

const maxLinkPreviewRedirects = 3

var nonPublicPrefixes = []netip.Prefix{
	netip.MustParsePrefix("0.0.0.0/8"),
	netip.MustParsePrefix("100.64.0.0/10"),   // RFC 6598 CGNAT / Tailscale tailnet
	netip.MustParsePrefix("169.254.0.0/16"),  // IPv4 link-local
	netip.MustParsePrefix("192.0.0.0/24"),    // IETF Protocol Assignments
	netip.MustParsePrefix("192.0.2.0/24"),    // TEST-NET-1
	netip.MustParsePrefix("198.18.0.0/15"),   // RFC 2544 benchmarking
	netip.MustParsePrefix("198.51.100.0/24"), // TEST-NET-2
	netip.MustParsePrefix("203.0.113.0/24"),  // TEST-NET-3
	netip.MustParsePrefix("240.0.0.0/4"),     // Reserved / class E
	netip.MustParsePrefix("fc00::/7"),        // IPv6 Unique Local Address (ULA)
	netip.MustParsePrefix("fe80::/10"),       // IPv6 link-local
	netip.MustParsePrefix("2001:db8::/32"),   // IPv6 documentation
}

func (a *Actions) getLinkPreviewClient() *http.Client {
	a.mu.Lock()
	c := a.linkClient
	resolver := a.linkResolver
	a.mu.Unlock()
	if c != nil {
		return c
	}
	if resolver == nil {
		resolver = net.DefaultResolver.LookupIPAddr
	}
	dialer := &net.Dialer{Timeout: linkPreviewTimeout}
	return &http.Client{
		Timeout: linkPreviewTimeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= maxLinkPreviewRedirects {
				return errors.New("too many redirects")
			}
			if req.URL == nil || !strings.EqualFold(req.URL.Scheme, "https") {
				return errors.New("refusing non-https link preview redirect")
			}
			return nil
		},
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				host, port, err := net.SplitHostPort(addr)
				if err != nil {
					return nil, err
				}
				ips, err := resolver(ctx, host)
				if err != nil {
					return nil, err
				}
				for _, ip := range ips {
					if isPrivateOrLoopbackIP(ip.IP) {
						return nil, errors.New("refusing link preview connection to private or loopback address")
					}
				}
				if len(ips) == 0 {
					return nil, errors.New("no IP addresses resolved")
				}
				return dialer.DialContext(ctx, network, net.JoinHostPort(ips[0].IP.String(), port))
			},
		},
	}
}

func isPrivateOrLoopbackIP(ip net.IP) bool {
	if len(ip) == 0 {
		return true
	}
	addr, ok := netip.AddrFromSlice(ip)
	if !ok {
		return true
	}
	addr = addr.Unmap()
	if !addr.IsGlobalUnicast() || addr.IsLoopback() || addr.IsPrivate() || addr.IsLinkLocalUnicast() || addr.IsLinkLocalMulticast() || addr.IsMulticast() || addr.IsUnspecified() {
		return true
	}
	for _, p := range nonPublicPrefixes {
		if p.Contains(addr) {
			return true
		}
	}
	return false
}

func firstURLInText(body string) string {
	m := urlInBodyRE.FindString(body)
	if m == "" {
		return ""
	}
	return strings.TrimRight(m, ".,;:!?)]'")
}

// applyLinkPreviews sets com.beeper.linkpreviews on c when c.Body contains a URL:
//   - By default (disable == nil || *disable == true), sets BeeperLinkPreviews to an empty non-nil slice ([]),
//     which serializes as "com.beeper.linkpreviews": [] so bridges suppress server-side unfurling, making zero HTTP requests.
//   - When disable != nil && !*disable, fetches only the first https:// URL on send (bounded by 3s timeout,
//     256 KiB HTML, and 2 MiB og:image) and attaches the resulting BeeperLinkPreview.
func (a *Actions) applyLinkPreviews(ctx context.Context, c *event.MessageEventContent, disable *bool) {
	matched := firstURLInText(c.Body)
	if matched == "" {
		return
	}
	// Default is privacy-first suppression: zero network traffic.
	if disable == nil || *disable {
		c.BeeperLinkPreviews = []*event.BeeperLinkPreview{}
		return
	}
	if !strings.HasPrefix(strings.ToLower(matched), "https://") {
		c.BeeperLinkPreviews = []*event.BeeperLinkPreview{}
		return
	}
	lp := a.fetchLinkPreview(ctx, matched)
	if lp == nil {
		c.BeeperLinkPreviews = []*event.BeeperLinkPreview{}
		return
	}
	c.BeeperLinkPreviews = []*event.BeeperLinkPreview{lp}
}

func (a *Actions) fetchLinkPreview(ctx context.Context, targetURL string) *event.BeeperLinkPreview {
	parsedURL, err := url.Parse(targetURL)
	if err != nil || parsedURL.Scheme != "https" || parsedURL.Host == "" {
		return nil
	}
	fetchCtx, cancel := context.WithTimeout(ctx, linkPreviewTimeout)
	defer cancel()

	client := a.getLinkPreviewClient()
	req, err := http.NewRequestWithContext(fetchCtx, http.MethodGet, targetURL, nil)
	if err != nil {
		return nil
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil
	}
	bodyBytes, err := io.ReadAll(io.LimitReader(resp.Body, maxLinkPreviewHTMLBytes))
	if err != nil || len(bodyBytes) == 0 {
		return nil
	}

	og := parseOpenGraphTags(string(bodyBytes))
	if og["og:title"] == "" && og["og:description"] == "" && og["og:site_name"] == "" && og["og:image"] == "" {
		return nil
	}

	canonical := og["og:url"]
	if canonical == "" {
		canonical = targetURL
	}
	preview := &event.BeeperLinkPreview{
		MatchedURL: targetURL,
		LinkPreview: event.LinkPreview{
			CanonicalURL: canonical,
			Title:        og["og:title"],
			Type:         og["og:type"],
			Description:  og["og:description"],
			SiteName:     og["og:site_name"],
		},
	}

	if rawImg := og["og:image"]; rawImg != "" && a.m != nil {
		if imgURL, err := parsedURL.Parse(rawImg); err == nil && imgURL.Scheme == "https" {
			a.populatePreviewImage(fetchCtx, client, imgURL.String(), preview)
		}
	}
	return preview
}

func (a *Actions) populatePreviewImage(ctx context.Context, client *http.Client, imgURL string, preview *event.BeeperLinkPreview) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, imgURL, nil)
	if err != nil {
		return
	}
	resp, err := client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxLinkPreviewImageBytes+1))
	if err != nil || len(data) == 0 || len(data) > maxLinkPreviewImageBytes {
		return
	}
	meta, err := media.InspectImage(bytes.NewReader(data))
	if err != nil {
		return
	}
	hash, err := a.m.Put(data)
	if err != nil {
		return
	}
	preview.ImageURL = ids.ContentURI(hash)
	preview.ImageSize = event.IntOrString(len(data))
	preview.ImageWidth = event.IntOrString(meta.Width)
	preview.ImageHeight = event.IntOrString(meta.Height)
	preview.ImageBlurhash = meta.BlurHash
	if ct := baseType(resp.Header.Get("Content-Type")); strings.HasPrefix(ct, "image/") {
		preview.ImageType = ct
	}
}

func parseOpenGraphTags(doc string) map[string]string {
	out := map[string]string{}
	for _, tag := range metaTagRE.FindAllString(doc, -1) {
		pm := attrPropRE.FindStringSubmatch(tag)
		cm := attrContRE.FindStringSubmatch(tag)
		if len(pm) < 2 || len(cm) < 2 {
			continue
		}
		key := strings.ToLower(strings.TrimSpace(pm[1]))
		if !strings.HasPrefix(key, "og:") {
			continue
		}
		if _, exists := out[key]; !exists {
			out[key] = strings.TrimSpace(html.UnescapeString(cm[1]))
		}
	}
	return out
}
