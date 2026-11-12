// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi_test

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/localapi"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

// HomeSpeaker (apps/desktop/home-speaker, BeeperClient.swift) reads GET /v1/accounts and GET /v1/messages/search.
// The functions below port its reading of the answers, rule for rule (parseAccounts, parseSearch, shouldAnnounce,
// spokenText, allMessages's paging), so these tests hold Vitruvian Courier's answers to what HomeSpeaker actually does with
// them. A change on either side that breaks the other should break here: keep them in step with the Swift.

type hsAccount struct{ accountID, bridgeType, network, userID string }

// hsParseAccounts is BeeperClient.parseAccounts: a list, or an object holding one under items or accounts; an
// entry with no accountID is skipped.
func hsParseAccounts(v any) []hsAccount {
	var list []any
	switch x := v.(type) {
	case []any:
		list = x
	case map[string]any:
		if l, ok := x["items"].([]any); ok {
			list = l
		} else if l, ok := x["accounts"].([]any); ok {
			list = l
		}
	}
	var out []hsAccount
	for _, e := range list {
		m, _ := e.(map[string]any)
		id, _ := m["accountID"].(string)
		if id == "" {
			continue
		}
		a := hsAccount{accountID: id}
		if b, ok := m["bridge"].(map[string]any); ok {
			a.bridgeType, _ = b["type"].(string)
		}
		a.network, _ = m["network"].(string)
		if u, ok := m["user"].(map[string]any); ok {
			a.userID, _ = u["id"].(string)
		}
		out = append(out, a)
	}
	return out
}

type hsChat struct {
	id, title, network       string
	isDirect, muted, lowPrio bool
}

type hsMessage struct {
	id, chatID, accountID, senderID, senderName, typ, text string
	ts                                                     time.Time
	isSender, isHidden, isDeleted                          bool
	mentions                                               []string
}

func (m hsMessage) key() string { return m.chatID + "/" + m.id }

type hsSearch struct {
	messages             []hsMessage // oldest first
	chats                map[string]hsChat
	hasMore, newestFirst bool
	oldestCursor         string
	newestCursor         string
}

// hsParseDate is BeeperClient.parseDate: ISO 8601 with fractional seconds, or without.
func hsParseDate(s string) (time.Time, bool) {
	for _, layout := range []string{"2006-01-02T15:04:05.000Z07:00", "2006-01-02T15:04:05Z07:00"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

// hsParseSearch is BeeperClient.parseSearch: items and the chats they are in; a message without an id, a chat or
// a readable time is skipped; the rest come back oldest first.
func hsParseSearch(m map[string]any) hsSearch {
	out := hsSearch{chats: map[string]hsChat{}}
	chats, _ := m["chats"].(map[string]any)
	for key, v := range chats {
		c, ok := v.(map[string]any)
		if !ok {
			continue
		}
		id, _ := c["id"].(string)
		if id == "" {
			id = key
		}
		typ, _ := c["type"].(string)
		ch := hsChat{id: id, isDirect: typ == "single"}
		ch.title, _ = c["title"].(string)
		ch.network, _ = c["network"].(string)
		ch.muted, _ = c["isMuted"].(bool)
		ch.lowPrio, _ = c["isLowPriority"].(bool)
		out.chats[id] = ch
	}
	items, _ := m["items"].([]any)
	var inOrder []hsMessage
	for _, v := range items {
		e, _ := v.(map[string]any)
		id, _ := e["id"].(string)
		chatID, _ := e["chatID"].(string)
		stamp, _ := e["timestamp"].(string)
		ts, ok := hsParseDate(stamp)
		if id == "" || chatID == "" || !ok {
			continue
		}
		msg := hsMessage{id: id, chatID: chatID, ts: ts, typ: "TEXT"}
		msg.accountID, _ = e["accountID"].(string)
		msg.senderID, _ = e["senderID"].(string)
		msg.senderName, _ = e["senderName"].(string)
		if t, ok := e["type"].(string); ok {
			msg.typ = strings.ToUpper(t)
		}
		msg.text, _ = e["text"].(string)
		msg.isSender, _ = e["isSender"].(bool)
		msg.isHidden, _ = e["isHidden"].(bool)
		msg.isDeleted, _ = e["isDeleted"].(bool)
		if ms, ok := e["mentions"].([]any); ok {
			for _, x := range ms {
				if s, ok := x.(string); ok {
					msg.mentions = append(msg.mentions, s)
				}
			}
		}
		inOrder = append(inOrder, msg)
	}
	out.newestFirst = len(inOrder) == 0 || !inOrder[0].ts.Before(inOrder[len(inOrder)-1].ts)
	out.messages = slices.Clone(inOrder)
	sort.SliceStable(out.messages, func(i, j int) bool {
		a, b := out.messages[i], out.messages[j]
		if !a.ts.Equal(b.ts) {
			return a.ts.Before(b.ts)
		}
		return a.key() < b.key()
	})
	out.hasMore, _ = m["hasMore"].(bool)
	out.oldestCursor, _ = m["oldestCursor"].(string)
	out.newestCursor, _ = m["newestCursor"].(string)
	return out
}

// hsShouldAnnounce is BeeperClient.shouldAnnounce with the default mode (direct messages, and group messages that
// mention you) and mute_own_messages on.
func hsShouldAnnounce(m hsMessage, chat *hsChat, own map[string]bool) bool {
	if m.typ == "REACTION" || m.isHidden || m.isDeleted {
		return false
	}
	if m.isSender || own[m.senderID] {
		return false
	}
	if chat != nil && (chat.muted || chat.lowPrio) {
		return false
	}
	if chat != nil && chat.isDirect {
		return true
	}
	return slices.Contains(m.mentions, "@room") || slices.ContainsFunc(m.mentions, func(id string) bool { return own[id] })
}

// hsSpokenText is BeeperClient.spokenText.
func hsSpokenText(m hsMessage) string {
	text := strings.Join(strings.Fields(m.text), " ")
	sent := map[string]string{
		"IMAGE": "sent a photo", "VIDEO": "sent a video", "VOICE": "sent a voice message", "AUDIO": "sent an audio file",
		"FILE": "sent a file", "STICKER": "sent a sticker", "LOCATION": "shared a location",
	}[m.typ]
	switch {
	case sent == "":
		return text
	case text == "":
		return sent
	}
	return sent + ": " + text
}

// restGet is GET path?query on the local API with the headers given (Host is set on the request itself).
func restGet(t *testing.T, w *world, method, path string, query url.Values, headers map[string]string) (int, []byte) {
	t.Helper()
	u := strings.TrimSuffix(w.url, localapi.MCPPath) + path
	if len(query) > 0 {
		u += "?" + query.Encode()
	}
	req, err := http.NewRequest(method, u, nil)
	require.NoError(t, err)
	req.Header.Set("Accept", "application/json")
	for k, v := range headers {
		if k == "Host" {
			req.Host = v
			continue
		}
		req.Header.Set(k, v)
	}
	resp, err := (&http.Client{Transport: &http.Transport{DisableKeepAlives: true}}).Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	for k := range resp.Header {
		require.False(t, strings.HasPrefix(strings.ToLower(k), "access-control-"), "no CORS header, ever: %s", k)
	}
	return resp.StatusCode, b
}

// homeSpeakerQuery is the query HomeSpeaker sends each poll (BeeperClient.messages), with mute_own_messages on.
func homeSpeakerQuery(after time.Time, limit int) url.Values {
	return url.Values{
		"dateAfter":          {after.UTC().Format("2006-01-02T15:04:05.000Z07:00")},
		"limit":              {fmt.Sprint(limit)},
		"includeMuted":       {"false"},
		"excludeLowPriority": {"true"},
		"sender":             {"others"},
	}
}

// insert stores one message, as a bridge would.
func insert(t *testing.T, s *store.Store, room, id, sender string, ts time.Time, content map[string]any) {
	t.Helper()
	b, err := json.Marshal(content)
	require.NoError(t, err)
	ins, err := s.InsertEvent(context.Background(), store.Event{
		RoomID: room, EventID: id, Sender: sender, Type: "m.room.message", Content: b, TS: ts, Status: "sent",
	})
	require.NoError(t, err)
	require.True(t, ins)
}

const (
	me      = "@me:courier.local"
	contact = "@whatsapp_contact:courier.local"
)

// restWorld is a world with, beside the fake network's chat, a direct chat, a group, a muted chat and a
// low-priority one, each holding synthetic messages, all newer than start; and one older message.
type restWorld struct {
	*world
	start                    time.Time
	dm, group, muted, low    string
	edited, deleted, tooOld  string
	atStart                  string // sent at exactly start: not strictly after it
	image, voice, own        string
	mention, everyone, plain string
}

func newRESTWorld(t *testing.T) *restWorld {
	t.Helper()
	w := &restWorld{world: newWorld(t, 1), dm: "!dm:courier.local", group: "!group:courier.local", muted: "!muted:courier.local", low: "!low:courier.local"}
	ctx := context.Background()
	for _, r := range []store.Room{
		{ID: w.dm, Network: "whatsapp", Name: "A contact", IsDirect: true},
		{ID: w.group, Network: "whatsapp", Name: "A group"},
		{ID: w.muted, Network: "whatsapp", Name: "A muted contact", IsDirect: true},
		{ID: w.low, Network: "whatsapp", Name: "A quiet contact", IsDirect: true},
	} {
		require.NoError(t, w.s.UpsertRoom(ctx, r))
	}
	require.NoError(t, w.s.SetMuted(ctx, w.muted, true))
	_, err := w.s.SetLowPriority(ctx, []string{w.low}, true)
	require.NoError(t, err)

	w.start = time.Now().Add(time.Hour).Truncate(time.Millisecond) // after the fake network's own message
	at := func(i int) time.Time { return w.start.Add(time.Duration(i) * time.Second) }
	text := func(body string) map[string]any { return map[string]any{"msgtype": "m.text", "body": body} }

	w.tooOld, w.atStart = "$old", "$at-start"
	insert(t, w.s, w.dm, w.tooOld, contact, w.start.Add(-time.Minute), text("before the window"))
	insert(t, w.s, w.dm, w.atStart, contact, w.start, text("exactly at the start"))
	w.plain = "$plain"
	insert(t, w.s, w.dm, "$dm-text", contact, at(1), text("hello there"))
	w.image = "$image"
	insert(t, w.s, w.dm, w.image, contact, at(2), map[string]any{
		"msgtype": "m.image", "body": "a caption", "filename": "photo.jpg", "info": map[string]any{"mimetype": "image/jpeg"},
	})
	w.voice = "$voice"
	insert(t, w.s, w.dm, w.voice, contact, at(3), map[string]any{
		"msgtype": "m.audio", "body": "voice.ogg", "org.matrix.msc3245.voice": map[string]any{},
	})
	w.mention = "$mention"
	insert(t, w.s, w.group, w.mention, contact, at(4), map[string]any{
		"msgtype": "m.text", "body": "a question for you", "m.mentions": map[string]any{"user_ids": []string{me}},
	})
	w.everyone = "$everyone"
	insert(t, w.s, w.group, w.everyone, contact, at(5), map[string]any{
		"msgtype": "m.text", "body": "news for everyone", "m.mentions": map[string]any{"room": true},
	})
	insert(t, w.s, w.group, w.plain, contact, at(6), text("chatter nobody is asked about"))
	w.own = "$own"
	insert(t, w.s, w.group, w.own, me, at(7), text("my own words"))
	w.edited = "$edited"
	insert(t, w.s, w.dm, w.edited, contact, at(8), text("first words"))
	w.deleted = "$deleted"
	insert(t, w.s, w.dm, w.deleted, contact, at(9), text("words taken back"))
	insert(t, w.s, w.muted, "$in-muted", contact, at(10), text("from a muted chat"))
	insert(t, w.s, w.low, "$in-low", contact, at(11), text("from a low priority chat"))

	room := w.room
	w.room = w.dm // edit and unsend act on w.room
	w.world.edit(t, w.edited, "latest words")
	w.unsend(t, w.deleted)
	w.room = room
	return w
}

func searchPage(t *testing.T, w *world, secret string, q url.Values) hsSearch {
	t.Helper()
	code, body := restGet(t, w, http.MethodGet, localapi.MessagesSearchPath, q, map[string]string{"Authorization": "Bearer " + secret})
	require.Equal(t, http.StatusOK, code, string(body))
	var m map[string]any
	require.NoError(t, json.Unmarshal(body, &m), string(body))
	return hsParseSearch(m)
}

// GET /v1/accounts answers in the shape HomeSpeaker reads: its accounts, each with the network's bridge type and
// me as the user, so HomeSpeaker can tell my mentions and my messages.
func TestRESTAccountsReadAsHomeSpeakerReadsThem(t *testing.T) {
	w := newWorld(t, 1)
	_, secret := w.token(t, false)
	code, body := restGet(t, w, http.MethodGet, localapi.AccountsPath, nil, map[string]string{"Authorization": "Bearer " + secret})
	require.Equal(t, http.StatusOK, code, string(body))

	var v any
	require.NoError(t, json.Unmarshal(body, &v))
	_, isList := v.([]any)
	require.True(t, isList, "a list, as the reference app answers: %s", body)
	accounts := hsParseAccounts(v)
	require.Equal(t, []hsAccount{{accountID: string(w.waLogin.ID), bridgeType: "whatsapp", network: "WhatsApp", userID: me}}, accounts)

	var raw []map[string]any
	require.NoError(t, json.Unmarshal(body, &raw))
	require.Equal(t, "CONNECTED", raw[0]["status"])
	require.Equal(t, map[string]any{"id": me, "isSelf": true, "fullName": "Test Account"}, raw[0]["user"])
	require.Equal(t, map[string]any{"id": "whatsapp", "type": "whatsapp", "provider": "local"}, raw[0]["bridge"])
}

// One poll's query, as HomeSpeaker sends it, read as HomeSpeaker reads the answer: the messages strictly after
// dateAfter from chats that aren't muted or low priority, others' only, each as it reads now (an edit's latest
// words; a deleted one never), with its type and mentions; and what HomeSpeaker would then say.
func TestRESTSearchReadsAsHomeSpeakerReadsIt(t *testing.T) {
	w := newRESTWorld(t)
	_, secret := w.token(t, false)
	code, body := restGet(t, w.world, http.MethodGet, localapi.AccountsPath, nil, map[string]string{"Authorization": "Bearer " + secret})
	require.Equal(t, http.StatusOK, code)
	var v any
	require.NoError(t, json.Unmarshal(body, &v))
	own := map[string]bool{}
	for _, a := range hsParseAccounts(v) {
		own[a.userID] = true
	}

	page := searchPage(t, w.world, secret, homeSpeakerQuery(w.start, 20))
	require.False(t, page.hasMore)
	require.True(t, page.newestFirst, "newest first, as the reference app sends it")
	var got []string
	byID := map[string]hsMessage{}
	for _, m := range page.messages {
		got = append(got, m.id)
		byID[m.id] = m
		require.Equal(t, string(w.waLogin.ID), m.accountID, "every chat is the one account's")
		require.Contains(t, page.chats, m.chatID, "every message's chat is in chats")
	}
	require.Equal(t, []string{"$dm-text", w.image, w.voice, w.mention, w.everyone, w.plain, w.edited}, got,
		"oldest first once read; not the one before or at dateAfter, my own, the deleted one, or the muted and low-priority chats'")

	require.Equal(t, "TEXT", byID["$dm-text"].typ)
	require.Equal(t, "IMAGE", byID[w.image].typ)
	require.Equal(t, "a caption", byID[w.image].text)
	require.Equal(t, "VOICE", byID[w.voice].typ)
	require.Equal(t, "latest words", byID[w.edited].text, "an edit reads as its latest words")
	require.Equal(t, []string{me}, byID[w.mention].mentions)
	require.Equal(t, []string{"@room"}, byID[w.everyone].mentions)
	require.Equal(t, contact, byID["$dm-text"].senderID)
	require.True(t, page.chats[w.dm].isDirect)
	require.False(t, page.chats[w.group].isDirect)
	require.Equal(t, "A group", page.chats[w.group].title)
	require.Equal(t, "WhatsApp", page.chats[w.group].network)

	spoken := map[string]string{}
	for _, m := range page.messages {
		chat, ok := page.chats[m.chatID]
		require.True(t, ok)
		if hsShouldAnnounce(m, &chat, own) {
			spoken[m.id] = hsSpokenText(m)
		}
	}
	require.Equal(t, map[string]string{
		"$dm-text": "hello there", w.image: "sent a photo: a caption", w.voice: "sent a voice message",
		w.mention: "a question for you", w.everyone: "news for everyone", w.edited: "latest words",
	}, spoken, "direct messages and the group messages that mention me; not the group's other chatter")

	// Without sender=others, includeMuted=false and excludeLowPriority, those come back too: the filters are
	// Vitruvian Courier's, not HomeSpeaker's.
	all := searchPage(t, w.world, secret, url.Values{"dateAfter": {w.start.UTC().Format(time.RFC3339Nano)}, "excludeLowPriority": {"false"}})
	var ids []string
	for _, m := range all.messages {
		ids = append(ids, m.id)
		if m.id == w.own {
			require.True(t, m.isSender)
			require.Equal(t, me, m.senderID)
		}
	}
	require.Subset(t, ids, []string{w.own, "$in-muted", "$in-low"})
	require.NotContains(t, ids, w.deleted)
}

// HomeSpeaker reads a poll page by page (BeeperClient.allMessages): it carries on from each page's oldest cursor
// going before (the pages come newest first) until hasMore is false. Read so, small pages give every message
// once, the same as one big page.
func TestRESTSearchPagesAsHomeSpeakerPagesIt(t *testing.T) {
	w := newRESTWorld(t)
	_, secret := w.token(t, false)
	whole := searchPage(t, w.world, secret, homeSpeakerQuery(w.start, 20))

	seen := map[string]bool{}
	var order []string
	used := map[string]bool{}
	q := homeSpeakerQuery(w.start, 2)
	for pages := 0; ; pages++ {
		require.Less(t, pages, 20, "paging must end")
		p := searchPage(t, w.world, secret, q)
		require.LessOrEqual(t, len(p.messages), 2)
		for _, m := range p.messages {
			require.False(t, seen[m.key()], "no message twice: %s", m.id)
			seen[m.key()] = true
			order = append(order, m.id)
		}
		if !p.hasMore {
			break
		}
		next := p.oldestCursor
		dir := "before"
		if !p.newestFirst {
			next, dir = p.newestCursor, "after"
		}
		require.NotEmpty(t, next)
		require.False(t, used[next], "a cursor is never handed out twice")
		used[next] = true
		q.Set("cursor", next)
		q.Set("direction", dir)
	}
	var want []string
	for _, m := range whole.messages {
		want = append(want, m.id)
	}
	require.ElementsMatch(t, want, order)

	// The reference app's most is 20 a page: more is read as 20.
	q = homeSpeakerQuery(w.start.Add(-24*time.Hour), 500)
	q.Set("sender", "")
	q.Set("excludeLowPriority", "false")
	q.Set("includeMuted", "true")
	for i := range 25 {
		insert(t, w.s, w.dm, fmt.Sprintf("$many%d", i), contact, w.start.Add(time.Minute+time.Duration(i)*time.Second), map[string]any{"msgtype": "m.text", "body": "one of many"})
	}
	p := searchPage(t, w.world, secret, q)
	require.Len(t, p.messages, 20)
	require.True(t, p.hasMore)
}

func TestRESTSearchParameters(t *testing.T) {
	w := newRESTWorld(t)
	_, secret := w.token(t, false)
	auth := map[string]string{"Authorization": "Bearer " + secret}
	after := w.start.UTC().Format(time.RFC3339)

	byChat := searchPage(t, w.world, secret, url.Values{"dateAfter": {after}, "chatIDs[]": {w.group}})
	for _, m := range byChat.messages {
		require.Equal(t, w.group, m.chatID)
	}
	require.Len(t, byChat.messages, 4)
	singles := searchPage(t, w.world, secret, url.Values{"dateAfter": {after}, "chatType": {"single"}, "sender": {"others"}})
	for _, m := range singles.messages {
		require.True(t, singles.chats[m.chatID].isDirect)
	}
	words := searchPage(t, w.world, secret, url.Values{"query": {"caption"}})
	require.Len(t, words.messages, 1)
	require.Equal(t, w.image, words.messages[0].id)
	none := searchPage(t, w.world, secret, url.Values{"dateAfter": {after}, "accountIDs": {"no-such-account"}})
	require.Empty(t, none.messages)

	for _, tc := range []struct {
		q    url.Values
		want string
	}{
		{url.Values{}, "Give a query, or a filter"},
		{url.Values{"dateAfter": {"yesterday"}}, "dateAfter must be a date"},
		{url.Values{"dateAfter": {after}, "includeMuted": {"maybe"}}, "includeMuted must be true or false"},
		{url.Values{"dateAfter": {after}, "limit": {"lots"}}, "limit must be a whole number"},
		{url.Values{"dateAfter": {after}, "chatType": {"channel"}}, "chatType must be group or single"},
		{url.Values{"dateAfter": {after}, "cursor": {"x"}}, "cursor"},
		{url.Values{"dateAfter": {after}, "direction": {"after"}}, "direction after needs a cursor"},
	} {
		code, body := restGet(t, w.world, http.MethodGet, localapi.MessagesSearchPath, tc.q, auth)
		require.Equal(t, http.StatusBadRequest, code, "%v: %s", tc.q, body)
		var e map[string]string
		require.NoError(t, json.Unmarshal(body, &e))
		require.Equal(t, "bad_request", e["error"])
		require.Contains(t, e["message"], tc.want, "HomeSpeaker shows message")
	}

	// Read only: nothing but GET (and HEAD).
	for _, method := range []string{http.MethodPost, http.MethodPut, http.MethodDelete, http.MethodPatch} {
		for _, path := range []string{localapi.AccountsPath, localapi.MessagesSearchPath} {
			code, _ := restGet(t, w.world, method, path, nil, auth)
			require.Equal(t, http.StatusMethodNotAllowed, code, "%s %s", method, path)
		}
	}
	code, _ := restGet(t, w.world, http.MethodHead, localapi.AccountsPath, nil, auth)
	require.Equal(t, http.StatusOK, code)
	// Only these two of the reference app's REST API are served.
	code, _ = restGet(t, w.world, http.MethodGet, "/v1/chats", nil, auth)
	require.Equal(t, http.StatusNotFound, code)
}

// The REST endpoints take the MCP endpoint's tokens, and nothing else: no token, a wrong one, another scheme or a
// revoked one is 401, as HomeSpeaker reads it (its "token refused").
func TestRESTNeedsAToken(t *testing.T) {
	w := storeOnly(t)
	tok, secret := w.token(t, false)
	for _, path := range []string{localapi.AccountsPath, localapi.MessagesSearchPath + "?dateAfter=2026-11-01T00:00:00Z"} {
		u, err := url.Parse(path)
		require.NoError(t, err)
		code, body := restGet(t, w, http.MethodGet, u.Path, u.Query(), nil)
		require.Equal(t, http.StatusUnauthorized, code, "no token: %s", path)
		require.JSONEq(t, `{"error":"unauthorized"}`, string(body))
		for _, auth := range []string{"Bearer courier_wrong", "Bearer " + secret + "x", "Basic " + secret, secret, "Bearer "} {
			code, _ = restGet(t, w, http.MethodGet, u.Path, u.Query(), map[string]string{"Authorization": auth})
			require.Equal(t, http.StatusUnauthorized, code, "a wrong token: %s", path)
		}
		code, body = restGet(t, w, http.MethodGet, u.Path, u.Query(), map[string]string{"Authorization": "Bearer " + secret})
		require.Equal(t, http.StatusOK, code, "the right token: %s %s", path, body)
	}

	require.NoError(t, w.s.RevokeAPIToken(context.Background(), tok.ID))
	code, body := restGet(t, w, http.MethodGet, localapi.AccountsPath, nil, map[string]string{"Authorization": "Bearer " + secret})
	require.Equal(t, http.StatusUnauthorized, code, "revoked")
	require.JSONEq(t, `{"error":"unauthorized"}`, string(body))
}

// The Host and Origin guards hold for the REST endpoints as for MCP: with Remote Access off, only a loopback Host
// on our port; with it on, any Host; and never a browser.
func TestRESTKeepsTheHostAndOriginGuards(t *testing.T) {
	w := storeOnly(t)
	_, secret := w.token(t, false)
	auth := "Bearer " + secret
	port := w.api.Status().Port

	for _, host := range []string{"evil.example", "my-mac.local:" + fmt.Sprint(port), "10.0.0.2:" + fmt.Sprint(port), "127.0.0.1:1"} {
		code, body := restGet(t, w, http.MethodGet, localapi.AccountsPath, nil, map[string]string{"Authorization": auth, "Host": host})
		require.Equal(t, http.StatusForbidden, code, "Remote Access off: Host %s", host)
		require.JSONEq(t, `{"error":"forbidden"}`, string(body))
	}
	for _, host := range []string{"localhost:" + fmt.Sprint(port), "127.0.0.1:" + fmt.Sprint(port), "[::1]:" + fmt.Sprint(port)} {
		code, _ := restGet(t, w, http.MethodGet, localapi.AccountsPath, nil, map[string]string{"Authorization": auth, "Host": host})
		require.Equal(t, http.StatusOK, code, "Host %s", host)
	}
	code, _ := restGet(t, w, http.MethodGet, localapi.AccountsPath, nil, map[string]string{"Authorization": auth, "Origin": "https://evil.example"})
	require.Equal(t, http.StatusForbidden, code, "never from a browser")

	st := w.api.Apply(context.Background(), localapi.Config{Enabled: true, Port: port, Remote: true})
	require.True(t, st.Listening, st.Error)
	code, _ = restGet(t, w, http.MethodGet, localapi.AccountsPath, nil, map[string]string{"Authorization": auth, "Host": "my-mac.local:" + fmt.Sprint(port)})
	require.Equal(t, http.StatusOK, code, "Remote Access on: any Host, with a token")
	code, _ = restGet(t, w, http.MethodGet, localapi.AccountsPath, nil, map[string]string{"Host": "my-mac.local:" + fmt.Sprint(port)})
	require.Equal(t, http.StatusUnauthorized, code, "and still a token")
}
