// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package richtext turns what the composer sends, plain text plus formatting ranges, into the two forms a
// Matrix message carries: `formatted_body` HTML (`org.matrix.custom.html`) that the bridges convert into each
// network's own formatting, and a plain `body` that reads well with no formatting at all.
//
// Typed characters are never formatting. There is no Markdown: `*`, `_`, `#`, `<b>` and backticks are text,
// escaped in the HTML and left as they are in the body. Only the ranges make formatting.
//
// The HTML uses a small fixed set of tags: strong, em, del, code, pre, blockquote, ul, ol, li, a, span and br.
// Every character of the text is escaped, an attribute is only ever an escaped http, https or mailto address
// or a matrix.to link built from an escaped user ID, and a chat keeps only the kinds its bridge converts: a
// kind it doesn't keep falls back to its plain form inside the HTML, the same form the body uses.
//
// Nothing here logs, and no error carries the message's text.
package richtext

import (
	"cmp"
	"errors"
	"fmt"
	"html"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf16"
)

// Kind is a kind of formatting range, as the protocol names it.
type Kind string

const (
	Bold     Kind = "bold"
	Italic   Kind = "italic"
	Strike   Kind = "strikethrough"
	Code     Kind = "code"
	Pre      Kind = "pre"
	Quote    Kind = "blockquote"
	Bullets  Kind = "bullet_list"
	Numbered Kind = "ordered_list"
	Link     Kind = "link"
	Mention  Kind = "mention"
	Spoiler  Kind = "spoiler"
)

// Kinds is every kind, in the protocol's order.
var Kinds = []Kind{Bold, Italic, Strike, Code, Pre, Quote, Bullets, Numbered, Link, Mention, Spoiler}

// Entity is one formatting range.
type Entity struct {
	Kind   Kind   `json:"type"`
	Offset int    `json:"offset"`            // UTF-16 code units into the text, as the composer's NSRange counts them
	Length int    `json:"length"`            // UTF-16 code units
	URL    string `json:"url,omitempty"`     // link: http, https or mailto only
	UserID string `json:"user_id,omitempty"` // mention: a member's Matrix ID, or "@room"
}

// MaxEntities is the most ranges one message may carry.
const MaxEntities = 1000

// RoomMention is the user of a mention of everyone in the chat.
const RoomMention = "@room"

// ErrBadEntity is what Check returns, wrapped with the range's index and the reason.
var ErrBadEntity = errors.New("formatting that doesn't fit the text")

// Check reports the first range that doesn't fit the text: out of bounds, of length 0 or splitting a surrogate
// pair; an unknown kind; a link whose address isn't http, https or mailto, or a mention without a member's
// Matrix ID or @room; a link or mention across lines, or overlapping another link, mention or code; a code block,
// quote or list that doesn't start and end on line boundaries, or two of them on one line; more than
// MaxEntities ranges.
//
// A link, mention or code inside a code block passes; Render drops it.
func Check(text string, ents []Entity) error {
	_, err := parse(text, ents, true)
	return err
}

// Rendered is a message ready to send.
type Rendered struct {
	Body    string   // the plain body, with every range in its plain form
	HTML    string   // formatted_body; "" means send the body only
	UserIDs []string // the users the kept mentions name, each once, in order, for m.mentions
	Room    bool     // a kept @room mention
}

// Render keeps the kinds keep allows and drops the rest to their plain form. A mention's text is the "@Name" the
// composer inserted, so its plain form is that text.
//
// The body doesn't depend on keep: links read "text (address)" when the text isn't the address, list lines
// start "• " or "1. ", quoted lines "> ", and everything else is the text as typed. The HTML is "" when no kept
// range needs a tag. Ranges Check refuses are dropped, not trusted. Invalid UTF-8 and NUL, which Matrix HTML
// can't carry, become U+FFFD in both forms.
//
// A block (code block, quote, list) takes whole lines: the line breaks either side of it are the block's own,
// and are not written as <br>. A <br> straight after a block stands for the break after it, so an empty line
// next to a block is one more <br>. A list's empty line takes no marker and no item: the list ends before it and
// starts again after it, a numbered one with `start` set so the numbering carries on.
func Render(text string, ents []Entity, keep func(Kind) bool) Rendered {
	if keep == nil {
		keep = func(Kind) bool { return false }
	}
	d, _ := parse(text, ents, false)
	r := &renderer{doc: d, keep: keep}
	out := Rendered{Body: d.body()}
	h := r.html()
	if r.tagged {
		out.HTML = h
	}
	out.UserIDs, out.Room = r.users, r.room
	return out
}

// The inline styles, which may overlap anything, in the order they nest when they start together.
var styles = []Kind{Bold, Italic, Strike, Spoiler}

const noAtom = -1

type span struct{ start, end int } // runes

// atom is a link, mention or inline code: a range nothing else may cut, so its tag is never split.
type atom struct {
	kind   Kind
	url    string
	userID string
	span
}

// block is a code block, quote or list: whole lines, first to last.
type block struct {
	kind        Kind
	first, last int
}

type doc struct {
	runes   []rune
	lines   []span
	lineOf  []int   // rune → its line; a "\n" belongs to the line it ends
	blockOf []int   // line → its block, or -1
	blocks  []block // in the order Check accepted them
	number  []int   // line → its number in a numbered list
	style   []uint8 // rune → bit i set when styles[i] covers it
	atomOf  []int   // rune → its atom, or noAtom
	atoms   []atom  // links, mentions and code, which never overlap
}

// parse reads the ranges. Strict, it returns the first range that doesn't fit; otherwise it drops each one.
func parse(text string, ents []Entity, strict bool) (*doc, error) {
	runes := []rune(text) // invalid UTF-8 becomes U+FFFD here
	for i, r := range runes {
		if r == 0 {
			runes[i] = unicode.ReplacementChar
		}
	}
	d := &doc{runes: runes, style: make([]uint8, len(runes)), atomOf: make([]int, len(runes)), lineOf: make([]int, len(runes))}
	start := 0
	for i, r := range runes {
		d.lineOf[i] = len(d.lines)
		if r == '\n' {
			d.lines = append(d.lines, span{start, i})
			start = i + 1
		}
	}
	d.lines = append(d.lines, span{start, len(runes)})
	d.blockOf = slices.Repeat([]int{-1}, len(d.lines))
	for i := range d.atomOf {
		d.atomOf[i] = noAtom
	}

	// unit[u] is the rune that starts at UTF-16 offset u, or -1 inside a surrogate pair.
	units := 0
	for _, r := range runes {
		units += utf16.RuneLen(r)
	}
	unit := slices.Repeat([]int{-1}, units+1)
	u := 0
	for i, r := range runes {
		unit[u] = i
		u += utf16.RuneLen(r)
	}
	unit[units] = len(runes)

	if len(ents) > MaxEntities {
		if strict {
			return nil, fmt.Errorf("%w: more than %d ranges", ErrBadEntity, MaxEntities)
		}
		ents = ents[:MaxEntities]
	}

	// First every range on its own and the blocks, then the atoms (which a code block may drop), then styles.
	spans := make([]span, len(ents))
	ok := make([]bool, len(ents))
	for i, e := range ents {
		s, reason := d.fit(e, unit, units)
		if reason == "" && isBlock(e.Kind) {
			reason = d.addBlock(e.Kind, s)
		}
		if reason != "" {
			if strict {
				return nil, fmt.Errorf("%w: range %d: %s", ErrBadEntity, i, reason)
			}
			continue
		}
		spans[i], ok[i] = s, true
	}
	for i, e := range ents {
		if !ok[i] || !isAtom(e.Kind) || d.inCodeBlock(spans[i]) {
			continue
		}
		if slices.ContainsFunc(d.atomOf[spans[i].start:spans[i].end], func(a int) bool { return a != noAtom }) {
			if strict {
				return nil, fmt.Errorf("%w: range %d: a link, mention or code overlapping another", ErrBadEntity, i)
			}
			continue
		}
		for p := spans[i].start; p < spans[i].end; p++ {
			d.atomOf[p] = len(d.atoms)
		}
		d.atoms = append(d.atoms, atom{kind: e.Kind, url: e.URL, userID: e.UserID, span: spans[i]})
	}
	for i, e := range ents {
		if b := slices.Index(styles, e.Kind); ok[i] && b >= 0 {
			for p := spans[i].start; p < spans[i].end; p++ {
				d.style[p] |= 1 << b
			}
		}
	}
	// A list's empty lines take no number: the next item carries on from the last.
	d.number = make([]int, len(d.lines))
	for _, b := range d.blocks {
		if b.kind != Numbered {
			continue
		}
		n := 0
		for l := b.first; l <= b.last; l++ {
			if !d.listGap(l) {
				n++
				d.number[l] = n
			}
		}
	}
	// Ranges inside code or a code block are dropped: nothing styles code.
	for p := range d.style {
		if a := d.atomOf[p]; (a != noAtom && d.atoms[a].kind == Code) || d.inCodeBlock(span{p, p + 1}) {
			d.style[p] = 0
		}
	}
	return d, nil
}

// fit checks one range on its own and returns it in runes, or why it doesn't fit.
func (d *doc) fit(e Entity, unit []int, units int) (span, string) {
	switch {
	case !slices.Contains(Kinds, e.Kind):
		return span{}, "unknown kind"
	case e.Offset < 0 || e.Length < 0 || e.Offset > units || e.Length > units-e.Offset:
		return span{}, "out of bounds"
	case e.Length == 0:
		return span{}, "empty"
	case unit[e.Offset] < 0 || unit[e.Offset+e.Length] < 0:
		return span{}, "splits a character"
	}
	s := span{unit[e.Offset], unit[e.Offset+e.Length]}
	switch e.Kind {
	case Link:
		if !safeURL(e.URL) {
			return s, "a link address that isn't http, https or mailto"
		}
	case Mention:
		if !matrixUser(e.UserID) {
			return s, "a mention without a member's Matrix ID"
		}
	case Pre, Quote, Bullets, Numbered:
		if s.start > 0 && d.runes[s.start-1] != '\n' {
			return s, "a block that doesn't start a line"
		}
		if s.end < len(d.runes) && d.runes[s.end] != '\n' && d.runes[s.end-1] != '\n' {
			return s, "a block that doesn't end a line"
		}
	}
	if isAtom(e.Kind) && e.Kind != Code && slices.Contains(d.runes[s.start:s.end], '\n') {
		return s, "a link or mention across lines"
	}
	return s, ""
}

func (d *doc) addBlock(kind Kind, s span) string {
	b := block{kind: kind, first: d.lineOf[s.start], last: d.lineOf[s.end-1]}
	if slices.ContainsFunc(d.blockOf[b.first:b.last+1], func(i int) bool { return i >= 0 }) {
		return "two blocks on one line"
	}
	for l := b.first; l <= b.last; l++ {
		d.blockOf[l] = len(d.blocks)
	}
	d.blocks = append(d.blocks, b)
	return ""
}

func (d *doc) inCodeBlock(s span) bool {
	for l := d.lineOf[s.start]; l <= d.lineOf[s.end-1]; l++ {
		if b := d.blockOf[l]; b >= 0 && d.blocks[b].kind == Pre {
			return true
		}
	}
	return false
}

func isBlock(k Kind) bool { return k == Pre || k == Quote || k == Bullets || k == Numbered }
func isAtom(k Kind) bool  { return k == Link || k == Mention || k == Code }

// safeURL is an http or https address with a host, or a mailto address, with no space or control character.
func safeURL(s string) bool {
	if s == "" || strings.ContainsFunc(s, func(r rune) bool { return unicode.IsSpace(r) || unicode.IsControl(r) }) {
		return false
	}
	u, err := url.Parse(s)
	if err != nil {
		return false
	}
	switch strings.ToLower(u.Scheme) {
	case "http", "https":
		return u.Host != ""
	case "mailto":
		return u.Opaque != ""
	}
	return false
}

// matrixUser is @room or a user ID: "@", a localpart, ":", a server name, at most 255 bytes, no space or
// control character.
func matrixUser(s string) bool {
	if s == RoomMention {
		return true
	}
	local, server, found := strings.Cut(strings.TrimPrefix(s, "@"), ":")
	return strings.HasPrefix(s, "@") && found && local != "" && server != "" && len(s) <= 255 &&
		!strings.ContainsFunc(s, func(r rune) bool { return unicode.IsSpace(r) || unicode.IsControl(r) })
}

// sameAsAddress is a link whose text, without spaces at either end, is its address, or its address without the
// scheme: its plain form is just the text. mautrix's own HTML parser draws the line in the same place.
func sameAsAddress(text, address string) bool {
	text = strings.TrimSpace(text)
	if text == address {
		return true
	}
	for _, scheme := range []string{"mailto:", "http://", "https://"} {
		if rest, ok := strings.CutPrefix(address, scheme); ok && text == rest {
			return true
		}
	}
	return false
}

// listGap is an empty line inside a list. It takes no marker and no item: the list stops before it and goes
// on after it, with the numbering carried on.
func (d *doc) listGap(line int) bool {
	b := d.blockOf[line]
	return b >= 0 && (d.blocks[b].kind == Bullets || d.blocks[b].kind == Numbered) &&
		d.lines[line].start == d.lines[line].end
}

// prefix is the plain form a block gives its line.
func (d *doc) prefix(line int) string {
	b := d.blockOf[line]
	if b < 0 || d.listGap(line) {
		return ""
	}
	switch d.blocks[b].kind {
	case Quote:
		return "> "
	case Bullets:
		return "• "
	case Numbered:
		return strconv.Itoa(d.number[line]) + ". "
	}
	return ""
}

// linkSuffix is what the plain form adds after atom a when it is a link, or "".
func (d *doc) linkSuffix(a int) string {
	at := d.atoms[a]
	if at.kind != Link || sameAsAddress(string(d.runes[at.start:at.end]), at.url) {
		return ""
	}
	return " (" + at.url + ")"
}

func (d *doc) body() string {
	var b strings.Builder
	for l, line := range d.lines {
		if l > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(d.prefix(l))
		for p := line.start; p < line.end; p++ {
			b.WriteRune(d.runes[p])
			if a := d.atomOf[p]; a != noAtom && d.atoms[a].end == p+1 {
				b.WriteString(d.linkSuffix(a))
			}
		}
	}
	return b.String()
}

type renderer struct {
	*doc
	keep   func(Kind) bool
	b      strings.Builder
	tagged bool // a kept range wrote a tag; without one there is no HTML to send
	users  []string
	room   bool
}

// escape writes text for HTML: & < > " ' as references, and a carriage return as &#13;, which an HTML parser
// would otherwise turn into a line feed.
func (r *renderer) escape(s string) {
	r.b.WriteString(strings.ReplaceAll(html.EscapeString(s), "\r", "&#13;"))
}

func (r *renderer) tag(s string) {
	r.b.WriteString(s)
	r.tagged = true
}

// keptBlock is the block a line is in, when the chat keeps its kind. A list's empty line is in none.
func (r *renderer) keptBlock(line int) (block, bool) {
	if b := r.blockOf[line]; b >= 0 && r.keep(r.blocks[b].kind) && !r.listGap(line) {
		return r.blocks[b], true
	}
	return block{}, false
}

// blank is a line with nothing to write: no text, and no plain-form prefix.
func (r *renderer) blank(line int) bool {
	_, kept := r.keptBlock(line)
	return r.lines[line].start == r.lines[line].end && (kept || r.prefix(line) == "")
}

func (r *renderer) html() string {
	afterBlock := false
	for l := 0; l < len(r.lines); {
		if b, ok := r.keptBlock(l); ok {
			last := l // up to the block's end, or the list's next empty line
			for last < b.last && !r.listGap(last+1) {
				last++
			}
			r.block(b, l, last)
			l, afterBlock = last+1, true
			continue
		}
		// A run of lines outside kept blocks, joined by <br>.
		end := l
		for end < len(r.lines) {
			if _, ok := r.keptBlock(end); ok {
				break
			}
			end++
		}
		if afterBlock && r.blank(l) {
			r.b.WriteString("<br>") // the break after the block, before the empty line
		}
		for i := l; i < end; i++ {
			if i > l {
				r.b.WriteString("<br>")
			}
			r.line(i, true)
		}
		if end < len(r.lines) && r.blank(end-1) {
			r.b.WriteString("<br>") // the empty line's own break, before the block
		}
		l, afterBlock = end, false
	}
	return r.b.String()
}

// block writes lines first to last of block b.
func (r *renderer) block(b block, first, last int) {
	switch b.kind {
	case Pre:
		r.tag("<pre><code>")
		for l := first; l <= last; l++ {
			if l > first {
				r.b.WriteByte('\n')
			}
			r.escape(string(r.runes[r.lines[l].start:r.lines[l].end]))
		}
		r.tag("</code></pre>")
	case Quote:
		r.tag("<blockquote>")
		for l := first; l <= last; l++ {
			if l > first {
				r.b.WriteString("<br>")
			}
			r.line(l, false)
		}
		r.tag("</blockquote>")
	default:
		list := map[Kind]string{Bullets: "ul", Numbered: "ol"}[b.kind]
		if b.kind == Numbered && r.number[first] > 1 {
			r.tag("<" + list + ` start="` + strconv.Itoa(r.number[first]) + `">`)
		} else {
			r.tag("<" + list + ">")
		}
		for l := first; l <= last; l++ {
			r.tag("<li>")
			r.line(l, false)
			r.tag("</li>")
		}
		r.tag("</" + list + ">")
	}
}

// line writes one line's text: with the plain form of a block the chat doesn't keep when plain is set, then
// each stretch of the same atom (or of none).
func (r *renderer) line(l int, plain bool) {
	if plain {
		r.escape(r.prefix(l))
	}
	if b := r.blockOf[l]; b >= 0 && r.blocks[b].kind == Pre {
		r.escape(string(r.runes[r.lines[l].start:r.lines[l].end])) // a code block the chat doesn't keep
		return
	}
	for p := r.lines[l].start; p < r.lines[l].end; {
		a := r.atomOf[p]
		q := p
		for q < r.lines[l].end && r.atomOf[q] == a {
			q++
		}
		r.stretch(a, p, q)
		p = q
	}
}

func (r *renderer) stretch(a, p, q int) {
	if a == noAtom {
		r.styled(p, q)
		return
	}
	at := r.atoms[a]
	kept := r.keep(at.kind)
	switch {
	case at.kind == Code && kept:
		r.tag("<code>")
		r.escape(string(r.runes[p:q]))
		r.tag("</code>")
	case at.kind == Code:
		r.escape(string(r.runes[p:q]))
	case at.kind == Link && kept:
		r.tag(`<a href="`)
		r.escape(at.url)
		r.b.WriteString(`">`)
		r.styled(p, q)
		r.tag("</a>")
	case at.kind == Link:
		r.styled(p, q)
		r.escape(r.linkSuffix(a))
	case at.userID == RoomMention:
		r.styled(p, q)
		r.room = r.room || kept
	case kept:
		r.tag(`<a href="https://matrix.to/#/`)
		r.escape(url.PathEscape(at.userID))
		r.b.WriteString(`">`)
		r.styled(p, q)
		r.tag("</a>")
		if !slices.Contains(r.users, at.userID) {
			r.users = append(r.users, at.userID)
		}
	default:
		r.styled(p, q)
	}
}

type openStyle struct {
	kind int // index into styles
	span
}

// styled writes runes p to q with the kept styles nested: the one starting first outside, then the longer, then
// in styles' order. When one ends inside another, the inner closes and opens again, so tags always balance.
func (r *renderer) styled(p, q int) {
	mask := uint8(0)
	for i, k := range styles {
		if r.keep(k) {
			mask |= 1 << i
		}
	}
	bits := func(x int) uint8 { return r.style[x] & mask }
	// The stretch of each style around each rune, within p..q.
	runStart := make([][]int, len(styles))
	runEnd := make([][]int, len(styles))
	for k := range styles {
		runStart[k], runEnd[k] = make([]int, q-p), make([]int, q-p)
		for x := p; x < q; x++ {
			if x > p && bits(x)&bits(x-1)&(1<<k) != 0 {
				runStart[k][x-p] = runStart[k][x-p-1]
			} else {
				runStart[k][x-p] = x
			}
		}
		for x := q - 1; x >= p; x-- {
			if x < q-1 && bits(x)&bits(x+1)&(1<<k) != 0 {
				runEnd[k][x-p] = runEnd[k][x-p+1]
			} else {
				runEnd[k][x-p] = x + 1
			}
		}
	}
	var stack []openStyle
	for x := p; x < q; {
		var want []openStyle
		for k := range styles {
			if bits(x)&(1<<k) != 0 {
				want = append(want, openStyle{k, span{runStart[k][x-p], runEnd[k][x-p]}})
			}
		}
		slices.SortFunc(want, func(a, b openStyle) int {
			return cmp.Or(cmp.Compare(a.start, b.start), cmp.Compare(b.end, a.end), cmp.Compare(a.kind, b.kind))
		})
		same := 0
		for same < len(stack) && same < len(want) && stack[same] == want[same] {
			same++
		}
		for len(stack) > same {
			r.closeStyle(stack[len(stack)-1].kind)
			stack = stack[:len(stack)-1]
		}
		for _, o := range want[same:] {
			r.openStyle(o.kind)
			stack = append(stack, o)
		}
		y := x + 1
		for y < q && bits(y) == bits(x) {
			y++
		}
		r.escape(string(r.runes[x:y]))
		x = y
	}
	for i := len(stack) - 1; i >= 0; i-- {
		r.closeStyle(stack[i].kind)
	}
}

var (
	openTags  = []string{"<strong>", "<em>", "<del>", "<span data-mx-spoiler>"}
	closeTags = []string{"</strong>", "</em>", "</del>", "</span>"}
)

func (r *renderer) openStyle(k int)  { r.tag(openTags[k]) }
func (r *renderer) closeStyle(k int) { r.tag(closeTags[k]) }
