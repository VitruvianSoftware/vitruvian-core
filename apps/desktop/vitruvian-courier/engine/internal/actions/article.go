// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"unicode/utf8"

	"golang.org/x/net/html"
	"golang.org/x/net/html/atom"
	"golang.org/x/net/html/charset"
)

// This file reads the main text of an article for "Summarize" (E1). It fetches the page through the link-preview
// client (getLinkPreviewClient): https only, the same time limit, the same redirect cap, no private, loopback or
// tailnet address, and the dial checks the address it resolved (DNS rebinding). The one difference is the size cap:
// a link preview only needs a page's head, but an article's text sits well down the page, so the cap here is
// maxArticleHTMLBytes (still bounded) instead of maxLinkPreviewHTMLBytes.
const (
	// maxArticleHTMLBytes is the most page bytes read.
	maxArticleHTMLBytes = 1 << 20
	// MaxArticleTextRunes is the most text handed back: enough for any news article, small enough for a prompt.
	MaxArticleTextRunes = 20000
	// minArticleRunes is the text below which a page is "couldn't read it": a bare shell, a script-built page.
	minArticleRunes = 120
	// paywallFullTextRunes: a page that carries a paywall marker but holds this much text is readable in full (the
	// site sent the text), so it isn't treated as paywalled.
	paywallFullTextRunes = 3000
	// teaser*: a page with no marker whose text is a short lead (under teaserMaxRunes, and under twice the
	// description's length) next to a real description (teaserMinDescRunes or more) is a teaser behind a paywall.
	teaserMaxRunes     = 500
	teaserMinDescRunes = 140
	maxDescriptionRune = 600
)

// Article is the readable part of a page.
type Article struct {
	// URL is where the page ended up, after redirects.
	URL         string `json:"url"`
	Title       string `json:"title"`
	Site        string `json:"site"`
	Description string `json:"description"`
	// Text is the main text, paragraphs split by a blank line, at most MaxArticleTextRunes long. It may hold only
	// the teaser when Paywalled.
	Text string `json:"text"`
	// Paywalled says the site keeps the article behind a subscription or sign-in.
	Paywalled bool `json:"paywalled"`
	// NeedsBrowser says nothing readable came back: the page failed to load, wasn't a web page, or builds its text with
	// scripts.
	NeedsBrowser bool `json:"needs_browser"`
}

// ReadArticle fetches rawURL and extracts its main text. A page that can't be fetched or holds no text is not an
// error: it is an Article with NeedsBrowser set (or Paywalled, for a 402), because the app treats "couldn't read it"
// as one answer. An address that isn't an https link is ErrBadValue; a cancelled ctx is its own error.
func (a *Actions) ReadArticle(ctx context.Context, rawURL string) (*Article, error) {
	u, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || !strings.EqualFold(u.Scheme, "https") || u.Host == "" || u.User != nil {
		return nil, fmt.Errorf("%w: an article address is an https link", ErrBadValue)
	}
	fetchCtx, cancel := context.WithTimeout(ctx, linkPreviewTimeout)
	defer cancel()

	res := &Article{URL: u.String(), Site: siteFromHost(u.Hostname())}
	req, err := http.NewRequestWithContext(fetchCtx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("%w: an article address is an https link", ErrBadValue)
	}
	req.Header.Set("Accept", "text/html,application/xhtml+xml;q=0.9")
	req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; VitruvianCourier)")
	client := a.getLinkPreviewClient()
	// The client is made for this one read (each hop is dialled and checked anew): don't leave its connection open.
	defer client.CloseIdleConnections()
	resp, err := client.Do(req)
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		res.NeedsBrowser = true
		return res, nil
	}
	defer resp.Body.Close()
	if resp.Request != nil && resp.Request.URL != nil {
		res.URL = resp.Request.URL.String()
		res.Site = siteFromHost(resp.Request.URL.Hostname())
	}
	switch {
	case resp.StatusCode == http.StatusPaymentRequired:
		res.Paywalled = true
		return res, nil
	case resp.StatusCode < 200 || resp.StatusCode >= 300:
		res.NeedsBrowser = true
		return res, nil
	}
	if ct := strings.ToLower(resp.Header.Get("Content-Type")); ct != "" && !strings.Contains(ct, "html") && !strings.Contains(ct, "xml") {
		res.NeedsBrowser = true
		return res, nil
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxArticleHTMLBytes))
	if err != nil && len(raw) == 0 {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		res.NeedsBrowser = true
		return res, nil
	}
	finalURL := u
	if resp.Request != nil && resp.Request.URL != nil {
		finalURL = resp.Request.URL
	}
	return ExtractArticle(raw, resp.Header.Get("Content-Type"), finalURL), nil
}

// ExtractArticle reads the main text, title, site, description and paywall state out of a page's HTML. contentType is
// the response's Content-Type, for the page's character set ("" when unknown).
func ExtractArticle(raw []byte, contentType string, pageURL *url.URL) *Article {
	out := &Article{}
	if pageURL != nil {
		out.URL = pageURL.String()
		out.Site = siteFromHost(pageURL.Hostname())
	}
	var r io.Reader = strings.NewReader(string(raw))
	if cr, err := charset.NewReader(r, contentType); err == nil {
		r = cr
	}
	doc, err := html.Parse(r)
	if err != nil || doc == nil {
		out.NeedsBrowser = true
		return out
	}

	meta := collectMeta(doc)
	ld := collectJSONLD(doc)
	if v := firstNonEmpty(meta["og:site_name"], meta["application-name"]); v != "" {
		out.Site = v
	}
	out.Description = truncateRunes(collapseSpace(firstNonEmpty(meta["og:description"], meta["description"], meta["twitter:description"])), maxDescriptionRune)

	paras, root := pickArticleText(doc)
	text := joinParagraphs(paras, MaxArticleTextRunes)
	out.Title = collapseSpace(firstNonEmpty(meta["og:title"], meta["twitter:title"], headlineOf(root), headlineOf(doc), titleTag(doc)))

	marker := ld.notFree || meta["article:content_tier"] == "locked" || hasPaywallMarker(doc)
	textRunes := utf8.RuneCountInString(text)
	descRunes := utf8.RuneCountInString(out.Description)
	switch {
	case marker && textRunes < paywallFullTextRunes:
		out.Paywalled = true
	case !marker && textRunes < teaserMaxRunes && descRunes >= teaserMinDescRunes && textRunes < 2*descRunes && textRunes >= minArticleRunes:
		out.Paywalled = true
	}
	// A page whose text is only in its structured data (script-built pages often keep an articleBody there), unless
	// the site marks the article as not free: then the structured data is the paywalled part.
	if !out.Paywalled && textRunes < 600 && utf8.RuneCountInString(ld.articleBody) > textRunes {
		text = joinParagraphs(splitBodyParagraphs(ld.articleBody), MaxArticleTextRunes)
		textRunes = utf8.RuneCountInString(text)
	}
	out.Text = text
	if !out.Paywalled && textRunes < minArticleRunes {
		out.NeedsBrowser = true
	}
	return out
}

func siteFromHost(host string) string {
	host = strings.ToLower(host)
	return strings.TrimPrefix(host, "www.")
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v = strings.TrimSpace(v); v != "" {
			return v
		}
	}
	return ""
}

func truncateRunes(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return string(r[:n])
}

var spaceRE = regexp.MustCompile(`[\s\x{00a0}\x{200b}]+`)

func collapseSpace(s string) string {
	return strings.TrimSpace(spaceRE.ReplaceAllString(s, " "))
}

func attrOf(n *html.Node, key string) string {
	for _, a := range n.Attr {
		if a.Key == key {
			return a.Val
		}
	}
	return ""
}

func textOf(n *html.Node) string {
	var b strings.Builder
	var walk func(*html.Node)
	walk = func(c *html.Node) {
		if c.Type == html.TextNode {
			b.WriteString(c.Data)
		}
		for ch := c.FirstChild; ch != nil; ch = ch.NextSibling {
			walk(ch)
		}
	}
	walk(n)
	return b.String()
}

// collectMeta maps each <meta> name or property, lowercased, to its first content.
func collectMeta(doc *html.Node) map[string]string {
	out := map[string]string{}
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		if n.Type == html.ElementNode && n.DataAtom == atom.Meta {
			key := strings.ToLower(strings.TrimSpace(firstNonEmpty(attrOf(n, "property"), attrOf(n, "name"), attrOf(n, "itemprop"))))
			if _, seen := out[key]; key != "" && !seen {
				out[key] = strings.TrimSpace(attrOf(n, "content"))
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(doc)
	return out
}

func titleTag(doc *html.Node) string {
	var title string
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		if title != "" {
			return
		}
		if n.Type == html.ElementNode && n.DataAtom == atom.Title {
			title = textOf(n)
			return
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(doc)
	return title
}

// headlineOf is the first <h1> under n.
func headlineOf(n *html.Node) string {
	if n == nil {
		return ""
	}
	var found string
	var walk func(*html.Node)
	walk = func(c *html.Node) {
		if found != "" {
			return
		}
		if c.Type == html.ElementNode && c.DataAtom == atom.H1 {
			found = collapseSpace(textOf(c))
			return
		}
		for ch := c.FirstChild; ch != nil; ch = ch.NextSibling {
			walk(ch)
		}
	}
	walk(n)
	return found
}

// ldInfo is what the page's schema.org JSON-LD says.
type ldInfo struct {
	// notFree: isAccessibleForFree is false.
	notFree     bool
	articleBody string
}

func collectJSONLD(doc *html.Node) ldInfo {
	var info ldInfo
	var walkJSON func(v any)
	walkJSON = func(v any) {
		switch x := v.(type) {
		case map[string]any:
			if f, ok := x["isAccessibleForFree"]; ok && isFalse(f) {
				info.notFree = true
			}
			if s, ok := x["articleBody"].(string); ok && len(s) > len(info.articleBody) {
				info.articleBody = s
			}
			for _, child := range x {
				walkJSON(child)
			}
		case []any:
			for _, child := range x {
				walkJSON(child)
			}
		}
	}
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		if n.Type == html.ElementNode && n.DataAtom == atom.Script &&
			strings.Contains(strings.ToLower(attrOf(n, "type")), "ld+json") {
			var v any
			if json.Unmarshal([]byte(strings.TrimSpace(textOf(n))), &v) == nil {
				walkJSON(v)
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(doc)
	return info
}

func isFalse(v any) bool {
	switch x := v.(type) {
	case bool:
		return !x
	case string:
		return strings.EqualFold(strings.TrimSpace(x), "false")
	}
	return false
}

// paywallWords are class, id and data-* fragments sites use on the element that gates an article.
var paywallWords = []string{
	"paywall", "regwall", "subscribe-wall", "subscription-wall", "subscriber-only", "subscribers-only",
	"premium-gate", "article-gate", "content-gate", "tp-modal", "metered-wall",
}

func hasPaywallMarker(doc *html.Node) bool {
	var found bool
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		if found {
			return
		}
		if n.Type == html.ElementNode {
			if n.DataAtom == atom.Script || n.DataAtom == atom.Style {
				return
			}
			for _, key := range []string{"class", "id", "data-testid", "data-component", "data-paywall"} {
				v := strings.ToLower(attrOf(n, key))
				if v == "" {
					continue
				}
				if key == "data-paywall" {
					found = true
					return
				}
				for _, w := range paywallWords {
					if strings.Contains(v, w) {
						found = true
						return
					}
				}
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(doc)
	return found
}

// --- main text ---

// skipTags are never part of the text: page furniture, scripts, forms, embeds.
var skipTags = map[atom.Atom]bool{
	atom.Script: true, atom.Style: true, atom.Noscript: true, atom.Template: true, atom.Nav: true,
	atom.Footer: true, atom.Header: true, atom.Aside: true, atom.Form: true, atom.Iframe: true, atom.Svg: true,
	atom.Button: true, atom.Select: true, atom.Input: true, atom.Textarea: true, atom.Canvas: true,
	atom.Video: true, atom.Audio: true, atom.Object: true, atom.Embed: true, atom.Figure: true,
	atom.Head: true, atom.Dialog: true, atom.Menu: true,
}

// blockTags end one paragraph and start the next.
var blockTags = map[atom.Atom]bool{
	atom.P: true, atom.Div: true, atom.Section: true, atom.Article: true, atom.Main: true, atom.Li: true,
	atom.Ul: true, atom.Ol: true, atom.Blockquote: true, atom.Pre: true, atom.Table: true, atom.Tr: true,
	atom.Td: true, atom.Th: true, atom.Dd: true, atom.Dt: true, atom.Dl: true, atom.Address: true,
	atom.Details: true, atom.Summary: true, atom.Hr: true, atom.Figcaption: true, atom.Body: true,
	atom.H1: true, atom.H2: true, atom.H3: true, atom.H4: true, atom.H5: true, atom.H6: true,
}

// furnitureWords are whole words of a class or id that mark a block that isn't the story: comments, sharing,
// related links, ads, sign-up boxes. A word counts when it is the class's start (related, related-stories) or the
// whole class, so "has-sidebar" on a story's wrapper doesn't throw the story away.
var furnitureWords = []string{
	"comment", "comments", "share", "sharing", "social", "related", "recommended", "newsletter", "promo",
	"advert", "advertisement", "ads", "sidebar", "cookie", "consent", "subscribe", "signup", "breadcrumb",
	"breadcrumbs", "footer", "navigation", "nav", "popup", "modal", "trending", "recirc", "toolbar", "outbrain",
	"taboola", "sponsored", "byline", "bylines", "tags", "taglist", "topics",
}

func isFurnitureToken(tok string) bool {
	tok = strings.ToLower(tok)
	for _, w := range furnitureWords {
		if tok == w || strings.HasPrefix(tok, w+"-") || strings.HasPrefix(tok, w+"_") {
			return true
		}
	}
	return false
}

func looksLikeFurniture(n *html.Node) bool {
	for _, key := range []string{"class", "id"} {
		for _, tok := range strings.Fields(attrOf(n, key)) {
			if isFurnitureToken(tok) {
				return true
			}
		}
	}
	return false
}

func isHidden(n *html.Node) bool {
	for _, a := range n.Attr {
		switch a.Key {
		case "hidden":
			return true
		case "aria-hidden":
			if strings.EqualFold(a.Val, "true") {
				return true
			}
		case "style":
			s := strings.ToLower(strings.ReplaceAll(a.Val, " ", ""))
			if strings.Contains(s, "display:none") || strings.Contains(s, "visibility:hidden") {
				return true
			}
		}
	}
	return false
}

type paragraph struct {
	text     string
	linkLen  int
	heading  bool
	runeSize int
}

type collector struct {
	paras    []paragraph
	cur      strings.Builder
	curLink  int
	heading  bool
	rootRune int // the root's text length, to keep a "furniture" class on a wrapper from emptying the story
}

func (c *collector) flush() {
	text := collapseSpace(c.cur.String())
	if text != "" {
		c.paras = append(c.paras, paragraph{text: text, linkLen: c.curLink, heading: c.heading, runeSize: utf8.RuneCountInString(text)})
	}
	c.cur.Reset()
	c.curLink = 0
	c.heading = false
}

func (c *collector) walk(n *html.Node, inLink bool) {
	switch n.Type {
	case html.TextNode:
		c.cur.WriteString(n.Data)
		if inLink {
			c.curLink += utf8.RuneCountInString(strings.TrimSpace(n.Data))
		}
		return
	case html.ElementNode:
		if skipTags[n.DataAtom] || isHidden(n) {
			return
		}
		if looksLikeFurniture(n) && utf8.RuneCountInString(textOf(n))*2 < c.rootRune {
			return
		}
		if n.DataAtom == atom.Br {
			c.cur.WriteString(" ")
			return
		}
		block := blockTags[n.DataAtom]
		if block {
			c.flush()
			switch n.DataAtom {
			case atom.H2, atom.H3, atom.H4, atom.H5, atom.H6:
				c.heading = true
			case atom.H1:
				// The headline is read separately; its text isn't part of the body.
				return
			}
		}
		link := inLink || n.DataAtom == atom.A
		for ch := n.FirstChild; ch != nil; ch = ch.NextSibling {
			c.walk(ch, link)
		}
		if block {
			c.flush()
		}
		return
	}
	for ch := n.FirstChild; ch != nil; ch = ch.NextSibling {
		c.walk(ch, inLink)
	}
}

var boilerplateLineRE = regexp.MustCompile(`(?i)^(advertisement|advertisements|sponsored content|story continues below|story continues|read more:?|read next:?|related:?|related stories:?|share this|sign up for|subscribe to|subscribe now|click here|copyright|©|all rights reserved|follow us|listen to this|more from)\b`)

// keepParagraph says whether a paragraph is story text: not a link list, ad line or fragment.
func keepParagraph(p paragraph) bool {
	if p.heading {
		return p.runeSize >= 3 && p.runeSize <= 200
	}
	if p.runeSize < 25 {
		return false
	}
	if boilerplateLineRE.MatchString(p.text) && p.runeSize < 160 {
		return false
	}
	if p.runeSize < 200 && p.linkLen*2 > p.runeSize {
		return false
	}
	return true
}

func collectFrom(root *html.Node) []paragraph {
	c := &collector{rootRune: utf8.RuneCountInString(textOf(root))}
	for ch := root.FirstChild; ch != nil; ch = ch.NextSibling {
		c.walk(ch, false)
	}
	c.flush()
	var kept []paragraph
	for _, p := range c.paras {
		if !keepParagraph(p) {
			continue
		}
		if len(kept) > 0 && kept[len(kept)-1].text == p.text {
			continue
		}
		kept = append(kept, p)
	}
	// A heading with no paragraph under it is furniture ("Related", "More stories").
	var out []paragraph
	for i, p := range kept {
		if p.heading && (i == len(kept)-1 || kept[i+1].heading) {
			continue
		}
		out = append(out, p)
	}
	return out
}

func paragraphsRunes(ps []paragraph) int {
	n := 0
	for _, p := range ps {
		if !p.heading {
			n += p.runeSize
		}
	}
	return n
}

// pickArticleText chooses the page's main text: structured article markup first (itemprop=articleBody, <article>,
// <main>), the whole body as the last resort, and the longest when none is long enough. root is where it came from.
func pickArticleText(doc *html.Node) ([]paragraph, *html.Node) {
	var bodies, articles, mains []*html.Node
	var body *html.Node
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		if n.Type == html.ElementNode {
			switch {
			case strings.Contains(strings.ToLower(attrOf(n, "itemprop")), "articlebody"):
				bodies = append(bodies, n)
			case n.DataAtom == atom.Article:
				articles = append(articles, n)
			case n.DataAtom == atom.Main || strings.EqualFold(attrOf(n, "role"), "main"):
				mains = append(mains, n)
			case n.DataAtom == atom.Body && body == nil:
				body = n
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(doc)

	const enough = 600
	var best []paragraph
	var bestRoot *html.Node
	bestRunes := -1
	try := func(group []*html.Node) bool {
		for _, n := range group {
			ps := collectFrom(n)
			if r := paragraphsRunes(ps); r > bestRunes {
				best, bestRoot, bestRunes = ps, n, r
			}
		}
		return bestRunes >= enough
	}
	if try(bodies) || try(articles) || try(mains) {
		return best, bestRoot
	}
	if body != nil {
		try([]*html.Node{body})
	}
	return best, bestRoot
}

// joinParagraphs makes the text: paragraphs split by a blank line, stopping at max runes on a paragraph boundary
// (the first paragraph is cut if it alone is over).
func joinParagraphs(ps []paragraph, max int) string {
	var b strings.Builder
	size := 0
	for _, p := range ps {
		add := p.runeSize
		if size > 0 {
			add += 2
		}
		if size+add > max {
			if size == 0 {
				b.WriteString(truncateRunes(p.text, max))
			}
			break
		}
		if size > 0 {
			b.WriteString("\n\n")
		}
		b.WriteString(p.text)
		size += add
	}
	return b.String()
}

// splitBodyParagraphs turns a structured-data articleBody into paragraphs.
func splitBodyParagraphs(body string) []paragraph {
	var out []paragraph
	for _, part := range newlineRE.Split(body, -1) {
		part = collapseSpace(part)
		if part == "" {
			continue
		}
		out = append(out, paragraph{text: part, runeSize: utf8.RuneCountInString(part)})
	}
	return out
}

var newlineRE = regexp.MustCompile(`\n+`)
