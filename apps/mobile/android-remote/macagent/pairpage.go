// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package main

import (
	"fmt"
	"html"
	"net/http"
	"net/url"
	"regexp"
	"strings"
)

// GET /pair?code=482917 -- the page a pairing QR code opens.
//
// The Mac's menu bar app shows a QR code holding
// http://<this Mac's Tailscale address>:7411/pair?code=NNNNNN. A QR has to
// hold a web link rather than a vitruvian-remote:// one, because Pixel's
// camera does not open custom-scheme links (Google issue 321657269): it shows
// them as text. Any camera opens a web link, and this page turns it into the
// app link with one tap.
//
// Read tier, no token, and it reveals nothing the QR did not already say:
// the code comes from the query, the address is the Host the phone itself
// used, and the name is this Mac's short hostname. It never checks the code
// against the open pairing window -- that would make it an oracle for
// guessing codes. POST /v1/pair stays the only place a code is judged.

var (
	pairCodeRE = regexp.MustCompile(`^[0-9]{6}$`)
	// host[:port] with nothing a link could be smuggled through: no scheme,
	// path, userinfo, query or whitespace.
	pairHostRE = regexp.MustCompile(`^[A-Za-z0-9.-]{1,253}(:[0-9]{1,5})?$`)
	pairNameRE = regexp.MustCompile(`[^A-Za-z0-9-]`)
)

// pairAppLink is the vitruvian-remote://pair link the phone app parses
// (DeepLink.pairing in Wire.kt). Shared fixture: the Kotlin test parses the
// exact string pairpage_test.go expects, so the two sides cannot drift.
func pairAppLink(host, code, name string) string {
	q := url.Values{}
	q.Set("url", "http://"+host)
	q.Set("code", code)
	if name != "" {
		q.Set("name", name)
	}
	// url.Values.Encode sorts keys: code, name, url.
	return "vitruvian-remote://pair?" + q.Encode()
}

// pairIntentLink is the same link as a Chrome intent: Chrome only hands a
// custom scheme to an app from a user gesture, and an intent: URL is the form
// it opens most reliably. package= keeps it from going to any other app.
func pairIntentLink(appLink string) string {
	rest := strings.TrimPrefix(appLink, "vitruvian-remote://")
	return "intent://" + rest + "#Intent;scheme=vitruvian-remote;package=dev.vitruvian.remote;end"
}

// pairName is the Mac's short hostname made safe for a link and a label.
func pairName(hostname string) string {
	n := pairNameRE.ReplaceAllString(strings.TrimSpace(hostname), "")
	if len(n) > 32 {
		n = n[:32]
	}
	return n
}

func (srv *server) pairPage(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	if !pairCodeRE.MatchString(code) {
		writeError(w, http.StatusBadRequest, "code must be six digits")
		return
	}
	if !pairHostRE.MatchString(r.Host) {
		writeError(w, http.StatusBadRequest, "unusable Host header")
		return
	}
	name := pairName(srv.sampler.Host().Hostname)
	app := pairAppLink(r.Host, code, name)
	label := name
	if label == "" {
		label = "this Mac"
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	// Nothing on this page may load or run anything else.
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'")
	w.Header().Set("Referrer-Policy", "no-referrer")
	_, _ = fmt.Fprintf(
		w, pairPageHTML,
		html.EscapeString(label),
		html.EscapeString(pairIntentLink(app)),
		html.EscapeString(label),
		html.EscapeString(code[:3]+" "+code[3:]),
		html.EscapeString(app),
	)
}

const pairPageHTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pair with %s</title>
<style>
:root{color-scheme:light dark;--bg:#f6f5f2;--fg:#1d1d1f;--dim:#6b6b70;--accent:#343a5c}
@media (prefers-color-scheme:dark){:root{--bg:#141418;--fg:#f2f2f4;--dim:#a0a0a8;--accent:#8e97d6}}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:var(--bg);color:var(--fg);font:16px/1.45 system-ui,sans-serif}
main{max-width:22rem;padding:2rem 1.25rem;text-align:center}
h1{font-size:1.35rem;margin:0 0 .5rem}
p{color:var(--dim);margin:.5rem 0 1.5rem}
a.open{display:block;padding:.95rem 1rem;border-radius:.75rem;background:var(--accent);color:#fff;text-decoration:none;font-weight:600}
code{font-size:1.1rem;letter-spacing:.12em}
small{display:block;margin-top:1.25rem;color:var(--dim)}
small a{color:var(--dim)}
</style></head>
<body><main>
<a class="open" href="%s">Open in Vitruvian Remote</a>
<h1 style="margin-top:1.5rem">Pair this phone with %s</h1>
<p>The app will ask you to confirm. Code <code>%s</code>, valid for five minutes.</p>
<small>Button does nothing? <a href="%s">Try the direct link</a>, or install the Vitruvian Remote app first.</small>
</main></body></html>
`
