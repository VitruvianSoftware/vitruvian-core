// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"slices"
	"strconv"
	"strings"

	"go.mau.fi/util/dbutil"
)

// RoomSummary aliases Room so callers referring to either name see the same chat metadata.
type RoomSummary = Room

// InboxQuery asks for one page of chats: a space, narrowed by filters, in an order.
type InboxQuery struct {
	Space   string   // a space ID (see Spaces); "" is "inbox"
	Filters []string // see filterRules; none is "All"
	Sort    string   // newest (the default) | oldest | least_time_remaining | most_time_remaining
	RoomIDs []string // when set: exactly these chats, in any place; Space and Filters are ignored
	After   string   // the cursor InboxPage returned for the previous page of the same query; "" is the first page
	Limit   int      // 1..500; 0 is 200
}

// ErrBadCursor is InboxPage's answer for a cursor it didn't hand out for this query.
var ErrBadCursor = errors.New("that cursor belongs to another query")

const (
	defaultPageSize = 200
	maxPageSize     = 500
)

// chatFacts names the SQL expressions a space's rule reads about a chat: where it is (placeSQL), whether its
// account and every one of its labels let it into the inbox space (shownInInboxSQL), and whether it has a
// reminder or a scheduled message. The spaces bar's counts (spaceCountsSQL) and InboxPage read the same facts through
// the same rules, so a space's count is always the number of chats its pages list.
type chatFacts struct{ place, shown, reminded, scheduled string }

// placeRule is the rule of a built-in space, which is also the rule of the place filter of that name: the chat is
// in that place. ok is false for a name that isn't one.
func placeRule(c chatFacts, place string) (rule string, ok bool) {
	switch place {
	case "inbox":
		return `(` + c.place + ` = 'inbox' AND ` + c.shown + `)`, true
	case "reminders":
		return `(` + c.reminded + ` AND ` + c.place + ` <> 'hidden')`, true
	case "requests":
		return `(` + c.place + ` = 'requests')`, true
	case "low_priority":
		return `(` + c.place + ` = 'low_priority')`, true
	case "archive":
		return `(` + c.place + ` = 'archive')`, true
	case "hidden":
		return `(` + c.place + ` = 'hidden')`, true
	case "send_later":
		return `(` + c.scheduled + ` AND ` + c.place + ` <> 'hidden')`, true
	}
	return "", false
}

// scopedPlaceRule is the place rule of an account's or a label's space: the chat is in the inbox place, whatever
// Show in Inbox says.
func scopedPlaceRule(c chatFacts) string { return `(` + c.place + ` = 'inbox')` }

// roomAliases holds the table aliases for a room and its joined preferences, reminders, last event, and read markers.
type roomAliases struct {
	r, p, ap, rm, lev, rd, rde, lr, lre string
}

var (
	mainRoomAliases = roomAliases{r: "r", p: "p", ap: "ap", rm: "rm", lev: "lev", rd: "rd", rde: "rde", lr: "lr", lre: "lre"}
	peerRoomAliases = roomAliases{r: "r2", p: "p2", ap: "ap2", rm: "rm2", lev: "lev2", rd: "rd2", rde: "rde2", lr: "lr2", lre: "lre2"}
)

// unreadChatSQLFor is whether a room a.r is unread: marked unread (its room_prefs a.p), or a message from someone else
// after the read markers (readMarkerJoinsFor) or from the message it was marked unread from (unreadSQLFor, which also reads
// a.p). EXISTS stops at the first one, on events_room_ts.
func unreadChatSQLFor(a roomAliases) string {
	return `(COALESCE(` + a.p + `.marked_unread, 0) = 1 OR EXISTS (SELECT 1 FROM events u WHERE ` +
		unreadSQLFor(a.r, a.p, a.rd, a.rde, a.lr, a.lre) + `))`
}

var unreadChatSQL = unreadChatSQLFor(mainRoomAliases)

// chatFactsFor builds the chat facts of room a.r, with room_prefs a.p, account_prefs a.ap and reminders a.rm.
func chatFactsFor(a roomAliases) chatFacts {
	return chatFacts{
		place: placeSQL(a.r, a.p), shown: shownInInboxSQL(a.r, a.ap), reminded: a.rm + `.room_id IS NOT NULL`,
		scheduled: scheduledSQL(a.r),
	}
}

var pageFacts = chatFactsFor(mainRoomAliases)

// scheduledSQL is whether room r has a scheduled message, in any state (waiting, canceled or missed): a lookup on
// outbox_room.
func scheduledSQL(r string) string {
	return `EXISTS (SELECT 1 FROM outbox o WHERE o.room_id = ` + r + `.room_id AND o.kind = 'later')`
}

// unknownSQLFor is whether room r is a one-to-one chat with someone I don't know: it has no name, or its name is a
// phone number (^\+?[0-9][0-9 ()\-]{5,}$). SQLite has no regular expressions, so the name less a leading + must
// start with a digit and five more characters of the set, and have no character outside it.
// Inferred (inventory 01 §3): "From unknown numbers" means exactly this.
func unknownSQLFor(r string) string {
	return `(` + r + `.is_direct = 1 AND (` + r + `.name = '' OR (
  (CASE WHEN substr(` + r + `.name, 1, 1) = '+' THEN substr(` + r + `.name, 2) ELSE ` + r + `.name END) GLOB '[0-9][0-9 ()-][0-9 ()-][0-9 ()-][0-9 ()-][0-9 ()-]*'
  AND (CASE WHEN substr(` + r + `.name, 1, 1) = '+' THEN substr(` + r + `.name, 2) ELSE ` + r + `.name END) NOT GLOB '*[^0-9 ()-]*')))`
}

var unknownSQL = unknownSQLFor("r")

// mutedChatSQLFor is whether room r is muted: by me (p), by its account (ap) or by any of its labels.
func mutedChatSQLFor(r, p, ap string) string {
	return `(COALESCE(` + p + `.muted, 0) = 1 OR COALESCE(` + ap + `.muted, 0) = 1 OR EXISTS (
  SELECT 1 FROM room_labels mrl JOIN labels ml ON ml.label_id = mrl.label_id WHERE mrl.room_id = ` + r + `.room_id AND ml.muted = 1))`
}

var mutedChatSQL = mutedChatSQLFor("r", "p", "ap")

// filterRule is one filter: the group it ORs with, and its condition on room r.
type filterRule struct{ group, sql string }

const (
	groupPlace = "place"
	groupType  = "type"
	groupReply = "reply"
)

var allFilterNames = []string{
	"archived", "dms", "drafts", "groups", "hidden", "low_priority",
	"muted", "no_reply", "reminders", "requests", "send_later",
	"unanswered", "unknown", "unread",
}

// filterRuleFor builds a filter's group and SQL condition for the given table aliases.
func filterRuleFor(a roomAliases, name string) (filterRule, bool) {
	facts := chatFactsFor(a)
	place := func(p string) (filterRule, bool) {
		rule, _ := placeRule(facts, p)
		return filterRule{groupPlace, rule}, true
	}
	switch name {
	case "archived":
		return place("archive")
	case "low_priority":
		return place("low_priority")
	case "hidden":
		return place("hidden")
	case "requests":
		return place("requests")
	case "reminders":
		return place("reminders")
	case "send_later":
		return place("send_later")
	case "dms":
		return filterRule{groupType, a.r + `.is_direct = 1`}, true
	case "groups":
		return filterRule{groupType, a.r + `.is_direct = 0`}, true
	// Inferred (inventory 01 §3): Unanswered is "the newest message is from someone else", No reply "the
	// newest message is mine". A chat with no message is neither.
	case "unanswered":
		return filterRule{groupReply, a.lev + `.sender <> $1`}, true
	case "no_reply":
		return filterRule{groupReply, a.lev + `.sender = $1`}, true
	case "unread":
		return filterRule{"unread", unreadChatSQLFor(a)}, true
	case "drafts":
		return filterRule{"drafts", `COALESCE(` + a.p + `.draft, '') <> ''`}, true
	case "unknown":
		return filterRule{"unknown", unknownSQLFor(a.r)}, true
	case "muted":
		return filterRule{"muted", mutedChatSQLFor(a.r, a.p, a.ap)}, true
	}
	return filterRule{}, false
}

// filterRules are the filters by name for mainRoomAliases. Filters in one group are ORed; groups, and the filters that
// stand on their own (their group is their name), are ANDed. A place filter replaces the space's place rule; the
// space's account or label still applies. The reply filters read the room's newest message, lev (rooms.last_event_id).
var filterRules = func() map[string]filterRule {
	m := make(map[string]filterRule, len(allFilterNames))
	for _, name := range allFilterNames {
		r, _ := filterRuleFor(mainRoomAliases, name)
		m[name] = r
	}
	return m
}()

// FilterNames lists every filter an InboxQuery takes, sorted. The protocol lists the same names.
func FilterNames() []string { return sortedKeys(filterRules) }

// SortNames lists every sort an InboxQuery takes, sorted. The protocol lists the same names.
func SortNames() []string { return sortedKeys(sortKeys) }

func sortedKeys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	slices.Sort(out)
	return out
}

// sortKeys are each sort's two keys after the pin key, both ascending. Pinned chats come first, oldest pin first
// (pinKeySQL); room_id breaks every tie. Chats without a reminder come after those with one.
var sortKeys = map[string][2]string{
	"newest":               {`-r.last_ts`, `-r.created_at`},
	"oldest":               {`r.last_ts`, `r.created_at`},
	"least_time_remaining": {`(rm.room_id IS NULL)`, `COALESCE(rm.due_at, 0)`},
	"most_time_remaining":  {`(rm.room_id IS NULL)`, `-COALESCE(rm.due_at, 0)`},
}

// pinKeySQL orders pinned chats first, by pinned_at (strictly increasing, so that is pin order), then the rest.
const pinKeySQL = `CASE WHEN COALESCE(p.pinned_at, 0) > 0 THEN p.pinned_at ELSE 9223372036854775807 END`

// pageKey is a row's position in its query's order: (pin, a, b, room_id), all ascending.
type pageKey struct {
	pin, a, b int64
	room      string
}

// pageQuery is an InboxQuery checked and put in its canonical form.
type pageQuery struct {
	space            string // "" when RoomIDs is set
	kind, network    string
	labelID          int64
	filters, roomIDs []string // sorted, without repeats
	sort             string
	limit            int
}

// normalize checks q and puts it in canonical form. An unknown space, filter or sort, or a limit out of range,
// is ErrBadValue, even where RoomIDs means it would be ignored.
func normalize(q InboxQuery) (pageQuery, error) {
	pq := pageQuery{space: q.Space, sort: q.Sort, limit: q.Limit}
	if pq.space == "" {
		pq.space = "inbox"
	}
	var ok bool
	if pq.kind, pq.network, pq.labelID, ok = parseSpace(pq.space); !ok {
		return pageQuery{}, ErrBadValue
	}
	if pq.sort == "" {
		pq.sort = "newest"
	}
	if _, ok := sortKeys[pq.sort]; !ok {
		return pageQuery{}, ErrBadValue
	}
	switch {
	case pq.limit == 0:
		pq.limit = defaultPageSize
	case pq.limit < 0 || pq.limit > maxPageSize:
		return pageQuery{}, ErrBadValue
	}
	for _, f := range q.Filters {
		if _, ok := filterRules[f]; !ok {
			return pageQuery{}, ErrBadValue
		}
	}
	pq.filters = sortedSet(q.Filters)
	if len(q.RoomIDs) > 0 {
		pq.roomIDs = sortedSet(q.RoomIDs)
		pq.space, pq.kind, pq.network, pq.labelID, pq.filters = "", "", "", 0, nil
	}
	return pq, nil
}

func sortedSet(v []string) []string {
	out := slices.Clone(v)
	slices.Sort(out)
	return slices.Compact(out)
}

// hash identifies the query a cursor belongs to: its space, filters, sort and, for RoomIDs, the chats. The page
// size isn't part of it, so the next page can be a different size.
func (pq pageQuery) hash() string {
	b, _ := json.Marshal([]any{pq.space, pq.filters, pq.sort, pq.roomIDs})
	sum := sha256.Sum256(b)
	return base64.RawURLEncoding.EncodeToString(sum[:12])
}

// pageCursor is a cursor, before base64url: q is the query's hash, k the last row's key [pin, a, b, room_id].
type pageCursor struct {
	Q string            `json:"q"`
	K []json.RawMessage `json:"k"`
}

func (pq pageQuery) cursor(k pageKey) string {
	enc := func(v any) json.RawMessage { b, _ := json.Marshal(v); return b }
	b, _ := json.Marshal(pageCursor{Q: pq.hash(), K: []json.RawMessage{enc(k.pin), enc(k.a), enc(k.b), enc(k.room)}})
	return base64.RawURLEncoding.EncodeToString(b)
}

// parseCursor reads a cursor of this query. Anything else, malformed or another query's, is ErrBadCursor.
func (pq pageQuery) parseCursor(after string) (pageKey, error) {
	b, err := base64.RawURLEncoding.DecodeString(after)
	if err != nil {
		return pageKey{}, ErrBadCursor
	}
	var c pageCursor
	if json.Unmarshal(b, &c) != nil || c.Q != pq.hash() || len(c.K) != 4 {
		return pageKey{}, ErrBadCursor
	}
	var k pageKey
	if json.Unmarshal(c.K[0], &k.pin) != nil || json.Unmarshal(c.K[1], &k.a) != nil ||
		json.Unmarshal(c.K[2], &k.b) != nil || json.Unmarshal(c.K[3], &k.room) != nil {
		return pageKey{}, ErrBadCursor
	}
	return k, nil
}

// sqlArgs collects a statement's arguments; add returns the placeholder for the next. Values only ever travel as
// arguments: the SQL itself is built from the fixed fragments above.
type sqlArgs []any

func (a *sqlArgs) add(v any) string {
	*a = append(*a, v)
	return "$" + strconv.Itoa(len(*a))
}

// whereConditions builds the active space, place, and filter WHERE conditions for the given table aliases.
func (pq pageQuery) whereConditions(a roomAliases, networkArg, labelArg string) (where []string, needLast, needUnread bool) {
	switch pq.kind {
	case kindAccount:
		where = append(where, a.r+`.network = `+networkArg)
	case kindLabel:
		where = append(where, `EXISTS (SELECT 1 FROM room_labels ql WHERE ql.room_id = `+a.r+`.room_id AND ql.label_id = `+labelArg+`)`)
	}
	groups := map[string][]string{}
	var order []string
	for _, f := range pq.filters {
		rule, _ := filterRuleFor(a, f)
		if _, seen := groups[rule.group]; !seen {
			order = append(order, rule.group)
		}
		groups[rule.group] = append(groups[rule.group], rule.sql)
		needUnread = needUnread || f == "unread"
		needLast = needLast || rule.group == groupReply
	}
	facts := chatFactsFor(a)
	if _, ok := groups[groupPlace]; !ok {
		rule := scopedPlaceRule(facts)
		if pq.kind == kindBuiltin {
			rule, _ = placeRule(facts, pq.space)
		}
		where = append(where, rule)
	}
	for _, g := range order {
		where = append(where, `(`+strings.Join(groups[g], ` OR `)+`)`)
	}
	return where, needLast, needUnread
}

// primaryMergeRoomWhereSQL ensures that for any merged chat, only the newest member room that ALSO satisfies the
// active space/place/filter conditions (peerWhere) is selected. A merge passes a filter or place if ANY of its member
// rooms passes, and its single row is the newest member room that passes the active filter/place.
func primaryMergeRoomWhereSQL(peerWhere []string, needLast, needUnread bool) string {
	a := peerRoomAliases
	q := `NOT EXISTS (
  SELECT 1 FROM merged_chat_rooms mcr1
  JOIN merged_chat_rooms mcr2 ON mcr2.merge_id = mcr1.merge_id AND mcr2.room_id <> mcr1.room_id
  JOIN rooms ` + a.r + ` ON ` + a.r + `.room_id = mcr2.room_id
  LEFT JOIN room_prefs ` + a.p + ` ON ` + a.p + `.room_id = ` + a.r + `.room_id
  LEFT JOIN account_prefs ` + a.ap + ` ON ` + a.ap + `.network = ` + a.r + `.network
  LEFT JOIN reminders ` + a.rm + ` ON ` + a.rm + `.room_id = ` + a.r + `.room_id`
	if needLast {
		q += `
  LEFT JOIN events ` + a.lev + ` ON ` + a.lev + `.event_id = ` + a.r + `.last_event_id`
	}
	if needUnread {
		q += "\n" + readMarkerJoinsFor(a.r, a.rd, a.rde, a.lr, a.lre)
	}
	q += `
  WHERE mcr1.room_id = r.room_id`
	for _, w := range peerWhere {
		q += `
    AND ` + w
	}
	q += `
    AND (` + a.r + `.last_ts > r.last_ts
         OR (` + a.r + `.last_ts = r.last_ts AND (` + a.r + `.created_at > r.created_at
             OR (` + a.r + `.created_at = r.created_at AND ` + a.r + `.room_id < r.room_id))))
)`
	return q
}

// sql builds the page statement. pg picks the page: it scans rooms with the space's and filters' conditions
// (index lookups each: prefs, account prefs, reminder, the newest message, and events_room_ts from the read
// marker on for unread), orders by the sort's keys and takes limit+1 rows (one more says a next page exists),
// starting after the cursor's key. Only then are the page's rows read in full, inboxColsSQL for at most limit+1
// chats, so the cost of the columns doesn't grow with the inbox.
func (pq pageQuery) sql(after *pageKey) (string, []any) {
	args := sqlArgs{myID}
	var where []string
	needUnread, needLast := false, false
	if len(pq.roomIDs) > 0 {
		ids, _ := json.Marshal(pq.roomIDs)
		where = append(where, `r.room_id IN (SELECT value FROM json_each(`+args.add(string(ids))+`))`)
	} else {
		var networkArg, labelArg string
		switch pq.kind {
		case kindAccount:
			networkArg = args.add(pq.network)
		case kindLabel:
			labelArg = args.add(pq.labelID)
		}
		where, needLast, needUnread = pq.whereConditions(mainRoomAliases, networkArg, labelArg)
		if pq.kind != kindAccount {
			peerWhere, _, _ := pq.whereConditions(peerRoomAliases, networkArg, labelArg)
			where = append(where, primaryMergeRoomWhereSQL(peerWhere, needLast, needUnread))
		}
	}
	keys := sortKeys[pq.sort]
	inner := `SELECT r.room_id, ` + pinKeySQL + ` AS k_pin, ` + keys[0] + ` AS k_a, ` + keys[1] + ` AS k_b
  FROM rooms r
  LEFT JOIN room_prefs p ON p.room_id = r.room_id
  LEFT JOIN account_prefs ap ON ap.network = r.network
  LEFT JOIN reminders rm ON rm.room_id = r.room_id`
	if needLast {
		inner += `
  LEFT JOIN events lev ON lev.event_id = r.last_event_id`
	}
	if needUnread {
		inner += "\n" + readMarkerJoins
	}
	if len(where) > 0 {
		inner += `
  WHERE ` + strings.Join(where, `
    AND `)
	}
	page := `SELECT * FROM (` + inner + `)`
	if after != nil {
		page += ` WHERE (k_pin, k_a, k_b, room_id) > (` + args.add(after.pin) + `, ` + args.add(after.a) + `, ` +
			args.add(after.b) + `, ` + args.add(after.room) + `)`
	}
	page += ` ORDER BY k_pin, k_a, k_b, room_id LIMIT ` + args.add(pq.limit+1)
	return `WITH pg AS MATERIALIZED (` + page + `)
SELECT pg.k_pin, pg.k_a, pg.k_b, ` + inboxColsSQL + `
FROM pg CROSS JOIN rooms r ON r.room_id = pg.room_id
` + inboxJoinsSQL + `
ORDER BY pg.k_pin, pg.k_a, pg.k_b, pg.room_id`, args
}

// buildInboxPage is the statement and arguments of q's page after the cursor key (nil for the first page).
func buildInboxPage(q InboxQuery, after *pageKey) (string, []any, error) {
	pq, err := normalize(q)
	if err != nil {
		return "", nil, err
	}
	query, args := pq.sql(after)
	return query, args, nil
}

// keyedScan scans a page row: the row's key, then inboxColsSQL.
type keyedScan struct {
	row dbutil.Scannable
	k   *pageKey
}

func (s keyedScan) Scan(dest ...any) error {
	return s.row.Scan(append([]any{&s.k.pin, &s.k.a, &s.k.b}, dest...)...)
}

// InboxPage returns one page of q: up to Limit chats and the cursor of the next page ("" when this is the last).
// Paging is by key, never by offset, so in every sort a chat that doesn't move is listed exactly once across the
// pages. A chat that moves between pages can be listed twice: under oldest after a new message, or in any sort
// after a pin, an unpin or a reminder change. Callers dedupe by room ID.
func (s *Store) InboxPage(ctx context.Context, q InboxQuery) (rows []InboxRow, next string, err error) {
	pq, err := normalize(q)
	if err != nil {
		return nil, "", err
	}
	var after *pageKey
	if q.After != "" {
		k, err := pq.parseCursor(q.After)
		if err != nil {
			return nil, "", err
		}
		after = &k
	}
	query, args := pq.sql(after)
	res, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return nil, "", err
	}
	defer res.Close()
	var keys []pageKey
	for res.Next() {
		var k pageKey
		r, err := s.scanInboxRow(keyedScan{res, &k})
		if err != nil {
			return nil, "", err
		}
		k.room = r.ID
		rows, keys = append(rows, r), append(keys, k)
	}
	if err := res.Err(); err != nil {
		return nil, "", err
	}
	if len(rows) > pq.limit {
		rows = rows[:pq.limit]
		next = pq.cursor(keys[pq.limit-1])
	}
	if pq.kind == kindAccount {
		for i := range rows {
			rows[i].MergeID = ""
		}
		return rows, next, nil
	}
	if err := s.enrichMergedInboxRows(ctx, rows); err != nil {
		return nil, "", err
	}
	return rows, next, nil
}
