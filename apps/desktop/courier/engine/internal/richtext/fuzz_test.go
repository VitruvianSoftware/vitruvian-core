// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package richtext

import (
	"context"
	"fmt"
	"html"
	"math/rand/v2"
	"slices"
	"strings"
	"testing"
	"unicode"
	"unicode/utf16"

	"github.com/stretchr/testify/assert"
	"maunium.net/go/mautrix/format"
)

// The addresses and users the fuzzer picks from: safe ones, and ones Check must refuse.
var (
	fuzzURLs  = []string{"https://x.test", "https://x.test/a_b", "mailto:ana@x.test", "http://x.test/?q=\"<>'&", "javascript:alert(1)", "https:x", "", "HTTPS://X.TEST/%22"}
	fuzzUsers = []string{"@ana:x.test", "@room", "", "@q\"<>&':x.test", "ana", "@bo:x.test"}
)

// fuzzEntities reads ranges from bytes, six per range: kind, offset (2 bytes), length (2 bytes) and a byte that
// picks the address or user. Its top bit keeps the raw offset and length; otherwise they are folded into the
// text, so most ranges fit and Render's real paths run, not only Check's refusals.
func fuzzEntities(text string, spec []byte) []Entity {
	n16 := 0
	for _, r := range text {
		n16 += utf16.RuneLen(r)
	}
	var ents []Entity
	for len(spec) >= 6 && len(ents) < MaxEntities+2 {
		b := spec[:6]
		spec = spec[6:]
		kind := Kind("underline")
		if i := int(b[0]) % (len(Kinds) + 1); i < len(Kinds) {
			kind = Kinds[i]
		}
		off, length := int(b[1])|int(b[2])<<8, int(b[3])|int(b[4])<<8
		if b[5]&0x80 == 0 {
			off %= n16 + 1
			length %= n16 - off + 1
		}
		ents = append(ents, Entity{
			Kind: kind, Offset: off, Length: length,
			URL: fuzzURLs[int(b[5]&0x7f)%len(fuzzURLs)], UserID: fuzzUsers[int(b[5]&0x7f)%len(fuzzUsers)],
		})
	}
	return ents
}

// seedSpec writes a case's ranges in fuzzEntities' form, with raw offsets.
func seedSpec(ents []Entity) []byte {
	var spec []byte
	for _, e := range ents {
		pick := 0
		for i, u := range fuzzURLs {
			if u == e.URL && e.Kind == Link {
				pick = i
			}
		}
		for i, u := range fuzzUsers {
			if u == e.UserID && e.Kind == Mention {
				pick = i
			}
		}
		spec = append(spec, byte(slices.Index(Kinds, e.Kind)), byte(e.Offset), byte(e.Offset>>8),
			byte(e.Length), byte(e.Length>>8), 0x80|byte(pick))
	}
	return spec
}

func keepMask(mask uint16) func(Kind) bool {
	return func(k Kind) bool {
		i := slices.Index(Kinds, k)
		return i >= 0 && mask&(1<<i) != 0
	}
}

// FuzzRender is Review Focus 4 over random input. Whatever the text and ranges, Render returns; the body
// doesn't depend on what the chat keeps; the HTML uses only Courier's tags, balanced, with every attribute
// value escaped and every link to a safe scheme; stripping its tags gives back the text exactly; reading it
// with the documented plain forms gives the body; and mautrix's own parser, which the bridges use, reads the
// same characters. The seeds are the shared cases.
func FuzzRender(f *testing.F) {
	for _, c := range readCases(f) {
		mask := uint16(0)
		for _, k := range c.Keep {
			mask |= 1 << slices.Index(Kinds, k)
		}
		f.Add(c.Text, seedSpec(c.Entities), mask)
		f.Add(c.Text, seedSpec(c.Entities), uint16(0xffff))
	}
	f.Add("a\x00b\xff\r\n\n<&>\"'", []byte{0, 0, 0, 1, 0, 0x80}, uint16(0xffff))
	f.Fuzz(func(t *testing.T, text string, spec []byte, mask uint16) {
		checkRender(t, text, fuzzEntities(text, spec), keepMask(mask))
	})
}

// TestRenderRandomMessages does what the fuzzer's blind mutation rarely does: messages of many lines with
// emoji, right-to-left text and characters HTML escapes, and ranges that mostly fit, blocks on line boundaries
// among them. Each goes through FuzzRender's checks with a random set of kinds kept.
func TestRenderRandomMessages(t *testing.T) {
	pieces := []string{"a", "bc ", " ", "\n", "\n", "🎉", "שלום", "<b>", "&", "\"'", "\r", "https://x.test", "\x00"}
	rng := rand.New(rand.NewPCG(4, 3))
	accepted := 0
	const n = 20000
	for range n {
		var text strings.Builder
		for range rng.IntN(16) {
			text.WriteString(pieces[rng.IntN(len(pieces))])
		}
		s := text.String()
		// Range ends: rune boundaries, and line starts and ends for blocks.
		var bounds, lineStarts, lineEnds []int
		u := 0
		for i, r := range s {
			bounds = append(bounds, u)
			if i == 0 || s[i-1] == '\n' {
				lineStarts = append(lineStarts, u)
			}
			if r == '\n' {
				lineEnds = append(lineEnds, u)
			}
			u += utf16.RuneLen(r)
		}
		bounds, lineEnds = append(bounds, u), append(lineEnds, u)
		if len(lineStarts) == 0 {
			lineStarts = []int{0}
		}
		var ents []Entity
		for range rng.IntN(6) {
			e := Entity{Kind: Kinds[rng.IntN(len(Kinds))], URL: fuzzURLs[rng.IntN(3)], UserID: fuzzUsers[rng.IntN(2)]}
			if isBlock(e.Kind) {
				e.Offset = lineStarts[rng.IntN(len(lineStarts))]
				end := lineEnds[rng.IntN(len(lineEnds))]
				e.Length = end - e.Offset
			} else {
				e.Offset = bounds[rng.IntN(len(bounds))]
				e.Length = bounds[rng.IntN(len(bounds))] - e.Offset
			}
			ents = append(ents, e)
		}
		if Check(s, ents) == nil {
			accepted++
		}
		checkRender(t, s, ents, keepMask(uint16(rng.Uint32())))
	}
	assert.Greater(t, accepted, n/5, "enough random messages pass Check to test Render's real paths")
}

// clean is the text as Render reads it: invalid UTF-8 and NUL become U+FFFD.
func clean(text string) string {
	return strings.ReplaceAll(string([]rune(text)), "\x00", "�")
}

func checkRender(t *testing.T, text string, ents []Entity, keep func(Kind) bool) {
	t.Helper()
	got := Render(text, ents, keep)
	all := Render(text, ents, keepAll)
	none := Render(text, ents, keepNone)
	if got.Body != all.Body || got.Body != none.Body {
		t.Fatalf("the body depends on what the chat keeps: %q / %q / %q", got.Body, all.Body, none.Body)
	}
	if none.HTML != "" || len(none.UserIDs) != 0 || none.Room {
		t.Fatalf("a chat that keeps nothing got HTML or mentions: %+v", none)
	}
	if len(ents) == 0 && got.Body != clean(text) {
		t.Fatalf("plain text changed: %q -> %q", text, got.Body)
	}
	if all.HTML == "" {
		if all.Body != clean(text) {
			t.Fatalf("no formatting survived, but the body has plain forms: %q -> %q", text, all.Body)
		}
	} else {
		nodes, err := parseCourierHTML(all.HTML)
		if err != nil {
			t.Fatalf("%v in %q", err, all.HTML)
		}
		if s := decode(nodes, raw); s != clean(text) {
			t.Fatalf("stripping the tags gives %q, not the text %q (HTML %q)", s, clean(text), all.HTML)
		}
	}
	if got.HTML == "" {
		return
	}
	nodes, err := parseCourierHTML(got.HTML)
	if err != nil {
		t.Fatalf("%v in %q", err, got.HTML)
	}
	if s := decode(nodes, plain); s != got.Body {
		t.Fatalf("the HTML reads %q, the body %q (HTML %q)", s, got.Body, got.HTML)
	}
	if a, b := squash(bridgeReads(got.HTML)), squash(decode(nodes, bridge)); a != b {
		t.Fatalf("mautrix reads %q, not %q (HTML %q)", a, b, got.HTML)
	}
}

// node is one element or text of Courier's HTML.
type node struct {
	tag      string // "" for text
	text     string
	href     string
	children []*node
}

var (
	inlineTags = map[string]bool{"strong": true, "em": true, "del": true, "code": true, "a": true, "span": true}
	blockTags  = map[string]bool{"pre": true, "blockquote": true, "ul": true, "ol": true}
	entityRefs = []string{"&amp;", "&lt;", "&gt;", "&#34;", "&#39;", "&#13;"}
)

// parseCourierHTML reads the HTML Render writes, and nothing looser: only Courier's tags and attributes, every
// tag closed in order, text escaped with only the six references Render writes, blocks only at the top level,
// lists holding only items, a code block holding only code holding only text, and no link inside a link.
func parseCourierHTML(s string) ([]*node, error) {
	root := &node{tag: "#root"}
	stack := []*node{root}
	for s != "" {
		top := stack[len(stack)-1]
		if s[0] != '<' {
			i := strings.IndexByte(s, '<')
			if i < 0 {
				i = len(s)
			}
			raw := s[:i]
			s = s[i:]
			// An HTML parser reads a raw carriage return as a line feed, and drops or replaces NUL.
			if strings.ContainsAny(raw, ">\"'\r\x00") {
				return nil, fmt.Errorf("unescaped text %q", raw)
			}
			for rest := raw; ; {
				j := strings.IndexByte(rest, '&')
				if j < 0 {
					break
				}
				if !slices.ContainsFunc(entityRefs, func(ref string) bool { return strings.HasPrefix(rest[j:], ref) }) {
					return nil, fmt.Errorf("stray & in %q", raw)
				}
				rest = rest[j+1:]
			}
			if top.tag == "ul" || top.tag == "ol" || top.tag == "pre" {
				return nil, fmt.Errorf("text directly inside <%s>", top.tag)
			}
			top.children = append(top.children, &node{text: html.UnescapeString(raw)})
			continue
		}
		end := strings.IndexByte(s, '>')
		if end < 0 {
			return nil, fmt.Errorf("unterminated tag %q", s)
		}
		tag := s[1:end]
		s = s[end+1:]
		if name, ok := strings.CutPrefix(tag, "/"); ok {
			if top.tag != name {
				return nil, fmt.Errorf("</%s> closes <%s>", name, top.tag)
			}
			stack = stack[:len(stack)-1]
			continue
		}
		n := &node{}
		switch {
		case tag == "br":
			n.tag = "br"
		case tag == "span data-mx-spoiler":
			n.tag = "span"
		case strings.HasPrefix(tag, `a href="`) && strings.HasSuffix(tag, `"`):
			raw := strings.TrimSuffix(strings.TrimPrefix(tag, `a href="`), `"`)
			if strings.ContainsAny(raw, "\"'<> ") {
				return nil, fmt.Errorf("unescaped href %q", raw)
			}
			n.tag, n.href = "a", html.UnescapeString(raw)
			lower := strings.ToLower(n.href)
			if !strings.HasPrefix(lower, "https://") && !strings.HasPrefix(lower, "http://") && !strings.HasPrefix(lower, "mailto:") {
				return nil, fmt.Errorf("unsafe href %q", n.href)
			}
		case inlineTags[tag] || blockTags[tag] || tag == "li":
			n.tag = tag
		default:
			return nil, fmt.Errorf("tag <%s>", tag)
		}
		parent := top.tag
		switch {
		case blockTags[n.tag] && parent != "#root":
			return nil, fmt.Errorf("<%s> inside <%s>", n.tag, parent)
		case (parent == "ul" || parent == "ol") != (n.tag == "li"):
			return nil, fmt.Errorf("<%s> inside <%s>", n.tag, parent)
		case parent == "pre" && n.tag != "code", parent == "code":
			return nil, fmt.Errorf("<%s> inside <%s>", n.tag, parent)
		case n.tag == "a" && slices.ContainsFunc(stack, func(x *node) bool { return x.tag == "a" }):
			return nil, fmt.Errorf("a link inside a link")
		}
		top.children = append(top.children, n)
		if n.tag != "br" {
			stack = append(stack, n)
		}
	}
	if len(stack) != 1 {
		return nil, fmt.Errorf("<%s> never closed", stack[len(stack)-1].tag)
	}
	return root.children, nil
}

// form is how decode reads the HTML.
type form int

const (
	raw    form = iota // the text alone, every tag stripped
	plain              // with the plain forms the body uses
	bridge             // as plain, but a quote loses its empty first and last lines, as mautrix trims a quote
)

// decode is the meaning of Courier's HTML as text. The plain forms the body uses are "• " and "1. " before list
// items, "> " before quoted lines, and " (address)" after a link whose text isn't its address. A block takes
// lines of its own: a line break separates it from what comes before and after, and a <br> straight after a
// block is that break.
func decode(nodes []*node, f form) string {
	var out strings.Builder
	pending := false
	for _, n := range nodes {
		switch {
		case blockTags[n.tag]:
			if pending || (out.Len() > 0 && !strings.HasSuffix(out.String(), "\n")) {
				out.WriteString("\n")
			}
			out.WriteString(decodeBlock(n, f))
			pending = true
		case n.tag == "br":
			out.WriteString("\n")
			pending = false
		default:
			s := decodeInline(n, f)
			if s == "" {
				continue
			}
			if pending {
				out.WriteString("\n")
				pending = false
			}
			out.WriteString(s)
		}
	}
	return out.String()
}

func decodeBlock(n *node, f form) string {
	switch n.tag {
	case "pre":
		return decodeInline(n, raw)
	case "blockquote":
		text := decode(n.children, f)
		if f == bridge {
			text = strings.TrimSpace(text)
		}
		lines := strings.Split(text, "\n")
		if f != raw {
			for i := range lines {
				lines[i] = "> " + lines[i]
			}
		}
		return strings.Join(lines, "\n")
	default:
		items := make([]string, len(n.children))
		for i, li := range n.children {
			items[i] = decode(li.children, f)
			if f != raw && n.tag == "ul" {
				items[i] = "• " + items[i]
			} else if f != raw {
				items[i] = fmt.Sprintf("%d. %s", i+1, items[i])
			}
		}
		return strings.Join(items, "\n")
	}
}

func decodeInline(n *node, f form) string {
	switch n.tag {
	case "":
		return n.text
	case "br":
		return "\n"
	}
	var s strings.Builder
	for _, c := range n.children {
		s.WriteString(decodeInline(c, f))
	}
	if n.tag == "a" && f != raw && !strings.HasPrefix(n.href, "https://matrix.to/#/") && !sameAsAddress(s.String(), n.href) {
		return s.String() + " (" + n.href + ")"
	}
	return s.String()
}

// bridgeReads is what a mautrix bridge's HTML parser reads from the HTML, with every mark left out: the bridges
// put back their own network's marks, which the comparison doesn't care about.
func bridgeReads(h string) string {
	same := func(s string, _ format.Context) string { return s }
	p := &format.HTMLParser{
		TabsToSpaces:            -1,
		Newline:                 "\n",
		BoldConverter:           same,
		ItalicConverter:         same,
		StrikethroughConverter:  same,
		MonospaceConverter:      same,
		SpoilerConverter:        func(text, _ string, _ format.Context) string { return text },
		MonospaceBlockConverter: func(code, _ string, _ format.Context) string { return code },
		PillConverter:           func(name, _, _ string, _ format.Context) string { return name },
		LinkConverter: func(text, href string, _ format.Context) string {
			if strings.HasPrefix(href, "https://matrix.to/#/") || sameAsAddress(text, href) {
				return text
			}
			return text + " (" + href + ")"
		},
	}
	return p.Parse(h, format.NewContext(context.Background()))
}

// squash drops whitespace, which mautrix collapses and trims, and writes its list bullet as Courier's.
func squash(s string) string {
	return strings.Map(func(r rune) rune {
		switch {
		case unicode.IsSpace(r):
			return -1
		case r == '*':
			return '•'
		}
		return r
	}, s)
}
