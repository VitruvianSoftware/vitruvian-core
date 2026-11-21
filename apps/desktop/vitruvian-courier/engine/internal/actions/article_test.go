// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"unicode/utf8"

	"github.com/stretchr/testify/require"
)

// The articles below are fixture pages: no network. Each paragraph is written long enough to count as story text.
const (
	para1 = "Officials said on Tuesday that the new bridge across the river will open to traffic in March, two months ahead of the schedule set last year."
	para2 = "The project cost 48 million dollars, according to the transport department, which paid for it with a federal grant and a state bond."
	para3 = "\"We never expected to finish early,\" said Dana Ortiz, the lead engineer. \"The crews worked through the winter and it paid off.\""
	para4 = "Local businesses expect the crossing to cut a 25 minute detour for about 9,000 drivers a day, the mayor's office said in a statement."
	para5 = "The first lane opens on March 3 and the second a week later, after inspectors finish their final checks on the approach roads."
)

var newsPageHead = `<!doctype html><html lang="en"><head>
<title>New bridge opens early - Example News</title>
<meta property="og:title" content="New bridge opens early">
<meta property="og:site_name" content="Example News">
<meta property="og:description" content="A new bridge across the river will open to traffic in March, two months early, officials say.">
<script>var tracking = "this must never appear in the text";</script>
<style>.x { color: red }</style>
</head>`

func mustURL(t *testing.T, raw string) *url.URL {
	t.Helper()
	u, err := url.Parse(raw)
	require.NoError(t, err)
	return u
}

func TestExtractArticleReadsMainTextAndLeavesFurnitureOut(t *testing.T) {
	page := newsPageHead + `<body>
<header><a href="/">Example News</a> <nav><a href="/world">World</a><a href="/sport">Sport</a></nav></header>
<div class="ad-slot">Advertisement: buy shoes now, they are very comfortable indeed</div>
<article>
  <header><h1>New bridge opens early</h1><p class="byline">By Sam Reporter</p></header>
  <p>` + para1 + `</p>
  <p>` + para2 + ` <a href="/x">source</a></p>
  <aside><p>Sidebar: you might also like this other story about something else entirely</p></aside>
  <h2>What the mayor said</h2>
  <p>` + para3 + `</p>
  <figure><img src="a.jpg"><figcaption>Photo: crews at work on the bridge deck, courtesy of the department</figcaption></figure>
  <p style="display:none">Hidden text that readers never see and the page never shows on screen.</p>
  <p>` + para4 + `</p>
  <p>` + para5 + `</p>
  <div class="related-stories"><h3>Related</h3><ul><li><a href="/a">Another story about another bridge somewhere</a></li></ul></div>
  <div id="comments"><p>First! This is a reader comment that must not be part of the article text.</p></div>
</article>
<footer><p>Copyright 2026 Example News. All rights reserved by the publisher of this site.</p></footer>
<script>document.write("never")</script>
</body></html>`
	a := ExtractArticle([]byte(page), "text/html; charset=utf-8", mustURL(t, "https://www.example.com/news/bridge"))

	require.Equal(t, "New bridge opens early", a.Title)
	require.Equal(t, "Example News", a.Site)
	require.Contains(t, a.Description, "A new bridge across the river")
	require.False(t, a.Paywalled)
	require.False(t, a.NeedsBrowser)
	require.Equal(t, "https://www.example.com/news/bridge", a.URL)
	for _, want := range []string{para1, "What the mayor said", para3, para4, para5} {
		require.Contains(t, a.Text, want)
	}
	require.Contains(t, a.Text, "The project cost 48 million dollars")
	for _, bad := range []string{
		"tracking", "document.write", "Advertisement", "Sidebar", "Photo: crews", "Hidden text", "Related", "Another story",
		"First!", "Copyright", "By Sam Reporter", "World",
	} {
		require.NotContains(t, a.Text, bad)
	}
	require.Contains(t, a.Text, "\n\n", "paragraphs are separated by a blank line")
}

func TestExtractArticleFindsTheBodyWithoutAnArticleTag(t *testing.T) {
	page := newsPageHead + `<body class="has-sidebar page-story">
<div class="site-header"><a href="/">Home</a></div>
<div itemprop="articleBody" class="story-body has-sidebar">
  <p>` + para1 + `</p><p>` + para2 + `</p><p>` + para3 + `</p><p>` + para4 + `</p><p>` + para5 + `</p>
</div>
<div class="newsletter-box"><p>Sign up for our newsletter to get the best stories sent to you every morning.</p></div>
</body></html>`
	a := ExtractArticle([]byte(page), "", mustURL(t, "https://example.com/s"))
	require.False(t, a.NeedsBrowser)
	require.Contains(t, a.Text, para1)
	require.Contains(t, a.Text, para5)
	require.NotContains(t, a.Text, "newsletter")

	// No markup hint at all: the body's paragraphs are the story, and a wrapper that has a "sidebar" class word is
	// not thrown away.
	plain := newsPageHead + `<body><div class="wrap has-sidebar"><div class="content">
  <p>` + para1 + `</p><p>` + para2 + `</p><p>` + para3 + `</p><p>` + para4 + `</p>
</div></div><div class="nav"><a href="/a">A link list item</a></div></body></html>`
	b := ExtractArticle([]byte(plain), "", mustURL(t, "https://example.com/s"))
	require.False(t, b.NeedsBrowser)
	require.Contains(t, b.Text, para4)
}

func TestExtractArticleTitleAndSiteFallBack(t *testing.T) {
	page := `<html><head><title>  Plain   title </title></head><body><article><h1>The headline</h1>
<p>` + para1 + `</p><p>` + para2 + `</p><p>` + para3 + `</p></article></body></html>`
	a := ExtractArticle([]byte(page), "", mustURL(t, "https://www.sub.example.org/x"))
	require.Equal(t, "The headline", a.Title, "the h1 comes before the <title>")
	require.Equal(t, "sub.example.org", a.Site, "no og:site_name: the host without www.")

	page2 := `<html><head><title>  Plain   title </title></head><body><article>
<p>` + para1 + `</p><p>` + para2 + `</p></article></body></html>`
	require.Equal(t, "Plain title", ExtractArticle([]byte(page2), "", mustURL(t, "https://example.org/x")).Title)
}

func TestExtractArticleDetectsPaywalls(t *testing.T) {
	teaser := `<p>` + para1 + `</p><p>` + para2 + `</p>`
	long := ""
	for i := range 12 {
		long += fmt.Sprintf(`<p>Part %d. %s %s %s</p>`, i, para1, para2, para3)
	}
	cases := []struct {
		name      string
		page      string
		paywalled bool
		browser   bool
	}{
		{
			name: "schema.org isAccessibleForFree false with a teaser",
			page: newsPageHead + `<script type="application/ld+json">{"@context":"https://schema.org","@type":"NewsArticle","headline":"x","isAccessibleForFree":false}</script>
<body><article>` + teaser + `</article></body></html>`,
			paywalled: true,
		},
		{
			name: "isAccessibleForFree as the string False inside a graph",
			page: newsPageHead + `<script type="application/ld+json">{"@graph":[{"@type":"WebPage"},{"@type":"NewsArticle","isAccessibleForFree":"False"}]}</script>
<body><article>` + teaser + `</article></body></html>`,
			paywalled: true,
		},
		{
			name: "isAccessibleForFree false but the site sent the whole text",
			page: newsPageHead + `<script type="application/ld+json">{"@type":"NewsArticle","isAccessibleForFree":false}</script>
<body><article>` + long + `</article></body></html>`,
			paywalled: false,
		},
		{
			name: "isAccessibleForFree true is not a marker",
			page: newsPageHead + `<script type="application/ld+json">{"@type":"NewsArticle","isAccessibleForFree":true}</script>
<body><article>` + teaser + `</article></body></html>`,
			paywalled: false,
		},
		{
			name:      "a paywall element with a teaser",
			page:      newsPageHead + `<body><article>` + teaser + `</article><div class="tp-modal"><p>Subscribe to keep reading this article and all our journalism</p></div></body></html>`,
			paywalled: true,
		},
		{
			name:      "article:content_tier locked",
			page:      newsPageHead + `<meta property="article:content_tier" content="locked"><body><article>` + teaser + `</article></body></html>`,
			paywalled: true,
		},
		{
			name: "no marker, a short lead under a long description",
			page: `<html><head><meta property="og:description" content="` + strings.Repeat("A long and detailed description of the story. ", 6) + `"></head>
<body><article><p>` + para1 + `</p><p>Subscribers can read on.</p></article></body></html>`,
			paywalled: true,
		},
		{
			name:      "a real short article with a short description is not a paywall",
			page:      `<html><head><meta property="og:description" content="Bridge opens early."></head><body><article><p>` + para1 + `</p><p>` + para2 + `</p></article></body></html>`,
			paywalled: false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			a := ExtractArticle([]byte(tc.page), "text/html", mustURL(t, "https://www.usatoday.com/story/x"))
			require.Equal(t, tc.paywalled, a.Paywalled)
			require.Equal(t, tc.browser, a.NeedsBrowser)
			if !tc.paywalled {
				require.NotEmpty(t, a.Text)
			}
		})
	}
}

func TestExtractArticleNeedsBrowserWhenThereIsNoText(t *testing.T) {
	shell := `<!doctype html><html><head><title>App</title><meta property="og:title" content="Story"></head>
<body><div id="root"></div><noscript>You need to enable JavaScript to run this app.</noscript>
<script src="/bundle.js"></script></body></html>`
	a := ExtractArticle([]byte(shell), "text/html", mustURL(t, "https://spa.example.com/a"))
	require.True(t, a.NeedsBrowser)
	require.False(t, a.Paywalled)
	require.Empty(t, a.Text)
	require.Equal(t, "Story", a.Title)

	// The same shell, but its structured data carries the article: that is readable.
	body := strings.Repeat(para1+" "+para2+"\n", 3)
	withLD := strings.Replace(shell, "</head>", `<script type="application/ld+json">`+mustJSON(t, map[string]any{
		"@type": "NewsArticle", "articleBody": body,
	})+`</script></head>`, 1)
	b := ExtractArticle([]byte(withLD), "text/html", mustURL(t, "https://spa.example.com/a"))
	require.False(t, b.NeedsBrowser)
	require.Contains(t, b.Text, "The project cost 48 million dollars")

	// But structured data on a page that says it is not free is the paywalled part: not used.
	locked := strings.Replace(shell, "</head>", `<script type="application/ld+json">`+mustJSON(t, map[string]any{
		"@type": "NewsArticle", "isAccessibleForFree": false, "articleBody": body,
	})+`</script></head>`, 1)
	c := ExtractArticle([]byte(locked), "text/html", mustURL(t, "https://spa.example.com/a"))
	require.True(t, c.Paywalled)
	require.NotContains(t, c.Text, "The project cost")
}

func mustJSON(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	require.NoError(t, err)
	return string(b)
}

func TestExtractArticleCapsTheTextAtAParagraphBoundary(t *testing.T) {
	var b strings.Builder
	for i := range 400 {
		fmt.Fprintf(&b, "<p>Paragraph number %d. %s %s</p>", i, para1, para2)
	}
	a := ExtractArticle([]byte(newsPageHead+`<body><article>`+b.String()+`</article></body></html>`), "text/html", mustURL(t, "https://example.com/long"))
	n := utf8.RuneCountInString(a.Text)
	require.LessOrEqual(t, n, MaxArticleTextRunes)
	require.Greater(t, n, MaxArticleTextRunes-600, "the cap is filled, not undershot")
	require.True(t, strings.HasSuffix(a.Text, para2), "cut between paragraphs, never inside one: %q", a.Text[len(a.Text)-40:])
}

func TestExtractArticleDecodesTheDeclaredCharset(t *testing.T) {
	// "café" in ISO-8859-1 is one byte for the é (0xE9): read as UTF-8 it would be a replacement character.
	page := "<html><head><meta charset=\"iso-8859-1\"></head><body><article><p>" + strings.Repeat("The caf\xe9 on the corner opened a second shop this week, which the owner said was a surprise. ", 4) + "</p></article></body></html>"
	a := ExtractArticle([]byte(page), "text/html; charset=ISO-8859-1", mustURL(t, "https://example.fr/a"))
	require.Contains(t, a.Text, "café")
	require.NotContains(t, a.Text, "�")
}

func goodPage() string {
	return newsPageHead + `<body><article><p>` + para1 + `</p><p>` + para2 + `</p><p>` + para3 + `</p></article></body></html>`
}

func newArticleActions(t *testing.T, h http.HandlerFunc) (*Actions, *httptest.Server) {
	t.Helper()
	srv := httptest.NewTLSServer(h)
	t.Cleanup(srv.Close)
	a := &Actions{}
	a.SetLinkPreviewHTTPClient(srv.Client())
	return a, srv
}

func TestReadArticleFetchesAndExtracts(t *testing.T) {
	var gotUA, gotAccept string
	a, srv := newArticleActions(t, func(w http.ResponseWriter, r *http.Request) {
		gotUA, gotAccept = r.Header.Get("User-Agent"), r.Header.Get("Accept")
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(goodPage()))
	})
	art, err := a.ReadArticle(context.Background(), srv.URL+"/story")
	require.NoError(t, err)
	require.Equal(t, "New bridge opens early", art.Title)
	require.Contains(t, art.Text, para3)
	require.False(t, art.Paywalled)
	require.False(t, art.NeedsBrowser)
	require.Equal(t, srv.URL+"/story", art.URL)
	require.Contains(t, gotAccept, "text/html")
	require.Contains(t, gotUA, "VitruvianCourier")
}

func TestReadArticleFollowsARedirectAndReportsWhereItEnded(t *testing.T) {
	a, srv := newArticleActions(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/go" {
			http.Redirect(w, r, "/final", http.StatusFound)
			return
		}
		w.Header().Set("Content-Type", "text/html")
		_, _ = w.Write([]byte(goodPage()))
	})
	art, err := a.ReadArticle(context.Background(), srv.URL+"/go")
	require.NoError(t, err)
	require.Equal(t, srv.URL+"/final", art.URL)
	require.NotEmpty(t, art.Text)
}

func TestReadArticleAnswersNotErrorsForPagesItCannotRead(t *testing.T) {
	cases := []struct {
		name      string
		handler   http.HandlerFunc
		paywalled bool
	}{
		{"402 is a paywall", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusPaymentRequired) }, true},
		{"403 is a page that needs a browser", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusForbidden) }, false},
		{"500", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusInternalServerError) }, false},
		{"a PDF", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/pdf")
			_, _ = w.Write([]byte("%PDF-1.7"))
		}, false},
		{"an empty page", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "text/html")
		}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			a, srv := newArticleActions(t, tc.handler)
			art, err := a.ReadArticle(context.Background(), srv.URL+"/x")
			require.NoError(t, err)
			require.Equal(t, tc.paywalled, art.Paywalled)
			require.Equal(t, !tc.paywalled, art.NeedsBrowser)
			require.Empty(t, art.Text)
		})
	}
}

func TestReadArticleRefusesAddressesThatAreNotHTTPS(t *testing.T) {
	a := &Actions{}
	for _, bad := range []string{"", "not a url", "http://example.com/a", "ftp://example.com/a", "file:///etc/passwd", "https://", "https://user:pw@example.com/a"} {
		_, err := a.ReadArticle(context.Background(), bad)
		require.ErrorIs(t, err, ErrBadValue, bad)
	}
}

func TestReadArticleKeepsTheLinkPreviewClientsPrivateAddressGuard(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		_, _ = w.Write([]byte(goodPage()))
	}))
	defer srv.Close()
	// The production client (no override) resolves the name and refuses a private or loopback address before it
	// connects, so a name that points at this Mac never reaches the server.
	for _, ip := range []string{"127.0.0.1", "10.0.0.5", "192.168.1.9", "169.254.169.254", "100.64.0.7", "::1", "fd00::1"} {
		a := &Actions{}
		a.SetLinkPreviewResolver(func(ctx context.Context, host string) ([]net.IPAddr, error) {
			return []net.IPAddr{{IP: net.ParseIP(ip)}}, nil
		})
		_, port, err := net.SplitHostPort(strings.TrimPrefix(srv.URL, "https://"))
		require.NoError(t, err)
		art, err := a.ReadArticle(context.Background(), "https://news.example.test:"+port+"/story")
		require.NoError(t, err, ip)
		require.True(t, art.NeedsBrowser, ip)
		require.Empty(t, art.Text, ip)
	}
	require.Zero(t, hits.Load(), "no request reached the server")
}

func TestReadArticleReadsAtMostTheSizeCap(t *testing.T) {
	late := "A paragraph far past the size cap that must not be read, because the page is cut off long before it."
	a, srv := newArticleActions(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		_, _ = w.Write([]byte(newsPageHead + `<body><article><p>` + para1 + `</p><p>` + para2 + `</p><p>` + para3 + `</p>`))
		_, _ = w.Write([]byte("<!--" + strings.Repeat("x", 3<<20) + "-->"))
		_, _ = w.Write([]byte(`<p>` + late + `</p></article></body></html>`))
	})
	art, err := a.ReadArticle(context.Background(), srv.URL+"/big")
	require.NoError(t, err)
	require.Contains(t, art.Text, para3)
	require.NotContains(t, art.Text, late)
}

func TestReadArticleCancelledContextIsTheContextsError(t *testing.T) {
	a, srv := newArticleActions(t, func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := a.ReadArticle(ctx, srv.URL+"/x")
	require.ErrorIs(t, err, context.Canceled)
}
