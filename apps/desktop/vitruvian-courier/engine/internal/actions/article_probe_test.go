// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// QA probes for article extraction on pages shaped like real sites: furniture the class-word list doesn't name, a
// character set declared only in a <meta>, and structured data next to a page shell.

func qaStory() string {
	return "<p>" + para1 + "</p><p>" + para2 + "</p><p>" + para3 + "</p><p>" + para4 + "</p><p>" + para5 + "</p>"
}

func TestQAExtractArticleCookieBannerAndCommentsOutsideAnArticleTag(t *testing.T) {
	page := newsPageHead + `<body>
<div id="onetrust-consent-sdk"><div role="dialog" aria-label="Cookie consent"><p>We use cookies to personalise content and ads, to provide social media features and analyse our traffic.</p></div></div>
<div class="story">` + qaStory() + `</div>
<ol class="commentlist"><li><p>Great article, I really enjoyed reading all of this and will share it widely.</p></li></ol>
</body></html>`
	a := ExtractArticle([]byte(page), "text/html; charset=utf-8", mustURL(t, "https://example.com/s"))
	require.Contains(t, a.Text, para1)
	require.NotContains(t, a.Text, "We use cookies", "a cookie banner is not the article")
	require.NotContains(t, a.Text, "Great article", "a comment is not the article")
}

func TestQAExtractArticleJSONLDBodyBeatsAShellWithLongBoilerplate(t *testing.T) {
	// A script-built page whose shell carries a long (>600 rune) cookie notice: the structured articleBody is the story.
	notice := strings.Repeat("We value your privacy and use cookies to store and access information on your device for the purposes described here. ", 7)
	long := strings.Repeat(para1+" ", 8)
	page := `<html><head><script type="application/ld+json">{"@type":"NewsArticle","headline":"H","articleBody":"` + long + `"}</script></head>
<body><main><p>` + notice + `</p></main></body></html>`
	a := ExtractArticle([]byte(page), "text/html", mustURL(t, "https://example.com/a"))
	require.Contains(t, a.Text, para1, "the page's own articleBody, not its cookie notice")
	require.NotContains(t, a.Text, "We value your privacy")
}

func TestQARSSIsNotAnArticle(t *testing.T) {
	a, srv := newArticleActions(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		_, _ = w.Write([]byte(`<rss><channel><title>Feed</title><item><title>a</title><description>` + para1 + para2 + `</description></item></channel></rss>`))
	})
	art, err := a.ReadArticle(context.Background(), srv.URL+"/feed")
	require.NoError(t, err)
	require.True(t, art.NeedsBrowser, "text=%q", art.Text)
}

func TestReadArticleReadsXHTMLAndTypedHTMLAndSniffsATypelessPage(t *testing.T) {
	for name, ct := range map[string]string{"xhtml": "application/xhtml+xml; charset=utf-8", "html": "text/html;charset=UTF-8", "none": ""} {
		t.Run(name, func(t *testing.T) {
			a, srv := newArticleActions(t, func(w http.ResponseWriter, r *http.Request) {
				w.Header()["Content-Type"] = nil // no type at all unless set
				if ct != "" {
					w.Header().Set("Content-Type", ct)
				}
				_, _ = w.Write([]byte(goodPage()))
			})
			art, err := a.ReadArticle(context.Background(), srv.URL+"/x")
			require.NoError(t, err)
			require.False(t, art.NeedsBrowser)
			require.Contains(t, art.Text, para3)
		})
	}
}

func TestReadArticleATypelessResponseThatIsNotHTMLIsNotAnArticle(t *testing.T) {
	a, srv := newArticleActions(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header()["Content-Type"] = nil
		_, _ = w.Write([]byte("\x89PNG\r\n\x1a\n" + strings.Repeat("x", 600)))
	})
	art, err := a.ReadArticle(context.Background(), srv.URL+"/x")
	require.NoError(t, err)
	require.True(t, art.NeedsBrowser)
}
