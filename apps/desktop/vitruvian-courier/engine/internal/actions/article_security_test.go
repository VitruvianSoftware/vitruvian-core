// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"net"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// (x/net/html stops nesting at 512 itself, so this is a guard on that: a dependency change that lifted it would show here.)
// extractWithin runs ExtractArticle on raw and fails when it takes longer than limit: a hostile page must cost the
// engine about as much as a normal one, because the parse runs after the fetch's time limit has stopped counting.
func extractWithin(t *testing.T, name, raw string, limit time.Duration) {
	t.Helper()
	done := make(chan *Article, 1)
	go func() { done <- ExtractArticle([]byte(raw), "text/html", mustURL(t, "https://hostile.example.test/a")) }()
	select {
	case art := <-done:
		require.NotNil(t, art, name)
	case <-time.After(limit):
		t.Fatalf("%s: ExtractArticle still running after %s on a %d byte page", name, limit, len(raw))
	}
}

func TestExtractArticleStaysFastOnHostilePages(t *testing.T) {
	const size = maxArticleHTMLBytes
	rep := func(prefix, unit string) string { return prefix + strings.Repeat(unit, size/len(unit)) }
	pages := map[string]string{
		"nested article":         rep("", "<article>"),
		"nested main":            rep("", "<main>"),
		"nested itemprop":        rep("", `<div itemprop="articleBody">`),
		"nested furniture class": rep("<body>", `<div class="nav">`),
		"nested divs":            rep("<body>", "<div>"),
		"misnested formatting":   rep("<body>", "<b><p>"),
		"nested tables":          rep("<body>", "<table><tr><td>"),
		"many articles":          rep("<body>", "<article>x</article>"),
		"many furniture blocks":  rep("<body><p>", `<span class="share">x</span>`),
	}
	for name, raw := range pages {
		extractWithin(t, name, raw, 5*time.Second)
	}
}

func TestPrivateAddressGuardCoversEmbeddedIPv4(t *testing.T) {
	// IPv6 forms that carry an IPv4 address: a NAT64 gateway or a 6to4 relay turns them into a connection to the IPv4
	// address, so a private one must be refused here as it is in plain IPv4.
	for _, bad := range []string{
		"64:ff9b::7f00:1",        // NAT64 well-known prefix, 127.0.0.1
		"64:ff9b::a00:1",         // 10.0.0.1
		"64:ff9b::a9fe:a9fe",     // 169.254.169.254
		"64:ff9b::c0a8:101",      // 192.168.1.1
		"::7f00:1",               // IPv4-compatible, 127.0.0.1
		"::a9fe:a9fe",            // IPv4-compatible, 169.254.169.254
		"2002:7f00:1::",          // 6to4, 127.0.0.1
		"2002:a9fe:a9fe::1",      // 6to4, 169.254.169.254
		"64:ff9b:1:a00:0:100::",  // local-use NAT64 prefix (RFC 8215), 10.0.0.1
		"64:ff9b:1:7f00:0:100::", // local-use NAT64 prefix, 127.0.0.1
	} {
		require.True(t, isPrivateOrLoopbackIP(net.ParseIP(bad)), "must reject %s", bad)
	}
	for _, ok := range []string{"64:ff9b::5db8:d822", "2002:5db8:d822::1", "93.184.216.34", "2606:2800:220:1:248:1893:25c8:1946"} {
		require.False(t, isPrivateOrLoopbackIP(net.ParseIP(ok)), "must allow %s", ok)
	}
}
