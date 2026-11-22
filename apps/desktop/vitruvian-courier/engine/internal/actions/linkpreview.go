// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"errors"
	"fmt"
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

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/media"
)

const (
	maxLinkPreviewHTMLBytes  = 256 * 1024
	maxLinkPreviewImageBytes = 2 * 1024 * 1024
)

// A preview of a message I send has one time for the page and the picture together (linkPreviewTimeout), so a slow site
// never holds a send up longer than that. A link card's picture (PreviewImageForURL) gets its own, after the page's
// (variables so a test can shorten them).
var (
	linkPreviewTimeout      = 3 * time.Second
	linkPreviewImageTimeout = 5 * time.Second
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
	// No Timeout of its own: the page and the picture each carry their own context deadline (fetchLinkPreviewDetail).
	return &http.Client{
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
			// One page and one picture per client: nothing is kept idle, so a client made for each fetch leaves no
			// connection (or the goroutines that serve it) behind.
			DisableKeepAlives: true,
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
	// An IPv6 form that carries an IPv4 address (NAT64, 6to4, IPv4-compatible) is judged by that address: a gateway
	// turns the connection into one to the IPv4 host, which may be on this Mac or its network.
	if v4, ok := embeddedIPv4(addr); ok {
		return isPrivateOrLoopbackIP(v4.AsSlice())
	}
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

var (
	nat64Prefix      = netip.MustParsePrefix("64:ff9b::/96")   // RFC 6052 well-known prefix
	nat64LocalPrefix = netip.MustParsePrefix("64:ff9b:1::/48") // RFC 8215 local-use prefix
	ipv4CompatPrefix = netip.MustParsePrefix("::/96")          // deprecated IPv4-compatible
	sixToFourPrefix  = netip.MustParsePrefix("2002::/16")      // 6to4
)

// embeddedIPv4 is the IPv4 address an IPv6 address carries, when it is one of the forms that do.
func embeddedIPv4(addr netip.Addr) (netip.Addr, bool) {
	if !addr.Is6() {
		return netip.Addr{}, false
	}
	b := addr.As16()
	switch {
	case nat64Prefix.Contains(addr), ipv4CompatPrefix.Contains(addr):
		return netip.AddrFrom4([4]byte{b[12], b[13], b[14], b[15]}), true
	case nat64LocalPrefix.Contains(addr):
		// RFC 6052: a /48 prefix puts the IPv4 address in bytes 6-7 and 9-10 (byte 8 is zero).
		return netip.AddrFrom4([4]byte{b[6], b[7], b[9], b[10]}), true
	case sixToFourPrefix.Contains(addr):
		return netip.AddrFrom4([4]byte{b[2], b[3], b[4], b[5]}), true
	}
	return netip.Addr{}, false
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
	lp, _ := a.fetchLinkPreviewDetail(ctx, targetURL, false)
	return lp
}

// linkPreviewImageOutcome says what became of the page's picture, for a caller that remembers the answer (the picture
// of a link card, PreviewImageForURL).
type linkPreviewImageOutcome struct {
	// Named is true when the page names an og:image at all.
	Named bool
	// Err is why that picture could not be had (it was refused, did not answer, was not 2xx, too big, or not a picture);
	// nil when it was saved, or when the page names none.
	Err error
}

// fetchLinkPreviewDetail is fetchLinkPreview and what became of the page's picture. The page and the picture share
// linkPreviewTimeout, as for a message I send; with ownImageTime (a link card's picture, which holds nothing up) the
// picture has linkPreviewImageTimeout of its own after the page's.
func (a *Actions) fetchLinkPreviewDetail(ctx context.Context, targetURL string, ownImageTime bool) (*event.BeeperLinkPreview, linkPreviewImageOutcome) {
	parsedURL, err := url.Parse(targetURL)
	if err != nil || parsedURL.Scheme != "https" || parsedURL.Host == "" {
		return nil, linkPreviewImageOutcome{}
	}
	fetchCtx, cancel := context.WithTimeout(ctx, linkPreviewTimeout)
	defer cancel()

	client := a.getLinkPreviewClient()
	// Whatever the client kept idle goes when the fetch ends (a client given by a test keeps connections alive).
	defer client.CloseIdleConnections()
	req, err := http.NewRequestWithContext(fetchCtx, http.MethodGet, targetURL, nil)
	if err != nil {
		return nil, linkPreviewImageOutcome{}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, linkPreviewImageOutcome{}
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, linkPreviewImageOutcome{}
	}
	bodyBytes, err := io.ReadAll(io.LimitReader(resp.Body, maxLinkPreviewHTMLBytes))
	if err != nil || len(bodyBytes) == 0 {
		return nil, linkPreviewImageOutcome{}
	}

	og := parseOpenGraphTags(string(bodyBytes))
	if og["og:title"] == "" && og["og:description"] == "" && og["og:site_name"] == "" && og["og:image"] == "" {
		return nil, linkPreviewImageOutcome{}
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

	var outcome linkPreviewImageOutcome
	if rawImg := og["og:image"]; rawImg != "" {
		outcome.Named = true
		switch imgURL, err := parsedURL.Parse(rawImg); {
		case a.m == nil:
			outcome.Err = errors.New("no media store to keep the picture in")
		case err != nil || imgURL.Scheme != "https":
			outcome.Err = errors.New("the page's picture is not an https address")
		default:
			imgCtx := fetchCtx // the page's time, shared (a send)
			if ownImageTime {
				var imgCancel context.CancelFunc
				imgCtx, imgCancel = context.WithTimeout(ctx, linkPreviewImageTimeout)
				defer imgCancel()
			}
			outcome.Err = a.populatePreviewImage(imgCtx, client, imgURL.String(), preview)
		}
	}
	return preview, outcome
}

// populatePreviewImage fetches the picture at imgURL into the media store and sets it on preview. The error says why
// it could not (the picture did not answer, was not 2xx, was empty or over 2 MiB, or was not a picture, or one too big
// to decode: media.ErrImageTooLarge).
func (a *Actions) populatePreviewImage(ctx context.Context, client *http.Client, imgURL string, preview *event.BeeperLinkPreview) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, imgURL, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("the picture answered %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxLinkPreviewImageBytes+1))
	if err != nil {
		return err
	}
	if len(data) == 0 || len(data) > maxLinkPreviewImageBytes {
		return errors.New("the picture is empty or over the size limit")
	}
	meta, err := media.InspectLinkPreviewImage(data)
	if err != nil {
		return err
	}
	hash, err := a.m.Put(data)
	if err != nil {
		return err
	}
	preview.ImageURL = ids.ContentURI(hash)
	preview.ImageSize = event.IntOrString(len(data))
	preview.ImageWidth = event.IntOrString(meta.Width)
	preview.ImageHeight = event.IntOrString(meta.Height)
	preview.ImageBlurhash = meta.BlurHash
	if ct := baseType(resp.Header.Get("Content-Type")); strings.HasPrefix(ct, "image/") {
		preview.ImageType = ct
	}
	return nil
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
