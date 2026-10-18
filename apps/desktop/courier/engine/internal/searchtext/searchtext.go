// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package searchtext prepares text for the search index and turns what a person types into a query the index
// can always run.
//
// Every search table uses the tokenizer `unicode61 remove_diacritics 2 categories 'L* N* Co M*'`. Text and
// queries both go through Normalize first. A query is never passed to FTS5 as written: Parse reads it as
// words and phrases, and MatchAll / MatchAny quote every one, so nothing a person types is ever FTS5 syntax.
package searchtext

import (
	"regexp"
	"slices"
	"strings"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

// MaxQueryRunes is how much of a query is read; the rest of a longer query is ignored.
const MaxQueryRunes = 500

// MaxTerms is how many words and phrases of a query are read; so are words past the 16th.
const MaxTerms = 16

// MaxIndexRunes is how much of a message's text is indexed.
const MaxIndexRunes = 16384

// Scripts written without spaces between words. Each of their characters is indexed as a word of its own, so
// a query can match inside what the writer thinks of as one word.
var noSpaceScripts = []*unicode.RangeTable{
	unicode.Han, unicode.Hiragana, unicode.Katakana, unicode.Hangul,
	unicode.Thai, unicode.Lao, unicode.Khmer, unicode.Myanmar,
}

// The tokenizer's `categories 'L* N* Co M*'`: everything else separates words.
var tokenCategories = []*unicode.RangeTable{unicode.L, unicode.N, unicode.M, unicode.Co}

func noSpace(r rune) bool   { return r >= 0x0e00 && unicode.In(r, noSpaceScripts...) }
func tokenRune(r rune) bool { return unicode.In(r, tokenCategories...) }

// Normalize is what both the index and a query see: NFKC, then a space either side of every character of a
// script written without spaces (Han, Hiragana, Katakana, Hangul, Thai, Lao, Khmer, Myanmar). A space is only
// added between two characters that are not already whitespace, so none is added at either end.
//
// Emoji and other symbols become a space, and the marks that only choose how an emoji looks (variation
// selectors, the keycap) are dropped. Words would treat them as separators anyway, but SQLite's tokenizer
// tables predate most emoji and count those as letters: without this, "thanks🥺" would be indexed as one
// word that "thanks" doesn't find, and "❤️" would search for its variation selector. Invalid UTF-8 becomes
// a space too.
func Normalize(s string) string {
	s = norm.NFKC.String(s)
	var b strings.Builder
	b.Grow(len(s))
	prev := rune(-1) // nothing written yet
	for _, r := range s {
		switch {
		case presentation(r):
			continue
		case r == utf8.RuneError || unicode.Is(unicode.S, r) || unknown(r):
			if prev < 0 || unicode.IsSpace(prev) {
				continue
			}
			r = ' '
		case prev >= 0 && !unicode.IsSpace(prev) && !unicode.IsSpace(r) && (noSpace(r) || noSpace(prev)):
			b.WriteByte(' ')
		}
		b.WriteRune(r)
		prev = r
	}
	return b.String()
}

// unknown is a code point Go's Unicode tables have no character for. Go 1.26 ships Unicode 15.0, so emoji
// from Unicode 16 on (U+1FAE9 🫩) are unknown to it, and SQLite's tokenizer counts every code point it doesn't
// know as a letter: left in place, "thanks🫩" would be indexed as one word. Made a separator, it is not
// searchable, like other emoji. The cost: letters of scripts newer than Go's tables aren't searchable either
// until a Go update brings the newer tables.
//
// The control categories are named one by one: Go's unicode.C also covers the code points with no character,
// so testing it would find nothing unknown.
func unknown(r rune) bool {
	return !unicode.In(r, unicode.L, unicode.M, unicode.N, unicode.P, unicode.S, unicode.Z,
		unicode.Cc, unicode.Cf, unicode.Co, unicode.Cs)
}

// presentation is a mark that only changes how the character before it is drawn: the variation selectors
// (U+FE0F asks for an emoji) and the keycap of 1️⃣.
func presentation(r rune) bool {
	return (r >= 0xfe00 && r <= 0xfe0f) || (r >= 0xe0100 && r <= 0xe01ef) || r == 0x20e3
}

// Words splits normalised text into the tokens the FTS5 tokenizer makes: runs of letters, numbers, marks and
// private-use characters, case-folded with accents removed. Snippets and phrases use it.
//
// The fold is the tokenizer's, not a general one: a Latin letter with accents becomes its plain letter (é, ǖ
// and ẫ all lose theirs), and a combining accent the tokenizer removes is dropped, but the marks of other
// scripts stay, because the index keeps them: a Hindi or Thai word without its vowel signs is a different
// word to the index. TestWordsMirrorTheTokenizer checks this against SQLite.
func Words(s string) []string {
	var words []string
	var b strings.Builder
	for _, r := range s {
		if tokenRune(r) {
			fold(&b, r)
			continue
		}
		if b.Len() > 0 {
			words = append(words, b.String())
			b.Reset()
		}
	}
	if b.Len() > 0 {
		words = append(words, b.String())
	}
	return words
}

// fold writes r as the tokenizer stores it.
func fold(b *strings.Builder, r rune) {
	if r < utf8.RuneSelf {
		b.WriteRune(unicode.ToLower(r))
		return
	}
	switch r {
	case 'ς':
		r = 'σ' // the tokenizer folds final sigma
	case 0x0345:
		r = 'ι' // and the combining iota subscript
	}
	r = unicode.ToLower(r)
	if ftsDiacritic(r) {
		return
	}
	if base, ok := plainLatin(r); ok {
		r = base
	}
	b.WriteRune(r)
}

// plainLatin is the ASCII letter under a Latin letter with accents: é → e, ǖ → u. The tokenizer's
// remove_diacritics 2 maps exactly these.
func plainLatin(r rune) (rune, bool) {
	var buf [32]byte
	d := norm.NFKD.AppendString(buf[:0], string(r))
	if len(d) < 2 || d[0] >= utf8.RuneSelf || !unicode.IsLetter(rune(d[0])) {
		return 0, false
	}
	for _, m := range string(d[1:]) {
		if !unicode.Is(unicode.Mn, m) {
			return 0, false
		}
	}
	return unicode.ToLower(rune(d[0])), true
}

// ftsDiacritic is SQLite's sqlite3Fts5UnicodeIsdiacritic: the combining accents (U+0300–U+0331) the
// tokenizer drops when remove_diacritics is set. It keeps the rest of that block.
func ftsDiacritic(r rune) bool {
	const mask0, mask1 = 0x08029FDF, 0x000361F8
	switch {
	case r < 0x300 || r > 0x331:
		return false
	case r < 0x320:
		return mask0&(1<<(r-0x300)) != 0
	default:
		return mask1&(1<<(r-0x320)) != 0
	}
}

// Term is one word or phrase of a query.
type Term struct {
	Text   string // normalised; for a phrase, its words separated by single spaces
	Phrase bool   // in quotes, or a word that splits into several tokens, or a run of a script without spaces
	Prefix bool   // the last word, still being typed
}

// Double quotes start and end a phrase. The curly ones are the same mark after macOS's smart quotes; the
// full-width one becomes '"' under NFKC.
func quote(r rune) bool { return r == '"' || r == '“' || r == '”' || r == '„' }

// Brackets end a word as a space does, so "NEAR(a b)" is three words. Other punctuation inside a word makes
// it a phrase of its parts, as the tokenizer splits it: "e-mail", "3.14", "o'clock", "10:30".
func wordEnd(r rune) bool {
	return unicode.IsSpace(r) || quote(r) || unicode.In(r, unicode.Ps, unicode.Pe)
}

// Parse reads what a person typed as at most MaxTerms words and phrases, from its first MaxQueryRunes
// characters. It is nil when nothing searchable is left (emoji or punctuation only).
//
// A phrase is in double quotes (an unclosed quote runs to the end), or a word the tokenizer would split, or a
// run of a script written without spaces. The last term matches as a prefix while it is still being typed:
// when it is a word (not a phrase) of at least 2 characters that runs to the end of the query, so the query
// doesn't end in whitespace or a closing quote, and no word after it was dropped.
func Parse(q string) []Term {
	q = strings.ToValidUTF8(q, "\uFFFD")
	if utf8.RuneCountInString(q) > MaxQueryRunes {
		n := 0
		for i := range q {
			if n == MaxQueryRunes {
				q = q[:i]
				break
			}
			n++
		}
	}
	rs := []rune(norm.NFKC.String(q))

	var terms []Term
	add := func(part []rune, quoted, atEnd bool) {
		words := Words(Normalize(string(part)))
		if len(words) == 0 || len(terms) == MaxTerms {
			return
		}
		t := Term{Text: strings.Join(words, " ")}
		t.Phrase = quoted || len(words) > 1 || strings.ContainsFunc(t.Text, noSpace)
		t.Prefix = atEnd && !t.Phrase && utf8.RuneCountInString(t.Text) >= 2
		terms = append(terms, t)
	}
	for i := 0; i < len(rs); {
		switch r := rs[i]; {
		case quote(r):
			j := i + 1
			for j < len(rs) && !quote(rs[j]) {
				j++
			}
			add(rs[i+1:j], true, false)
			i = j + 1
		case wordEnd(r):
			i++
		default:
			j := i
			for j < len(rs) && !wordEnd(rs[j]) {
				j++
			}
			add(rs[i:j], false, j == len(rs))
			i = j
		}
	}
	return terms
}

// Letters counts the letters across terms, so the caller can ask for enough of them before searching
// messages. A character of a script written without spaces counts as 2: one is already a word.
func Letters(terms []Term) int {
	n := 0
	for _, t := range terms {
		for _, r := range t.Text {
			switch {
			case noSpace(r):
				n += 2
			case tokenRune(r):
				n++
			}
		}
	}
	return n
}

var columnName = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// MatchAll is an FTS5 expression over column that every term must match: {column}: ("a" AND "b c" AND "d"*).
// Every term is double-quoted with inner quotes doubled, and a prefix is "abc"*; it is "" when terms is
// empty. Nothing else of FTS5's syntax ever comes from the person. column is the program's own column name.
func MatchAll(column string, terms []Term) string { return match(column, terms, " AND ") }

// MatchAny is MatchAll for messages that match any of the terms: {column}: ("a" OR "b").
func MatchAny(column string, terms []Term) string { return match(column, terms, " OR ") }

func match(column string, terms []Term, op string) string {
	if !columnName.MatchString(column) {
		panic("searchtext: bad column name " + column)
	}
	var parts []string
	for _, t := range terms {
		// Re-split the text, so a term built by hand is as safe as one from Parse.
		words := Words(Normalize(t.Text))
		if len(words) == 0 {
			continue
		}
		p := `"` + strings.ReplaceAll(strings.Join(words, " "), `"`, `""`) + `"`
		if t.Prefix && !t.Phrase && len(words) == 1 {
			p += "*"
		}
		parts = append(parts, p)
	}
	if len(parts) == 0 {
		return ""
	}
	return "{" + column + "}: (" + strings.Join(parts, op) + ")"
}

// Range is part of a snippet in UTF-16 code units, as AppKit's NSRange counts them.
type Range struct{ Start, Length int }

// A word of a text and where it is, in runes. The words of one run of text share its place.
type span struct {
	word       string
	start, end int
}

// spans finds the words of text as the index sees them, each with where it is in the text as written, so a
// match on the folded words can be shown on the original characters.
func spans(rs []rune) []span {
	var out []span
	for i := 0; i < len(rs); {
		if !wordRune(rs[i]) {
			i++
			continue
		}
		// One character of a script without spaces is a word (with any marks after it that NFKC may
		// compose into it); anything else runs to the next separator or such character.
		j := i + 1
		if noSpace(rs[i]) {
			for j < len(rs) && unicode.In(rs[j], unicode.Mn, unicode.Me) && !noSpace(rs[j]) {
				j++
			}
		} else {
			for j < len(rs) && wordRune(rs[j]) && !noSpace(rs[j]) {
				j++
			}
		}
		for _, w := range Words(Normalize(string(rs[i:j]))) {
			out = append(out, span{word: w, start: i, end: j})
		}
		i = j
	}
	return out
}

// wordRune is a character that is, or under NFKC becomes, part of a word: "ⓐ" is a symbol, but NFKC makes
// it "a".
func wordRune(r rune) bool {
	if tokenRune(r) {
		return true
	}
	if r < utf8.RuneSelf {
		return false
	}
	return strings.ContainsFunc(norm.NFKC.String(string(r)), tokenRune)
}

// snapRunes is how far a cut moves to land on a space rather than inside a word.
const snapRunes = 16

// Snippet is at most maxRunes of text around the first match (the start of text when none), with "…" where it
// was cut, and the ranges of every matched word or phrase in it, in order. A prefix term matches the start of
// a word. maxRunes of 0 or less means the whole text; below 3 it is 3, room for one character and both cuts.
func Snippet(text string, terms []Term, maxRunes int) (string, []Range) {
	rs := []rune(text) // invalid UTF-8 becomes U+FFFD, a byte at a time, as encoding/json sends it
	words := spans(rs)

	type hit struct{ start, end int }
	var hits []hit
	for _, t := range terms {
		tw := Words(Normalize(t.Text))
		if len(tw) == 0 {
			continue
		}
		prefix := t.Prefix && !t.Phrase && len(tw) == 1
		for i := 0; i+len(tw) <= len(words); i++ {
			matched := true
			for j, w := range tw {
				if got := words[i+j].word; got != w && (!prefix || !strings.HasPrefix(got, w)) {
					matched = false
					break
				}
			}
			if matched {
				hits = append(hits, hit{words[i].start, words[i+len(tw)-1].end})
			}
		}
	}
	slices.SortFunc(hits, func(a, b hit) int {
		if a.start != b.start {
			return a.start - b.start
		}
		return b.end - a.end
	})
	merged := hits[:0]
	for _, h := range hits {
		if n := len(merged); n > 0 && h.start < merged[n-1].end {
			merged[n-1].end = max(merged[n-1].end, h.end)
			continue
		}
		merged = append(merged, h)
	}

	start, end := 0, len(rs)
	if maxRunes > 0 {
		maxRunes = max(maxRunes, 3)
	}
	if maxRunes > 0 && len(rs) > maxRunes {
		from, to := 0, 0
		if len(merged) > 0 {
			from, to = merged[0].start, merged[0].end
		}
		start, end = window(rs, from, to, maxRunes)
	}

	var b strings.Builder
	offset := 0
	if start > 0 {
		b.WriteString("…")
		offset = 1
	}
	b.WriteString(string(rs[start:end]))
	if end < len(rs) {
		b.WriteString("…")
	}

	var ranges []Range
	units := offset
	at := start
	for _, h := range merged {
		h.start, h.end = max(h.start, start), min(h.end, end)
		if h.start >= h.end {
			continue
		}
		units += utf16Len(rs[at:h.start])
		n := utf16Len(rs[h.start:h.end])
		ranges = append(ranges, Range{Start: units, Length: n})
		units += n
		at = h.end
	}
	return b.String(), ranges
}

// window picks the runes [start, end) of rs to show, at most maxRunes with the "…" of each cut end, around
// the match [from, to). With no match, from and to are 0, which shows the start.
func window(rs []rune, from, to, maxRunes int) (start, end int) {
	n := len(rs)
	room := maxRunes - 2 // cut at both ends
	start = (from+to)/2 - room/2
	switch {
	case start <= 0 || to == 0:
		start, end = 0, maxRunes-1
	case start+room >= n:
		start, end = n-(maxRunes-1), n
	default:
		end = start + room
	}
	// Move a cut back onto a space, never into the match.
	if start > 0 {
		for i := start; i < min(from, start+snapRunes); i++ {
			if unicode.IsSpace(rs[i]) {
				start = i + 1
				break
			}
		}
	}
	if end < n {
		for i := end - 1; i >= max(to, end-snapRunes); i-- {
			if unicode.IsSpace(rs[i]) {
				end = i
				break
			}
		}
	}
	return start, end
}

func utf16Len(rs []rune) int {
	n := 0
	for _, r := range rs {
		n += utf16.RuneLen(r)
	}
	return n
}
