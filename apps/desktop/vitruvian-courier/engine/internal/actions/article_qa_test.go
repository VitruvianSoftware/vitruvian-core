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

// QA checks for article extraction: a character set declared only in a <meta>, a Shift_JIS page, structured data
// next to a page shell, and content types that aren't pages.

func TestExtractArticleCharsetDeclaredOnlyInMeta(t *testing.T) {
	// No charset in the Content-Type header; Windows-1252 curly quotes (0x93 0x94) and an e-acute, declared in the meta only.
	body := strings.Repeat("The \x93caf\xe9\x94 on the corner opened a second shop this week, which the owner said was a surprise to everyone. ", 4)
	page := "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=windows-1252\"></head><body><article><p>" + body + "</p></article></body></html>"
	a := ExtractArticle([]byte(page), "text/html", mustURL(t, "https://example.fr/a"))
	require.Contains(t, a.Text, "“café”")
	require.NotContains(t, a.Text, "�")
}

func TestExtractArticleShiftJIS(t *testing.T) {
	// "日本語のニュース記事です。" in Shift_JIS, repeated, declared by the header only.
	sjis := "\x93\xfa\x96\x7b\x8c\xea\x82\xcc\x83\x6a\x83\x85\x81\x5b\x83\x58\x8b\x4c\x8e\x96\x82\xc5\x82\xb7\x81\x42"
	page := "<html><body><article><p>" + strings.Repeat(sjis, 12) + "</p></article></body></html>"
	a := ExtractArticle([]byte(page), "text/html; charset=Shift_JIS", mustURL(t, "https://example.jp/a"))
	require.Contains(t, a.Text, "日本語のニュース記事です。")
}

func TestExtractArticleJSONLDBodyBeatsAScriptBuiltShell(t *testing.T) {
	long := strings.Repeat(para1+" ", 8)
	page := `<html><head><script type="application/ld+json">{"@type":"NewsArticle","headline":"H","articleBody":"` + long + `"}</script></head>
<body><div id="root"><p>Loading…</p></div></body></html>`
	a := ExtractArticle([]byte(page), "text/html", mustURL(t, "https://example.com/a"))
	require.False(t, a.NeedsBrowser)
	require.Contains(t, a.Text, para1)
}

func TestReadArticleRejectsContentTypesThatAreNotPages(t *testing.T) {
	for _, ct := range []string{"application/json", "text/plain", "image/png", "application/octet-stream"} {
		t.Run(ct, func(t *testing.T) {
			a, srv := newArticleActions(t, func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", ct)
				_, _ = w.Write([]byte(goodPage()))
			})
			art, err := a.ReadArticle(context.Background(), srv.URL+"/x")
			require.NoError(t, err)
			require.True(t, art.NeedsBrowser)
			require.Empty(t, art.Text)
		})
	}
}
