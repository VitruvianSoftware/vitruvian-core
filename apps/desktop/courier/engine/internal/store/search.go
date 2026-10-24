// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"cmp"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/searchtext"
)

// The query side of the search index (searchindex.go). Every statement here is built from fixed fragments; every
// value travels as a bound parameter, and the MATCH expression is one parameter built only from searchtext's
// quoted terms and the scope tokens this package makes, so nothing a person types is ever SQL or FTS5 syntax.
// Text always matches through its own column ({body}: or {name}:) and filters through {scope}:, so a scope token
// ("all", "me", "dm", "group", …) never matches as a word. Nothing here logs text, names or queries.

// ErrNoQuery is the answer to a search with nothing to look for: no words, and no filter that picks messages out.
var ErrNoQuery = errors.New("nothing to search for")

const (
	defaultMessageLimit = 20
	maxMessageLimit     = 50
	defaultNameLimit    = 5
	maxNameLimit        = 100
	// maxSearchRoomIDs is how many chats a message search can be narrowed to.
	maxSearchRoomIDs = 100
	// searchPageBytes is what a page of hits stays under (4.1's rule: a page fits in 1 MiB with room for the
	// envelope), counted as JSON. A page that would pass it ends early, with a cursor for the rest.
	searchPageBytes = 1<<20 - 4<<10
)

// messageKinds are the kinds a message search filters on: the scope token of each is k and its name. A link is a
// text message holding an http(s) URL, so it is both text and link.
var messageKinds = map[string]bool{"text": true, "image": true, "video": true, "audio": true, "file": true, "sticker": true, "link": true}

// MessageQuery asks for one page of messages, newest first.
type MessageQuery struct {
	Terms              []searchtext.Term // may be empty when a positive filter is given
	Partial            bool              // after the full matches, those with some of the words
	RoomIDs            []string          // 0..100
	Networks           []string
	Sender             string    // "" | "me" | "others" | a user ID (milestone 5)
	ChatType           string    // "" | "dm" | "group"
	Kinds, NotKinds    []string  // text image video audio file sticker link
	Since, Until       time.Time // zero = open; Until is exclusive
	ExcludeLowPriority bool      // milestone 5
	ExcludeMuted       bool      // milestone 5; muted by the chat, its account or a label
	BookmarkedOnly     bool      // only bookmarked messages: it narrows, and alone is ErrNoQuery
	After              string    // the cursor of the previous page of the same query
	Limit              int       // 1..50; 0 is 20
}

// MessageHit is one message found.
type MessageHit struct {
	Event             Event
	Text, Kind        string // CurrentText and its kind
	RoomName, Network string
	IsDirect          bool
	Place             string // inbox | archive | low_priority | hidden | requests
	MediaURI          string // the image's or video's thumbnail (or the file) for kimage / kvideo, else ""
	Partial           bool   // a partial match
}

// NameQuery asks for chats or people by name.
type NameQuery struct {
	Terms    []searchtext.Term
	Networks []string
	ChatType string // "" | "dm" | "group"
	Limit    int    // 1..100; 0 is 5
}

// PersonHit is someone found by name in a group I share with them: RoomID is that group with the newest message,
// and Groups how many groups we share.
type PersonHit struct {
	UserID, Name, Network, AvatarURI, RoomID, RoomName string
	Groups                                             int
}

// searchTerms keeps the terms that have something to match: a term built by hand may hold no word at all.
func searchTerms(terms []searchtext.Term) []searchtext.Term {
	var out []searchtext.Term
	for _, t := range terms {
		if len(searchtext.Words(searchtext.Normalize(t.Text))) > 0 {
			out = append(out, t)
		}
	}
	return out
}

// scopeAny is an FTS5 expression over the scope column that matches any of tokens. The tokens are this package's
// own (lowercase ASCII letters and digits), quoted all the same.
func scopeAny(tokens []string) string {
	quoted := make([]string, len(tokens))
	for i, t := range tokens {
		quoted[i] = `"` + strings.ReplaceAll(t, `"`, `""`) + `"`
	}
	return `{scope}: (` + strings.Join(quoted, ` OR `) + `)`
}

// andAll ANDs FTS5 expressions, each in brackets.
func andAll(parts []string) string { return `(` + strings.Join(parts, `) AND (`) + `)` }

// messageSearch is a MessageQuery checked and put in its canonical form.
type messageSearch struct {
	terms                              []searchtext.Term
	partial                            bool
	roomIDs, networks, kinds, notKinds []string // sorted, without repeats
	sender, chatType                   string   // sender is "", "me", "others" or a user ID other than mine
	since, until                       *int64   // ms; nil = open
	excludeLow, excludeMuted           bool
	bookmarkedOnly                     bool
	limit                              int
}

// normalizeMessageQuery checks q. A limit, a kind, a sender or a chat type it doesn't take, or more than 100
// chats, is ErrBadValue. No words and no filter that picks messages to list (chats, networks, a sender, a chat
// type, kinds, Since or Until) is ErrNoQuery: what only leaves messages out (NotKinds, low priority, muted,
// BookmarkedOnly) or widens (Partial) has nothing to list. A filter alone is a browse, newest first: with no words
// the match is the scope column's "all" token ANDed with the filters, which FTS5 walks in doc-id order from Until
// (or the top) down to Since and stops at the limit (Ruling 34): a cheap browse, as TestSearchPlansWalkTheIndex
// checks. Bookmarks alone would walk every message for a few, so RecentBookmarks lists those instead.
func normalizeMessageQuery(q MessageQuery) (messageSearch, error) {
	m := messageSearch{
		terms: searchTerms(q.Terms), partial: q.Partial, roomIDs: sortedSet(q.RoomIDs), networks: sortedSet(q.Networks),
		kinds: sortedSet(q.Kinds), notKinds: sortedSet(q.NotKinds), sender: q.Sender, chatType: q.ChatType,
		excludeLow: q.ExcludeLowPriority, excludeMuted: q.ExcludeMuted, bookmarkedOnly: q.BookmarkedOnly, limit: q.Limit,
	}
	switch {
	case m.limit == 0:
		m.limit = defaultMessageLimit
	case m.limit < 0 || m.limit > maxMessageLimit:
		return messageSearch{}, ErrBadValue
	}
	if len(m.roomIDs) > maxSearchRoomIDs {
		return messageSearch{}, ErrBadValue
	}
	for _, k := range append(slices.Clone(m.kinds), m.notKinds...) {
		if !messageKinds[k] {
			return messageSearch{}, ErrBadValue
		}
	}
	switch {
	case m.sender == string(ids.Me):
		m.sender = "me"
	case m.sender == "", m.sender == "me", m.sender == "others", strings.HasPrefix(m.sender, "@"):
	default:
		return messageSearch{}, ErrBadValue
	}
	if m.chatType != "" && m.chatType != "dm" && m.chatType != "group" {
		return messageSearch{}, ErrBadValue
	}
	if !q.Since.IsZero() {
		ms := q.Since.UnixMilli()
		m.since = &ms
	}
	if !q.Until.IsZero() {
		ms := q.Until.UnixMilli()
		m.until = &ms
	}
	positive := len(m.roomIDs) > 0 || len(m.networks) > 0 || len(m.kinds) > 0 || m.sender != "" || m.chatType != "" ||
		m.since != nil || m.until != nil
	if len(m.terms) == 0 && !positive {
		return messageSearch{}, ErrNoQuery
	}
	return m, nil
}

// lastPhase is the last phase a search runs: 0 is the messages with every word; 1, when Partial is on and there
// are at least 2 terms, those with some of the words but not all.
// Inferred (inventory 01 §12): "Show partial matches" lists, after every full match, the messages that match some
// but not all of the words.
func (m messageSearch) lastPhase() int {
	if m.partial && len(m.terms) >= 2 {
		return 1
	}
	return 0
}

// match is phase's MATCH expression: the words through {body}: (or, with none, every message, {scope}: "all"),
// ANDed with the positive filters through {scope}:, and NOT the negative ones (others' messages are NOT "me";
// NotKinds).
func (m messageSearch) match(phase int) string {
	var pos []string
	switch {
	case len(m.terms) == 0:
		pos = append(pos, `{scope}: "all"`)
	case phase == 0:
		pos = append(pos, searchtext.MatchAll("body", m.terms))
	default:
		pos = append(pos, `(`+searchtext.MatchAny("body", m.terms)+`) NOT (`+searchtext.MatchAll("body", m.terms)+`)`)
	}
	if len(m.roomIDs) > 0 {
		tokens := make([]string, len(m.roomIDs))
		for i, id := range m.roomIDs {
			tokens[i] = RoomScope(id)
		}
		pos = append(pos, scopeAny(tokens))
	}
	if len(m.networks) > 0 {
		pos = append(pos, scopeAny(networkTokens(m.networks)))
	}
	switch m.sender {
	case "", "others":
	case "me":
		pos = append(pos, scopeAny([]string{"me"}))
	default:
		pos = append(pos, scopeAny([]string{SenderScope(m.sender)}))
	}
	if len(m.kinds) > 0 {
		pos = append(pos, scopeAny(kindTokens(m.kinds)))
	}
	expr := andAll(pos)
	var neg []string
	if m.sender == "others" {
		neg = append(neg, "me")
	}
	neg = append(neg, kindTokens(m.notKinds)...)
	if len(neg) > 0 {
		expr = `(` + expr + `) NOT ` + scopeAny(neg)
	}
	return expr
}

func networkTokens(networks []string) []string {
	out := make([]string, len(networks))
	for i, n := range networks {
		out[i] = NetworkScope(n)
	}
	return slices.Compact(slices.Sorted(slices.Values(out)))
}

func kindTokens(kinds []string) []string {
	out := make([]string, len(kinds))
	for i, k := range kinds {
		out[i] = "k" + k
	}
	return out
}

// docBound is the first doc id of millisecond ms, kept within the doc ids there can be.
func docBound(ms int64) int64 { return min(max(ms, 0), maxDocTS) << 10 }

// top is the highest doc id a page may start from: below Until's first, or any.
func (m messageSearch) top() int64 {
	if m.until == nil {
		return math.MaxInt64
	}
	if *m.until > maxDocTS {
		return math.MaxInt64
	}
	return docBound(*m.until) - 1 // -1 when Until is at or before 0: nothing
}

// searchColsSQL is a hit's columns: the doc id, the event (eventCols of e), and its chat r with prefs p.
var searchColsSQL = `f.rowid, e.room_id, e.event_id, e.sender, e.type, e.state_key, e.content, e.ts, e.status,
  e.status_reason, e.seq, e.deleted_for_me, e.expires_at, COALESCE(NULLIF(p.local_name, ''), r.name), r.network, r.is_direct, ` + placeSQL("r", "p")

// sql is the statement of up to limit hits of phase with doc id at most upper, newest first. CROSS JOIN fixes the
// order, so FTS5 drives it: it walks its matches in doc-id order, which is time order (indexEvent), from upper
// down, with Since as the lower bound; each match's event is looked up through events_doc and its chat by primary
// key. Chat type, low priority and mute are checked on that chat: few rows are passed over (about half the
// chats are DMs), and nothing is sorted. BookmarkedOnly joins bookmarks after the FTS5 join, a primary-key lookup per
// match, so FTS5 still drives the plan.
func (m messageSearch) sql(phase int, upper int64, limit int) (string, []any) {
	var args sqlArgs
	q := `SELECT ` + searchColsSQL + `
FROM search_messages f CROSS JOIN events e ON e.doc_id = f.rowid`
	if m.bookmarkedOnly {
		q += ` CROSS JOIN bookmarks b ON b.event_id = e.event_id`
	}
	q += ` CROSS JOIN rooms r ON r.room_id = e.room_id
LEFT JOIN room_prefs p ON p.room_id = r.room_id`
	if m.excludeMuted {
		q += `
LEFT JOIN account_prefs ap ON ap.network = r.network`
	}
	q += `
WHERE f.search_messages MATCH ` + args.add(m.match(phase)) + ` AND f.rowid <= ` + args.add(upper)
	if m.since != nil {
		q += ` AND f.rowid >= ` + args.add(docBound(*m.since))
	}
	switch m.chatType {
	case "dm":
		q += ` AND r.is_direct = 1`
	case "group":
		q += ` AND r.is_direct = 0`
	}
	if m.excludeLow {
		q += ` AND COALESCE(p.low_priority, 0) = 0`
	}
	if m.excludeMuted {
		q += ` AND NOT ` + mutedChatSQL
	}
	q += `
ORDER BY f.rowid DESC LIMIT ` + args.add(limit)
	return q, args
}

// hash identifies the query a cursor belongs to: everything but After and Limit, so the next page can be a
// different size.
func (m messageSearch) hash() string {
	b, _ := json.Marshal([]any{
		m.terms, m.partial, m.roomIDs, m.networks, m.sender, m.chatType, m.kinds, m.notKinds,
		m.since, m.until, m.excludeLow, m.excludeMuted, m.bookmarkedOnly,
	})
	sum := sha256.Sum256(b)
	return base64.RawURLEncoding.EncodeToString(sum[:12])
}

// searchCursor is a cursor, before base64url: q the query's hash, p the phase, r the doc id of the last hit handed
// out in that phase (absent: the phase starts from the top).
type searchCursor struct {
	Q string `json:"q"`
	P int    `json:"p"`
	R *int64 `json:"r,omitempty"`
}

func (m messageSearch) cursor(phase int, last *int64) string {
	b, _ := json.Marshal(searchCursor{Q: m.hash(), P: phase, R: last})
	return base64.RawURLEncoding.EncodeToString(b)
}

// parseCursor reads a cursor of this query. Anything else, malformed or another query's, is ErrBadCursor.
func (m messageSearch) parseCursor(after string) (searchCursor, error) {
	b, err := base64.RawURLEncoding.DecodeString(after)
	if err != nil {
		return searchCursor{}, ErrBadCursor
	}
	var c searchCursor
	if json.Unmarshal(b, &c) != nil || c.Q != m.hash() || c.P < 0 || c.P > m.lastPhase() {
		return searchCursor{}, ErrBadCursor
	}
	return c, nil
}

// searchRow is one row of messageSearch.sql.
type searchRow struct {
	docID             int64
	e                 Event
	roomName, network string
	direct            bool
	place             string
}

func (s *Store) searchRows(ctx context.Context, m messageSearch, phase int, upper int64, limit int) ([]searchRow, error) {
	query, args := m.sql(phase, upper, limit)
	rows, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []searchRow
	for rows.Next() {
		var r searchRow
		var er eventRow
		dest := append(append([]any{&r.docID}, er.dest()...), &r.roomName, &r.network, &r.direct, &r.place)
		if err := rows.Scan(dest...); err != nil {
			return nil, err
		}
		r.e = er.event()
		out = append(out, r)
	}
	return out, rows.Err()
}

// hitOf is the hit of a found row: its message's current text and kind, and its chat.
func (s *Store) hitOf(ctx context.Context, r searchRow, partial bool) (MessageHit, error) {
	text, err := s.CurrentText(ctx, r.e)
	if err != nil {
		return MessageHit{}, err
	}
	_, kind, _ := MessageText(r.e.Type, r.e.Content)
	return MessageHit{
		Event: r.e, Text: text, Kind: kind, RoomName: r.roomName, Network: r.network, IsDirect: r.direct,
		Place: r.place, MediaURI: hitMediaURI(kind, r.e.Content), Partial: partial,
	}, nil
}

// hitMediaURI is what a hit shows for an image or a video: its thumbnail, else the file itself.
func hitMediaURI(kind string, content json.RawMessage) string {
	if kind != "image" && kind != "video" {
		return ""
	}
	var c struct {
		URL  string `json:"url"`
		Info struct {
			ThumbnailURL string `json:"thumbnail_url"`
		} `json:"info"`
	}
	_ = json.Unmarshal(content, &c) // an indexed message's content is JSON; anything else shows no media
	if c.Info.ThumbnailURL != "" {
		return c.Info.ThumbnailURL
	}
	return c.URL
}

// hitBytes is about what a hit takes as JSON: its strings escaped and its content as it is.
func hitBytes(h MessageHit) int {
	b, err := json.Marshal(struct {
		E          Event
		T, N, U, P string
	}{h.Event, h.Text, h.RoomName, h.MediaURI, h.Place})
	if err != nil { // content that isn't JSON: count it as a string, at worst six bytes a byte
		return 6*(len(h.Event.Content)+len(h.Text)+len(h.RoomName)+len(h.MediaURI)) + 512
	}
	return len(b) + 1
}

// SearchMessages returns one page of q, newest first: up to Limit hits and the cursor of the next page ("" when
// this is the last). With Partial, every full match comes first, then the partial ones, each newest first.
//
// Paging is by doc id, never by offset: a page carries on below the last doc id handed out, so no hit repeats and
// a message that arrives meanwhile (a higher doc id) doesn't push the later pages along. A page can end before
// Limit to stay under 1 MiB, so a short page isn't the last: only next == "" says that.
func (s *Store) SearchMessages(ctx context.Context, q MessageQuery) ([]MessageHit, string, error) {
	m, err := normalizeMessageQuery(q)
	if err != nil {
		return nil, "", err
	}
	phase, upper := 0, m.top()
	var start *int64 // the cursor's doc id, for the phase it is in
	if q.After != "" {
		c, err := m.parseCursor(q.After)
		if err != nil {
			return nil, "", err
		}
		phase, start = c.P, c.R
		if c.R != nil {
			upper = min(upper, *c.R-1)
		}
	}
	hits := []MessageHit{}
	size := 2 // the list's brackets
	for ; phase <= m.lastPhase(); phase, upper, start = phase+1, m.top(), nil {
		want := m.limit - len(hits)
		rows, err := s.searchRows(ctx, m, phase, upper, want+1) // one more says whether the phase goes on
		if err != nil {
			return nil, "", err
		}
		last := start
		for i, r := range rows {
			if i == want {
				return hits, m.cursor(phase, last), nil
			}
			h, err := s.hitOf(ctx, r, phase == 1)
			if err != nil {
				return nil, "", err
			}
			n := hitBytes(h)
			if len(hits) > 0 && size+n > searchPageBytes {
				return hits, m.cursor(phase, last), nil
			}
			size += n
			hits = append(hits, h)
			docID := r.docID
			last = &docID
		}
	}
	return hits, "", nil
}

// nameSearch is a NameQuery checked and put in its canonical form.
type nameSearch struct {
	terms    []searchtext.Term
	networks []string // their scope tokens
	chatType string
	limit    int
}

// normalizeNameQuery checks q: a limit or a chat type it doesn't take is ErrBadValue, and no words ErrNoQuery.
func normalizeNameQuery(q NameQuery) (nameSearch, error) {
	n := nameSearch{terms: searchTerms(q.Terms), chatType: q.ChatType, limit: q.Limit}
	switch {
	case n.limit == 0:
		n.limit = defaultNameLimit
	case n.limit < 0 || n.limit > maxNameLimit:
		return nameSearch{}, ErrBadValue
	}
	if n.chatType != "" && n.chatType != "dm" && n.chatType != "group" {
		return nameSearch{}, ErrBadValue
	}
	if len(q.Networks) > 0 {
		n.networks = networkTokens(q.Networks)
	}
	if len(n.terms) == 0 {
		return nameSearch{}, ErrNoQuery
	}
	return n, nil
}

// match is the MATCH expression of a name: every word through {name}:, ANDed with the networks and any extra
// scope tokens (a chat's dm or group) through {scope}:.
func (n nameSearch) match(extra ...string) string {
	parts := []string{searchtext.MatchAll("name", n.terms)}
	if len(n.networks) > 0 {
		parts = append(parts, scopeAny(n.networks))
	}
	for _, t := range extra {
		parts = append(parts, scopeAny([]string{t}))
	}
	return andAll(parts)
}

// wantsNetwork is whether a chat on network passes the query's networks.
func (n nameSearch) wantsNetwork(network string) bool {
	return len(n.networks) == 0 || slices.Contains(n.networks, NetworkScope(network))
}

// startsWith is whether name begins with the first term: its first words are the term's, the last of them only
// begun when the term is still being typed. Prefixes start at a word, as the index matches them.
func (n nameSearch) startsWith(name string) bool {
	first := n.terms[0]
	tw := searchtext.Words(searchtext.Normalize(first.Text))
	nw := searchtext.Words(searchtext.Normalize(name))
	if len(nw) < len(tw) {
		return false
	}
	for i, w := range tw {
		if nw[i] == w {
			continue
		}
		if i == len(tw)-1 && first.Prefix && !first.Phrase && strings.HasPrefix(nw[i], w) {
			continue
		}
		return false
	}
	return true
}

// chatMatchSQL lists the chats whose name matches $1: FTS5 first, then each doc's chat_docs row by its integer
// key and the chat by its primary key.
const chatMatchSQL = `SELECT r.room_id, COALESCE(NULLIF(p.local_name, ''), r.name), r.network, r.last_ts
FROM search_chats f CROSS JOIN chat_docs d ON d.doc_id = f.rowid CROSS JOIN rooms r ON r.room_id = d.room_id
LEFT JOIN room_prefs p ON p.room_id = r.room_id
WHERE f.search_chats MATCH $1`

// personDMSQL lists the people whose name matches $1 with each chat they have a member row in, through
// members_user and the chats' primary key: SearchChats keeps the direct ones.
const personDMSQL = `SELECT r.room_id, r.network, r.last_ts, COALESCE(pr.display_name, ''), m.content
FROM search_people f CROSS JOIN people_docs d ON d.doc_id = f.rowid CROSS JOIN members m ON m.user_id = d.user_id
CROSS JOIN rooms r ON r.room_id = m.room_id LEFT JOIN profiles pr ON pr.user_id = d.user_id
WHERE f.search_people MATCH $1 AND r.is_direct = 1`

// memberOf reads a member row: whether it is being in the chat (not leave or ban), and the name and avatar the
// chat knows them by.
func memberOf(content string) (in bool, name, avatar string) {
	var m struct {
		Membership  string `json:"membership"`
		DisplayName string `json:"displayname"`
		AvatarURL   string `json:"avatar_url"`
	}
	_ = json.Unmarshal([]byte(content), &m) // a member row we can't read still says they're in the chat
	return m.Membership != "leave" && m.Membership != "ban", m.DisplayName, m.AvatarURL
}

// nameHit is a chat or a person found by name, and what orders it.
type nameHit struct {
	key    string
	starts bool
	lastTS int64
}

// compareNameHits orders hits: a name that begins with the first word first, then the newest message, then by key.
func compareNameHits(a, b nameHit) int {
	if a.starts != b.starts {
		if a.starts {
			return -1
		}
		return 1
	}
	return cmp.Or(cmp.Compare(b.lastTS, a.lastTS), cmp.Compare(a.key, b.key))
}

// SearchChats lists the chats, in any place, whose name matches q, as whole inbox rows: a chat whose name begins
// with the first word first, then the newest message first. A DM is also found by the name of the person it is
// with, so one named by a phone number is found by theirs. All matches are read (at most the chats there are);
// only the first Limit are read in full.
func (s *Store) SearchChats(ctx context.Context, q NameQuery) ([]InboxRow, error) {
	n, err := normalizeNameQuery(q)
	if err != nil {
		return nil, err
	}
	var extra []string
	if n.chatType != "" {
		extra = append(extra, n.chatType)
	}
	found := map[string]nameHit{}
	add := func(h nameHit) {
		if old, ok := found[h.key]; ok {
			h.starts = h.starts || old.starts
		}
		found[h.key] = h
	}
	rows, err := s.db.Query(ctx, chatMatchSQL, n.match(extra...))
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var id, name, network string
		var lastTS int64
		if err := rows.Scan(&id, &name, &network, &lastTS); err != nil {
			rows.Close()
			return nil, err
		}
		add(nameHit{key: id, starts: n.startsWith(name), lastTS: lastTS})
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return nil, err
	}
	if n.chatType != "group" {
		rows, err := s.db.Query(ctx, personDMSQL, n.match())
		if err != nil {
			return nil, err
		}
		for rows.Next() {
			var id, network, profileName, content string
			var lastTS int64
			if err := rows.Scan(&id, &network, &lastTS, &profileName, &content); err != nil {
				rows.Close()
				return nil, err
			}
			in, memberName, _ := memberOf(content)
			if !in || !n.wantsNetwork(network) {
				continue
			}
			add(nameHit{key: id, starts: n.startsWith(profileName) || n.startsWith(memberName), lastTS: lastTS})
		}
		if err := errors.Join(rows.Err(), rows.Close()); err != nil {
			return nil, err
		}
	}
	return s.inboxRowsInOrder(ctx, found, n.limit)
}

// inboxRowsInOrder reads the first limit of found, in compareNameHits order, as whole inbox rows.
func (s *Store) inboxRowsInOrder(ctx context.Context, found map[string]nameHit, limit int) ([]InboxRow, error) {
	hits := make([]nameHit, 0, len(found))
	for _, h := range found {
		hits = append(hits, h)
	}
	slices.SortFunc(hits, compareNameHits)
	hits = hits[:min(len(hits), limit)]
	if len(hits) == 0 {
		return []InboxRow{}, nil
	}
	roomIDs := make([]string, len(hits))
	for i, h := range hits {
		roomIDs[i] = h.key
	}
	page, _, err := s.InboxPage(ctx, InboxQuery{RoomIDs: roomIDs, Limit: len(roomIDs)})
	if err != nil {
		return nil, err
	}
	byID := make(map[string]InboxRow, len(page))
	for _, r := range page {
		byID[r.ID] = r
	}
	out := make([]InboxRow, 0, len(hits))
	for _, id := range roomIDs {
		if r, ok := byID[id]; ok { // a chat deleted in between is left out
			out = append(out, r)
		}
	}
	return out, nil
}

// peopleInGroupsSQL lists the people whose name matches $1 with every chat they have a member row in, through
// members_user and the chats' primary key.
const peopleInGroupsSQL = `SELECT d.user_id, COALESCE(pr.display_name, ''), COALESCE(pr.avatar_uri, ''), m.content,
  r.room_id, COALESCE(NULLIF(p.local_name, ''), r.name), r.network, r.is_direct, r.last_ts
FROM search_people f CROSS JOIN people_docs d ON d.doc_id = f.rowid CROSS JOIN members m ON m.user_id = d.user_id
CROSS JOIN rooms r ON r.room_id = m.room_id LEFT JOIN room_prefs p ON p.room_id = r.room_id
LEFT JOIN profiles pr ON pr.user_id = d.user_id
WHERE f.search_people MATCH $1`

// SearchPeopleInGroups lists the people whose name matches q who are in at least one group with me and have no
// direct chat with me, each with the group of theirs that has the newest message and how many groups they're in.
// A name that begins with the first word comes first, then the newest message. Networks narrows the groups; a
// direct chat on any network leaves the person out. A ChatType of dm finds no one: these are people met in groups.
//
// Inferred (inventory 01 §12 [I]): "In groups" lists people I have no direct chat with.
func (s *Store) SearchPeopleInGroups(ctx context.Context, q NameQuery) ([]PersonHit, error) {
	n, err := normalizeNameQuery(q)
	if err != nil {
		return nil, err
	}
	if n.chatType == "dm" {
		return []PersonHit{}, nil
	}
	type person struct {
		hit                   PersonHit
		profileName, profAv   string
		direct, starts        bool
		lastTS                int64
		bestName, bestAv, any string
	}
	people := map[string]*person{}
	rows, err := s.db.Query(ctx, peopleInGroupsSQL, n.match())
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var userID, profileName, profileAvatar, content, roomID, roomName, network string
		var direct bool
		var lastTS int64
		if err := rows.Scan(&userID, &profileName, &profileAvatar, &content, &roomID, &roomName, &network, &direct, &lastTS); err != nil {
			rows.Close()
			return nil, err
		}
		p := people[userID]
		if p == nil {
			p = &person{hit: PersonHit{UserID: userID}, profileName: profileName, profAv: profileAvatar, starts: n.startsWith(profileName)}
			people[userID] = p
		}
		in, memberName, memberAvatar := memberOf(content)
		if !in {
			continue
		}
		p.starts = p.starts || n.startsWith(memberName)
		if p.any == "" {
			p.any = memberName
		}
		if direct {
			p.direct = true
			continue
		}
		if !n.wantsNetwork(network) {
			continue
		}
		p.hit.Groups++
		if p.hit.Groups == 1 || lastTS > p.lastTS || lastTS == p.lastTS && roomID < p.hit.RoomID {
			p.hit.RoomID, p.hit.RoomName, p.hit.Network, p.lastTS = roomID, roomName, network, lastTS
			p.bestName, p.bestAv = memberName, memberAvatar
		}
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return nil, err
	}
	var hits []nameHit
	for id, p := range people {
		if !p.direct && p.hit.Groups > 0 {
			hits = append(hits, nameHit{key: id, starts: p.starts, lastTS: p.lastTS})
		}
	}
	slices.SortFunc(hits, compareNameHits)
	out := make([]PersonHit, 0, min(len(hits), n.limit))
	for _, h := range hits[:min(len(hits), n.limit)] {
		p := people[h.key]
		p.hit.Name = cmp.Or(p.profileName, p.bestName, p.any)
		p.hit.AvatarURI = cmp.Or(p.profAv, p.bestAv)
		out = append(out, p.hit)
	}
	return out, nil
}

// lastArchivedSQL is the chat archived most recently that isn't hidden and isn't $1.
const lastArchivedSQL = `SELECT room_id FROM room_prefs WHERE archived_at > 0 AND hidden = 0 AND room_id <> $1
ORDER BY archived_at DESC, room_id LIMIT 1`

// LastArchived is the chat archived most recently, as an inbox row, leaving out hidden chats and except (the open
// chat). ok is false when there is none.
//
// Inferred (inventory 01 §12, [O]): Last archived leaves out hidden chats and the open chat.
func (s *Store) LastArchived(ctx context.Context, except string) (InboxRow, bool, error) {
	var id string
	err := s.db.QueryRow(ctx, lastArchivedSQL, except).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return InboxRow{}, false, nil
	}
	if err != nil {
		return InboxRow{}, false, err
	}
	rows, err := s.inboxRowsInOrder(ctx, map[string]nameHit{id: {key: id}}, 1)
	if err != nil || len(rows) == 0 {
		return InboxRow{}, false, err
	}
	return rows[0], true, nil
}

// SharedLink is one HTTP(S) link extracted from a message in a room.
type SharedLink struct {
	EventID string
	Sender  string
	TS      time.Time
	URL     string
	Host    string
}

func (s *Store) RoomSharedMedia(ctx context.Context, roomID string, limit int) ([]Event, error) {
	if limit <= 0 {
		limit = 50
	}
	evts, err := s.queryEvents(ctx, `SELECT `+eventCols+` FROM events
		WHERE room_id = $1 AND type = 'm.room.message' AND deleted_for_me = 0 AND redacted = 0
		  AND json_extract(content, '$.msgtype') IN ('m.image', 'm.video')
		  AND COALESCE(json_extract(content, '$.url'), '') <> ''
		ORDER BY ts DESC, seq DESC LIMIT $2`, roomID, limit)
	if err != nil {
		return nil, err
	}
	if evts == nil {
		evts = []Event{}
	}
	return evts, nil
}

func (s *Store) RoomSharedFiles(ctx context.Context, roomID string, limit int) ([]Event, error) {
	if limit <= 0 {
		limit = 50
	}
	evts, err := s.queryEvents(ctx, `SELECT `+eventCols+` FROM events
		WHERE room_id = $1 AND type = 'm.room.message' AND deleted_for_me = 0 AND redacted = 0
		  AND json_extract(content, '$.msgtype') IN ('m.file', 'm.audio')
		  AND COALESCE(json_extract(content, '$.url'), '') <> ''
		ORDER BY ts DESC, seq DESC LIMIT $2`, roomID, limit)
	if err != nil {
		return nil, err
	}
	if evts == nil {
		evts = []Event{}
	}
	return evts, nil
}

func (s *Store) RoomSharedLinks(ctx context.Context, roomID string, limit int) ([]SharedLink, error) {
	if limit <= 0 {
		limit = 50
	}
	evts, err := s.queryEvents(ctx, `SELECT `+eventCols+` FROM events
		WHERE room_id = $1 AND type = 'm.room.message' AND deleted_for_me = 0 AND redacted = 0
		ORDER BY ts DESC, seq DESC`, roomID)
	if err != nil {
		return nil, err
	}
	out := []SharedLink{}
	for _, e := range evts {
		if isEdit(e.Content) {
			continue
		}
		text, err := s.CurrentText(ctx, e)
		if err != nil {
			return nil, err
		}
		for _, rawURL := range extractHTTPURLs(text) {
			u, err := url.Parse(rawURL)
			if err != nil || u.Hostname() == "" {
				continue
			}
			out = append(out, SharedLink{
				EventID: e.EventID,
				Sender:  e.Sender,
				TS:      e.TS,
				URL:     rawURL,
				Host:    u.Hostname(),
			})
			if len(out) >= limit {
				return out, nil
			}
		}
	}
	return out, nil
}

func extractHTTPURLs(text string) []string {
	var urls []string
	for _, token := range strings.Fields(text) {
		idx := strings.Index(token, "https://")
		if idx < 0 {
			idx = strings.Index(token, "http://")
		}
		if idx < 0 {
			continue
		}
		u := strings.TrimRight(token[idx:], ".,;:!?)>]'\"")
		if u != "http://" && u != "https://" {
			urls = append(urls, u)
		}
	}
	return urls
}
