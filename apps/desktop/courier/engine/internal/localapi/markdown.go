// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi

import (
	"strings"
	"unicode"
	"unicode/utf16"

	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
)

// fromMarkdown turns the Markdown an MCP client writes into what message.send takes: plain text and formatting
// ranges. It knows a small, common subset: ```fenced code blocks```, `code`, **bold** (or __bold__), *italic* (or
// _italic_), ~~strikethrough~~ and [links](https://…) (http, https or mailto). Anything else, and any marker without
// its partner, stays as it was typed; a backslash keeps the punctuation after it as text. When the result would not
// pass richtext.Check, the text goes as it was written, with no formatting: a message is never refused for its
// Markdown.
func fromMarkdown(md string) (string, []richtext.Entity) {
	var out builder
	out.block(md)
	if len(out.ents) > 0 && richtext.Check(out.text.String(), out.ents) != nil {
		return md, nil
	}
	return out.text.String(), out.ents
}

type builder struct {
	text  strings.Builder
	units int // UTF-16 length of text
	ents  []richtext.Entity
}

func (b *builder) write(s string) {
	b.text.WriteString(s)
	for _, r := range s {
		b.units += utf16.RuneLen(r)
	}
}

func (b *builder) add(kind richtext.Kind, start int, url string) {
	if b.units > start {
		b.ents = append(b.ents, richtext.Entity{Kind: kind, Offset: start, Length: b.units - start, URL: url})
	}
}

// block handles fenced code blocks, which take whole lines, and hands everything between them to inline.
func (b *builder) block(md string) {
	for {
		open := fenceStart(md)
		if open < 0 {
			b.inline(md)
			return
		}
		rest := md[open+3:]
		nl := strings.IndexByte(rest, '\n')
		if nl < 0 {
			b.inline(md)
			return
		}
		body := rest[nl+1:]
		end := strings.Index(body, "\n```")
		if end < 0 {
			b.inline(md)
			return
		}
		after := body[end+4:]
		if eol := strings.IndexByte(after, '\n'); eol >= 0 {
			if strings.TrimSpace(after[:eol]) != "" {
				b.inline(md) // not a closing fence after all: leave it all as typed
				return
			}
			after = after[eol+1:]
		} else if strings.TrimSpace(after) != "" {
			b.inline(md)
			return
		} else {
			after = ""
		}
		b.inline(md[:open])
		start := b.units
		b.write(body[:end])
		b.add(richtext.Pre, start, "")
		if after != "" {
			b.write("\n")
		}
		md = after
	}
}

// fenceStart is where the first ``` that begins a line is, or -1.
func fenceStart(md string) int {
	for i := 0; ; {
		j := strings.Index(md[i:], "```")
		if j < 0 {
			return -1
		}
		j += i
		if j == 0 || md[j-1] == '\n' {
			return j
		}
		i = j + 3
	}
}

// inline handles the spans inside one stretch of text.
func (b *builder) inline(s string) {
	prev := byte(' ') // the source character before s[0]: emphasis only opens after a non-word character
	for len(s) > 0 {
		opens := !wordByte(prev)
		switch {
		case s[0] == '\\' && len(s) > 1 && strings.ContainsRune("\\`*_~[]()", rune(s[1])):
			b.write(s[1:2])
			prev = s[1]
			s = s[2:]
			continue
		case s[0] == '`':
			if end := strings.IndexByte(s[1:], '`'); end > 0 && !strings.Contains(s[1:1+end], "\n") {
				start := b.units
				b.write(s[1 : 1+end])
				b.add(richtext.Code, start, "")
				prev = '`'
				s = s[end+2:]
				continue
			}
		case opens && (strings.HasPrefix(s, "**") || strings.HasPrefix(s, "__")):
			if rest, ok := b.span(s, s[:2], richtext.Bold); ok {
				prev = s[len(s)-len(rest)-1]
				s = rest
				continue
			}
		case opens && strings.HasPrefix(s, "~~"):
			if rest, ok := b.span(s, "~~", richtext.Strike); ok {
				prev = s[len(s)-len(rest)-1]
				s = rest
				continue
			}
		case opens && (s[0] == '*' || s[0] == '_'):
			if rest, ok := b.span(s, s[:1], richtext.Italic); ok {
				prev = s[len(s)-len(rest)-1]
				s = rest
				continue
			}
		case s[0] == '[':
			if rest, ok := b.link(s); ok {
				prev = ')'
				s = rest
				continue
			}
		}
		// One character as typed. A run of word characters goes at once, so _ inside a word stays text.
		n := 1
		for n < len(s) && wordByte(s[n-1]) && wordByte(s[n]) {
			n++
		}
		if n == 1 {
			_, size := firstRune(s)
			n = size
		}
		b.write(s[:n])
		prev = s[n-1]
		s = s[n:]
	}
}

func wordByte(c byte) bool {
	return c >= 0x80 || c == '_' || unicode.IsLetter(rune(c)) || unicode.IsDigit(rune(c))
}

func firstRune(s string) (rune, int) {
	for i, r := range s {
		if i > 0 {
			return r, i
		}
	}
	return 0, len(s)
}

// span formats the text between marker and its partner on the same line as kind, if there is a partner and the
// span is not empty or padded with spaces.
func (b *builder) span(s, marker string, kind richtext.Kind) (string, bool) {
	body := s[len(marker):]
	end := strings.Index(body, marker)
	if end <= 0 { // no partner, or an empty span ("****")
		return "", false
	}
	inner := body[:end]
	if strings.Contains(inner, "\n") || strings.TrimSpace(inner) != inner {
		return "", false
	}
	if after := body[end+len(marker):]; after != "" && wordByte(after[0]) {
		return "", false // closes only before a non-word character: 2*3*4 is arithmetic
	}
	start := b.units
	b.inline(inner)
	b.add(kind, start, "")
	return body[end+len(marker):], true
}

// link formats [text](address) as a link, if address is http, https or mailto.
func (b *builder) link(s string) (string, bool) {
	close := strings.Index(s, "](")
	if close < 1 {
		return "", false
	}
	label := s[1:close]
	if strings.ContainsAny(label, "[]\n") {
		return "", false
	}
	rest := s[close+2:]
	end := strings.IndexByte(rest, ')')
	if end < 1 {
		return "", false
	}
	url := rest[:end]
	lower := strings.ToLower(url)
	if strings.ContainsAny(url, " \n") ||
		!(strings.HasPrefix(lower, "http://") || strings.HasPrefix(lower, "https://") || strings.HasPrefix(lower, "mailto:")) {
		return "", false
	}
	start := b.units
	b.write(label)
	b.add(richtext.Link, start, url)
	return rest[end+1:], true
}
